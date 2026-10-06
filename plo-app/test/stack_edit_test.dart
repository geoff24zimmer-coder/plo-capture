import 'package:test/test.dart';
import 'package:plo_capture/plo_engine.dart';
import 'package:plo_capture/hand_recorder.dart';

/// 2/5 cash, 4-handed. Seats: 1=BTN, 2=SB, 3=BB, 4=UTG.
HandConfig cfg4(Map<int, int> stacks) => HandConfig(
      initialStacks: stacks,
      buttonSeat: 1,
      smallBlind: 200,
      bigBlind: 500,
      forcedBets: const [
        ForcedBet(2, PostType.sb, 200),
        ForcedBet(3, PostType.bb, 500),
      ],
      straddleRule: StraddleActionRule.sbFirst,
      heroSeat: 1,
    );

const deep = {1: 100000, 2: 100000, 3: 100000, 4: 100000};

/// Copy of [base] with one seat's starting stack changed.
Map<int, int> withStack(Map<int, int> base, int seat, int amount) =>
    {...base, seat: amount};

void main() {
  group('replayUnchanged (per-seat stack edits)', () {
    test('editing a seat that has not acted yet keeps the hand', () {
      final e = cfg4(deep).buildEngine();
      e.apply(4, ActionType.raise, amount: 1700); // UTG pots it (max 1700)

      final r = replayUnchanged(cfg4(withStack(deep, 1, 40000)), e);
      expect(r, isNotNull);
      expect(r!.whoseTurn(), 1);
      expect(r.players[1]!.stack, 40000);
      // The new stack caps what the BTN can do from here.
      expect(r.legalActions().maxRaiseTo, lessThanOrEqualTo(40000));
    });

    test('an edit before any action rebuilds with the new stack', () {
      final e = cfg4(deep).buildEngine();
      final r = replayUnchanged(cfg4(withStack(deep, 4, 25000)), e);
      expect(r, isNotNull);
      expect(r!.players[4]!.stack, 25000);
    });

    test('a stack below what the seat already put in is refused', () {
      final e = cfg4(deep).buildEngine();
      e.apply(4, ActionType.raise, amount: 1700);
      expect(replayUnchanged(cfg4(withStack(deep, 4, 1000)), e), isNull);
    });

    test('a stack that would turn a call into an all-in is refused', () {
      final e = cfg4(deep).buildEngine();
      e.apply(4, ActionType.raise, amount: 1700);
      e.apply(1, ActionType.call); // BTN calls 1700 with chips behind
      // 1700 exactly: the same call would now be all-in.
      expect(replayUnchanged(cfg4(withStack(deep, 1, 1700)), e), isNull);
    });

    test('making an all-in player deeper is refused', () {
      final short = withStack(deep, 4, 1500);
      final e = cfg4(short).buildEngine();
      e.apply(4, ActionType.raise, amount: 1500); // UTG all-in
      expect(e.log.last.isAllIn, isTrue);
      expect(replayUnchanged(cfg4(deep), e), isNull);
    });

    test('a blind that could no longer post in full is refused', () {
      final e = cfg4(deep).buildEngine();
      expect(replayUnchanged(cfg4(withStack(deep, 3, 300)), e), isNull);
    });

    test('a folded seat can be corrected after showdown; pots unchanged', () {
      final e = cfg4(deep).buildEngine();
      e.apply(4, ActionType.raise, amount: 1700);
      e.apply(1, ActionType.fold);
      e.apply(2, ActionType.fold);
      e.apply(3, ActionType.call);
      for (final _ in Street.values.skip(1).take(3)) {
        e.apply(3, ActionType.check);
        e.apply(4, ActionType.check);
      }
      expect(e.status, HandStatus.showdown);

      final r = replayUnchanged(cfg4(withStack(deep, 1, 30000)), e);
      expect(r, isNotNull);
      expect(r!.status, HandStatus.showdown);
      expect(r.computePots().pots.single.amount,
          e.computePots().pots.single.amount);
    });

    test('replaying an unedited all-in hand is the identity', () {
      final short = withStack(deep, 4, 1500);
      final e = cfg4(short).buildEngine();
      e.apply(4, ActionType.raise, amount: 1500); // all-in
      e.apply(1, ActionType.call);
      e.apply(2, ActionType.fold);
      e.apply(3, ActionType.fold);
      expect(e.status, HandStatus.showdown);
      final r = replayUnchanged(cfg4(short), e);
      expect(r, isNotNull);
      expect(r!.status, e.status);
      expect(r.log.length, e.log.length);
    });
  });
}
