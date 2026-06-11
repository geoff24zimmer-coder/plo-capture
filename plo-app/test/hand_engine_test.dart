import 'package:test/test.dart';
import 'package:plo_capture/plo_engine.dart';

/// Seats mirror example-hand.json:
/// 1=MP 2=HJ 3=CO(hero) 4=BTN(straddler) 5=SB 6=BB 7=UTG 8=UTG1
HandEngine buttonStraddleHand({StraddleActionRule rule = StraddleActionRule.utgFirstStraddlerLast}) {
  return HandEngine(
    seatedPlayers: [
      PlayerState(1, 60000),
      PlayerState(2, 95000),
      PlayerState(3, 124000),
      PlayerState(4, 80000),
      PlayerState(5, 45000),
      PlayerState(6, 150000),
      PlayerState(7, 200000),
      PlayerState(8, 30000),
    ],
    buttonSeat: 4,
    bigBlind: 500,
    straddleRule: rule,
    forcedBets: const [
      ForcedBet(5, PostType.sb, 200),
      ForcedBet(6, PostType.bb, 500),
      ForcedBet(4, PostType.straddleButton, 1000),
    ],
  );
}

void main() {
  group('Button straddle hand (canonical example-hand.json)', () {
    test('preflop order opens UTG, straddler acts last', () {
      final e = buttonStraddleHand();
      expect(e.whoseTurn(), 7); // UTG first
      e.apply(7, ActionType.call, amount: 1000); // limp the straddle
      e.apply(8, ActionType.fold);
      e.apply(1, ActionType.call, amount: 1000);
      e.apply(2, ActionType.fold);

      // Hero in CO: pot 3700, call 1000 → pot raise-to must be exactly 5700.
      final la = e.legalActions();
      expect(la.seat, 3);
      expect(la.toCall, 1000);
      expect(la.maxRaiseTo, 5700);
      expect(la.minRaiseTo, 2000); // double the straddle
      expect(la.sizing!.pot, 5700);

      e.apply(3, ActionType.raise, amount: 5700);
      expect(e.whoseTurn(), 5); // SB
      e.apply(5, ActionType.fold);
      e.apply(6, ActionType.fold);
      expect(e.whoseTurn(), 4); // button straddler acts LAST
      e.apply(4, ActionType.call, amount: 5700);
      e.apply(7, ActionType.call, amount: 5700);
      e.apply(1, ActionType.fold);

      expect(e.street, Street.flop);
      expect(e.pot, 18800);
      expect(e.whoseTurn(), 7); // first active left of button postflop
    });

    test('full replay reconciles to the penny, river capped below pot max', () {
      final e = buttonStraddleHand();
      e.apply(7, ActionType.call, amount: 1000);
      e.apply(8, ActionType.fold);
      e.apply(1, ActionType.call, amount: 1000);
      e.apply(2, ActionType.fold);
      e.apply(3, ActionType.raise, amount: 5700);
      e.apply(5, ActionType.fold);
      e.apply(6, ActionType.fold);
      e.apply(4, ActionType.call, amount: 5700);
      e.apply(7, ActionType.call, amount: 5700);
      e.apply(1, ActionType.fold);

      // Flop
      e.apply(7, ActionType.check);
      final flopLa = e.legalActions();
      expect(flopLa.sizing!.threeQuarter, 14100); // 0.75 * 18800
      e.apply(3, ActionType.bet, amount: 14100);
      e.apply(4, ActionType.fold);
      e.apply(7, ActionType.call, amount: 14100);

      // Turn checks through
      expect(e.pot, 47000);
      e.apply(7, ActionType.check);
      e.apply(3, ActionType.check);

      // River: legal pot raise is 117500, hero only has 104200 behind-total.
      e.apply(7, ActionType.bet, amount: 23500);
      final la = e.legalActions();
      expect(la.seat, 3);
      expect(la.maxRaiseTo, 104200); // stack-capped below the 117500 pot max
      final shove =
          e.apply(3, ActionType.raise, amount: 104200);
      expect(shove.isAllIn, isTrue);
      e.apply(7, ActionType.call, amount: 104200);

      expect(e.status, HandStatus.showdown);
      expect(e.pot, 255400);

      // Engine log matches the hand history's cached fields.
      final riverShove = e.log.firstWhere(
          (a) => a.street == Street.river && a.action == ActionType.raise);
      expect(riverShove.potBefore, 70500);
      expect(riverShove.amountToCall, 23500);
    });

    test('sb_first house rule opens action on the small blind', () {
      final e = buttonStraddleHand(rule: StraddleActionRule.sbFirst);
      expect(e.whoseTurn(), 5); // SB first under this rule
    });
  });

  group('UTG straddle', () {
    HandEngine utgStraddle() => HandEngine(
          seatedPlayers: [
            PlayerState(1, 100000),
            PlayerState(2, 100000),
            PlayerState(3, 100000),
            PlayerState(4, 100000),
            PlayerState(5, 100000),
            PlayerState(6, 100000),
          ],
          buttonSeat: 1,
          bigBlind: 500,
          forcedBets: const [
            ForcedBet(2, PostType.sb, 200),
            ForcedBet(3, PostType.bb, 500),
            ForcedBet(4, PostType.straddleUtg, 1000),
          ],
        );

    test('action opens after the straddler; straddler holds last option', () {
      final e = utgStraddle();
      expect(e.whoseTurn(), 5);
      e.apply(5, ActionType.call, amount: 1000);
      e.apply(6, ActionType.fold);
      e.apply(1, ActionType.fold);
      e.apply(2, ActionType.fold);
      e.apply(3, ActionType.call, amount: 1000);
      // Straddler last, with the option: facing no raise, can check.
      final la = e.legalActions();
      expect(la.seat, 4);
      expect(la.canCheck, isTrue);
      expect(la.minRaiseTo, 2000);
      e.apply(4, ActionType.check);
      expect(e.street, Street.flop);
    });
  });

  group('Short all-in does not reopen raising', () {
    test('original bettor may only call or fold after a short shove', () {
      final e = HandEngine(
        seatedPlayers: [
          PlayerState(1, 50000),
          PlayerState(2, 50000),
          PlayerState(3, 8700), // the short stack
        ],
        buttonSeat: 1,
        bigBlind: 500,
        forcedBets: const [
          ForcedBet(2, PostType.sb, 200),
          ForcedBet(3, PostType.bb, 500),
        ],
      );
      // Build a real pot: button pot-raises (max must be exactly 1700).
      expect(e.legalActions().maxRaiseTo, 1700);
      e.apply(1, ActionType.raise, amount: 1700);
      e.apply(2, ActionType.call, amount: 1700);
      e.apply(3, ActionType.call, amount: 1700);
      expect(e.street, Street.flop);
      expect(e.pot, 5100);

      e.apply(2, ActionType.bet, amount: 5000);
      // Seat 3 has 7000 behind: all-in raise-to 7000, increment 2000 < 5000.
      final la3 = e.legalActions();
      expect(la3.seat, 3);
      expect(la3.maxRaiseTo, 7000); // stack-capped
      expect(la3.minRaiseTo, 7000); // short all-in is the only legal raise
      final shove = e.apply(3, ActionType.raise, amount: 7000);
      expect(shove.isAllIn, isTrue);
      e.apply(1, ActionType.fold);

      final la2 = e.legalActions();
      expect(la2.seat, 2);
      expect(la2.toCall, 2000);
      expect(la2.canCall, isTrue);
      expect(la2.canBetOrRaise, isFalse); // action NOT reopened

      // Calling closes action; remaining streets run out automatically.
      e.apply(2, ActionType.call, amount: 7000);
      expect(e.status, HandStatus.showdown);
    });
  });

  group('MTT big-blind ante (WSOP pot-limit rule)', () {
    // 100/200, 200 BB ante. Button on 1 -> SB 2, BB 3, UTG 4 first to act.
    HandEngine bbAnteHand() => HandEngine(
          seatedPlayers: [
            for (var s = 1; s <= 8; s++) PlayerState(s, 20000),
          ],
          buttonSeat: 1,
          bigBlind: 200,
          forcedBets: const [
            ForcedBet(2, PostType.sb, 100),
            ForcedBet(3, PostType.bb, 200),
            ForcedBet(3, PostType.ante, 200, isLive: false),
          ],
        );

    test('ante is held out of the preflop pot — UTG open is 3·BB + SB', () {
      final e = bbAnteHand();
      expect(e.pot, 300); // SB 100 + BB 200; the 200 ante is held aside
      expect(e.whoseTurn(), 4); // UTG
      final la = e.legalActions();
      expect(la.toCall, 200);
      expect(la.maxRaiseTo, 700); // NOT 900 — ante invisible to the preflop pot
      expect(la.sizing!.pot, 700);
    });

    test('the ante merges into the pot once the flop is dealt', () {
      final e = bbAnteHand();
      e.apply(4, ActionType.raise, amount: 700); // UTG pots
      for (final s in [5, 6, 7, 8, 1, 2]) {
        e.apply(s, ActionType.fold); // fold around to the BB
      }
      expect(e.whoseTurn(), 3);
      e.apply(3, ActionType.call, amount: 700); // BB calls -> flop
      expect(e.street, Street.flop);
      // 700 (UTG) + 700 (BB) + 100 (SB) + 200 (ante, now merged) = 1700
      expect(e.pot, 1700);
    });

    test('won preflop by folds still scoops the ante', () {
      final e = bbAnteHand();
      e.apply(4, ActionType.raise, amount: 700);
      for (final s in [5, 6, 7, 8, 1, 2]) {
        e.apply(s, ActionType.fold);
      }
      e.apply(3, ActionType.fold); // BB folds too -> UTG wins it preflop
      expect(e.status, HandStatus.wonByFold);
      // 700 (UTG) + 200 (BB) + 100 (SB) + 200 (ante) = 1200
      expect(e.pot, 1200);
    });
  });
}
