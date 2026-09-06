import 'package:test/test.dart';
import 'package:plo_capture/plo_engine.dart';
import 'package:plo_capture/hand_recorder.dart';

/// 2/5 cash, 4-handed for compact all-in scenarios.
/// Seats: 1=BTN, 2=SB, 3=BB, 4=UTG.
HandConfig cfg4({
  required Map<int, int> stacks,
  int heroSeat = 1,
}) =>
    HandConfig(
      initialStacks: stacks,
      buttonSeat: 1,
      smallBlind: 200,
      bigBlind: 500,
      forcedBets: const [
        ForcedBet(2, PostType.sb, 200),
        ForcedBet(3, PostType.bb, 500),
      ],
      straddleRule: StraddleActionRule.sbFirst,
      heroSeat: heroSeat,
    );

const positions4 = {1: 'BTN', 2: 'SB', 3: 'BB', 4: 'UTG'};

void main() {
  group('computePots', () {
    test('fold-out: uncalled raise returned, pot holds only called chips', () {
      final cfg = cfg4(
          stacks: {1: 100000, 2: 100000, 3: 100000, 4: 100000});
      final e = cfg.buildEngine();
      e.apply(4, ActionType.raise, amount: 1500);
      e.apply(1, ActionType.fold);
      e.apply(2, ActionType.fold);
      e.apply(3, ActionType.fold);
      expect(e.status, HandStatus.wonByFold);

      final b = e.computePots();
      expect(b.returnedSeat, 4);
      expect(b.returnedAmount, 1000); // 1500 beyond the BB's 500
      expect(b.pots, hasLength(1));
      expect(b.pots.single.amount, 1200); // 500 called + 200 + 500 dead
      expect(b.pots.single.eligible, [4]);
      expect(b.total + b.returnedAmount, e.pot);
    });

    test('short all-in called by a deeper stack: excess returned', () {
      // UTG all-in 1700 (exact pot max), BTN pots over the top, blinds fold.
      final cfg = cfg4(
          stacks: {1: 100000, 2: 100000, 3: 100000, 4: 1700});
      final e = cfg.buildEngine();
      e.apply(4, ActionType.raise, amount: 1700);
      e.apply(1, ActionType.raise, amount: 5800);
      e.apply(2, ActionType.fold);
      e.apply(3, ActionType.fold);
      expect(e.status, HandStatus.showdown); // both effectively all the way in

      final b = e.computePots();
      expect(b.returnedSeat, 1);
      expect(b.returnedAmount, 4100); // 5800 - 1700
      expect(b.pots, hasLength(1));
      expect(b.pots.single.amount, 4100); // 1700+1700 + 700 dead blinds
      expect(b.pots.single.eligible, [1, 4]);
      expect(b.total + b.returnedAmount, e.pot);
    });

    test('three-way all-in builds main + side with correct eligibility', () {
      // A(BTN) 20000, B(SB) 5000, C(BB) 20000. B is the short stack.
      final cfg = cfg4(
          stacks: {1: 20000, 2: 5000, 3: 20000, 4: 20000});
      final e = cfg.buildEngine();
      e.apply(4, ActionType.fold);
      e.apply(1, ActionType.raise, amount: 1500);
      e.apply(2, ActionType.call, amount: 1500);
      e.apply(3, ActionType.call, amount: 1500);
      expect(e.street, Street.flop);

      // Flop: SB jams the rest, BB calls, BTN pots, BB calls all-in.
      e.apply(2, ActionType.bet, amount: 3500); // all-in (5000 total)
      e.apply(3, ActionType.call, amount: 3500);
      e.apply(1, ActionType.raise, amount: 18500); // all-in (20000 total)
      e.apply(3, ActionType.call, amount: 18500); // capped all-in
      expect(e.status, HandStatus.showdown);
      expect(e.pot, 45000);

      final b = e.computePots();
      expect(b.returnedAmount, 0);
      expect(b.pots, hasLength(2));
      expect(b.pots[0].amount, 15000); // 5000 x 3
      expect(b.pots[0].eligible, [1, 2, 3]);
      expect(b.pots[1].amount, 30000); // 15000 x 2
      expect(b.pots[1].eligible, [1, 3]);
      expect(b.total, e.pot);
    });
  });

  group('buildHandJson pot results', () {
    Map<int, int> threeWayStacks() => {1: 20000, 2: 5000, 3: 20000, 4: 20000};

    HandEngine playThreeWayAllIn(HandConfig cfg) {
      final e = cfg.buildEngine();
      e.apply(4, ActionType.fold);
      e.apply(1, ActionType.raise, amount: 1500);
      e.apply(2, ActionType.call, amount: 1500);
      e.apply(3, ActionType.call, amount: 1500);
      e.apply(2, ActionType.bet, amount: 3500);
      e.apply(3, ActionType.call, amount: 3500);
      e.apply(1, ActionType.raise, amount: 18500);
      e.apply(3, ActionType.call, amount: 18500);
      return e;
    }

    test('side pot serialized: BB scoops main, wins side; short SB loses', () {
      final cfg = cfg4(stacks: threeWayStacks(), heroSeat: 3);
      final e = playThreeWayAllIn(cfg);
      final j = buildHandJson(
        engine: e,
        cfg: cfg,
        positions: positions4,
        heroCards: ['Ah', 'Ad', 'Kc', 'Qc'],
        flop: ['2h', '7d', 'Jc'],
        turnCard: '3s',
        riverCard: '9h',
        potWinners: [
          [3], // main
          [3], // side
        ],
      );
      final pots = (j['results'] as Map)['pots'] as List;
      expect(pots, hasLength(2));
      expect((pots[0] as Map)['pot_type'], 'main');
      expect((pots[0] as Map)['amount'], 15000);
      expect(((pots[0] as Map)['winners'] as List).single,
          {'seat': 3, 'amount_won': 15000, 'share_type': 'full'});
      expect((pots[1] as Map)['pot_type'], 'side');
      expect(((pots[1] as Map)['winners'] as List).single,
          {'seat': 3, 'amount_won': 30000, 'share_type': 'full'});
      // Hero (BB) committed 20000, wins 45000.
      expect((j['results'] as Map)['hero_net'], 25000);
    });

    test('chopped main pot splits evenly; odd remainder to first seat', () {
      final cfg = cfg4(stacks: threeWayStacks(), heroSeat: 2);
      final e = playThreeWayAllIn(cfg);
      // Rake 101 makes the main pot 14899: 3-way split 4967/4966/4966.
      final j = buildHandJson(
        engine: e,
        cfg: cfg,
        positions: positions4,
        heroCards: ['Ah', 'Ad', 'Kc', 'Qc'],
        flop: ['2h', '7d', 'Jc'],
        turnCard: '3s',
        riverCard: '9h',
        rake: 101,
        potWinners: [
          [1, 2, 3], // main chopped three ways
          [1], // side to BTN
        ],
      );
      final main = ((j['results'] as Map)['pots'] as List)[0] as Map;
      final winners = (main['winners'] as List).cast<Map>();
      expect(main['amount'], 15000); // amount is pre-rake pot size
      expect(winners.map((w) => w['seat']), [1, 2, 3]);
      expect(winners.map((w) => w['amount_won']), [4967, 4966, 4966]);
      expect(winners.map((w) => w['share_type']),
          everyElement('split'));
      // Hero (short SB): committed 5000, got back 4966.
      expect((j['results'] as Map)['hero_net'], -34);
    });

    test('unresolved pot saved winner-less; hero_net omitted', () {
      final cfg = cfg4(stacks: threeWayStacks(), heroSeat: 3);
      final e = playThreeWayAllIn(cfg);
      final j = buildHandJson(
        engine: e,
        cfg: cfg,
        positions: positions4,
        heroCards: ['Ah', 'Ad', 'Kc', 'Qc'],
        flop: ['2h', '7d', 'Jc'],
        turnCard: '3s',
        riverCard: '9h',
        potWinners: [
          [3], // main resolved
          [], // side unknown
        ],
      );
      final pots = (j['results'] as Map)['pots'] as List;
      expect((pots[1] as Map).containsKey('winners'), isFalse);
      expect((j['results'] as Map).containsKey('hero_net'), isFalse);
    });

    test('legacy winnerSeat still works: fold-out excludes uncalled chips',
        () {
      final cfg = cfg4(
          stacks: {1: 100000, 2: 100000, 3: 100000, 4: 100000},
          heroSeat: 4);
      final e = cfg.buildEngine();
      e.apply(4, ActionType.raise, amount: 1500);
      e.apply(1, ActionType.fold);
      e.apply(2, ActionType.fold);
      e.apply(3, ActionType.fold);
      final j = buildHandJson(
        engine: e,
        cfg: cfg,
        positions: positions4,
        heroCards: ['Ah', 'Ad', 'Kc', 'Qc'],
        flop: [],
        winnerSeat: 4,
      );
      final results = j['results'] as Map;
      final main = (results['pots'] as List).single as Map;
      expect(main['amount'], 1200); // called 500 + 700 dead blinds
      expect((main['winners'] as List).single['amount_won'], 1200);
      expect(results['uncalled_returned'], {'seat': 4, 'amount': 1000});
      // Hero raised to 1500, got 1000 back uncalled, won 1200: net +700.
      expect(results['hero_net'], 700);
    });
  });
}
