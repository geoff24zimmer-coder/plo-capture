import 'package:test/test.dart';
import 'package:plo_capture/equity/allin_ev.dart';
import 'package:plo_capture/hand_loader.dart';
import 'package:plo_capture/hand_recorder.dart';
import 'package:plo_capture/plo_engine.dart';

/// 2/5 cash, 4-handed. Seats: 1=BTN (hero), 2=SB, 3=BB, 4=UTG.
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

const positions = {1: 'BTN', 2: 'SB', 3: 'BB', 4: 'UTG'};

/// Play [moves] on [cfg], serialise exactly as capture does, load it back.
LoadedHand play(
  HandConfig cfg,
  List<(int, ActionType, int?)> moves, {
  required List<String> hero,
  required Map<int, List<String>> shown,
  required List<String> board,
  required List<List<int>> potWinners,
}) {
  final e = cfg.buildEngine();
  for (final (s, a, amt) in moves) {
    e.apply(s, a, amount: amt);
  }
  final json = buildHandJson(
    engine: e,
    cfg: cfg,
    positions: positions,
    heroCards: hero,
    flop: board.take(3).toList(),
    turnCard: board.length > 3 ? board[3] : null,
    riverCard: board.length > 4 ? board[4] : null,
    potWinners: potWinners,
    shownCards: shown,
  );
  return loadHand(json);
}

void main() {
  // Turn all-in, heads-up: hero's nut-ish flush vs a set of sevens that fills
  // up on 10 of the 40 unseen rivers.
  List<(int, ActionType, int?)> turnJam() => [
        (4, ActionType.fold, null),
        (1, ActionType.call, null),
        (2, ActionType.fold, null),
        (3, ActionType.check, null),
        (3, ActionType.check, null), // flop
        (1, ActionType.check, null),
        (3, ActionType.bet, 1200), // turn
        (1, ActionType.raise, 4800),
        (3, ActionType.raise, 9500), // all-in
        (1, ActionType.call, null),
      ];

  test('turn all-in: exact EV from countable outs', () {
    final h = play(
      cfg4({1: 10000, 2: 10000, 3: 10000, 4: 10000}),
      turnJam(),
      hero: ['Qh', 'Jh', '3s', '4d'],
      shown: {3: ['7s', '7d', '9c', '8c']},
      board: ['Ah', 'Kh', '7h', '2c', 'Ad'], // river fills villain up
      potWinners: [
        [3]
      ],
    );
    final ev = computeAllInEv(h);
    expect(ev.status, AllInStatus.ok);
    expect(ev.street, Street.turn);
    expect(ev.exact, isTrue);
    expect(ev.equity[1], closeTo(0.75, 1e-12));
    // Pot 20,200 (10,000 each + SB's 200 dead): 0.75 × 20,200 − 10,000.
    expect(ev.heroEv, 5150);
    expect(ev.heroActual, -10000);
    expect(ev.luck, -15150);
  });

  test('PLO5: the same turn all-in with five cards each', () {
    final cfg = cfg4({1: 10000, 2: 10000, 3: 10000, 4: 10000});
    final h = play(
      HandConfig(
        initialStacks: cfg.initialStacks,
        buttonSeat: cfg.buttonSeat,
        smallBlind: cfg.smallBlind,
        bigBlind: cfg.bigBlind,
        forcedBets: cfg.forcedBets,
        straddleRule: cfg.straddleRule,
        heroSeat: cfg.heroSeat,
        variant: 'plo5',
      ),
      turnJam(),
      hero: ['Qh', 'Jh', '3s', '4d', '5c'],
      shown: {3: ['7s', '7d', '9c', '8c', '6c']},
      board: ['Ah', 'Kh', '7h', '2c', 'Ad'],
      potWinners: [
        [3]
      ],
    );
    expect(h.cfg.variant, 'plo5'); // round-trips through the stored JSON
    expect(h.heroCards, hasLength(5));
    final ev = computeAllInEv(h);
    expect(ev.status, AllInStatus.ok);
    expect(ev.exact, isTrue);
    // 38 unseen rivers; the set fills up on 10 (3 A, 3 K, 3 deuces, 7c).
    expect(ev.equity[1], closeTo(28 / 38, 1e-12));
  });

  test('PLO5: a shown 4-card hand is not enough to score', () {
    final cfg = cfg4({1: 10000, 2: 10000, 3: 10000, 4: 10000});
    final h = play(
      HandConfig(
        initialStacks: cfg.initialStacks,
        buttonSeat: cfg.buttonSeat,
        smallBlind: cfg.smallBlind,
        bigBlind: cfg.bigBlind,
        forcedBets: cfg.forcedBets,
        straddleRule: cfg.straddleRule,
        heroSeat: cfg.heroSeat,
        variant: 'plo5',
      ),
      turnJam(),
      hero: ['Qh', 'Jh', '3s', '4d', '5c'],
      shown: {3: ['7s', '7d', '9c', '8c']},
      board: ['Ah', 'Kh', '7h', '2c', 'Ad'],
      potWinners: [
        [3]
      ],
    );
    expect(computeAllInEv(h).status, AllInStatus.missingCards);
  });

  test('side pots are scored pot by pot, other hands dead', () {
    // SB (2,000) jams the turn, BB raises, hero (BTN) re-jams, BB calls:
    // main 6,000 three-way, side 16,000 hero vs BB.
    final h = play(
      cfg4({1: 10000, 2: 2000, 3: 10000, 4: 10000}),
      [
        (4, ActionType.fold, null),
        (1, ActionType.call, null),
        (2, ActionType.call, null),
        (3, ActionType.check, null),
        (2, ActionType.check, null), // flop
        (3, ActionType.check, null),
        (1, ActionType.check, null),
        (2, ActionType.bet, 1500), // turn: SB all-in
        (3, ActionType.raise, 6000),
        (1, ActionType.raise, 9500), // hero all-in
        (3, ActionType.call, null),
      ],
      hero: ['Qh', 'Jh', '3s', '4d'],
      shown: {
        2: ['As', 'Ks', 'Td', '6d'],
        3: ['7s', '7d', '9c', '8c'],
      },
      board: ['Ah', 'Kh', '7h', '2c', '9d'],
      potWinners: [
        [1],
        [1]
      ],
    );
    final ev = computeAllInEv(h);
    expect(ev.status, AllInStatus.ok);
    // 36 unseen rivers. Main: SB fills up on Ad Ac Kd Kc (AAAKK beats 777AA),
    // BB on 2h 2d 2s 7c, hero the other 28. Side (SB's cards dead): BB's
    // A/K/2/7c outs are the same 8 → hero 28/36 in both.
    expect(ev.equity[1], closeTo(28 / 36, 1e-12));
    expect(ev.equity[2], closeTo(4 / 36, 1e-12));
    expect(ev.heroEv, (22000 * 28 / 36).round() - 10000); // 7,111
    expect(ev.heroActual, 12000);
  });

  test('preflop all-in uses a seeded simulation (stable per hand)', () {
    final h = play(
      cfg4({1: 5000, 2: 100000, 3: 5000, 4: 100000}),
      [
        (4, ActionType.fold, null),
        (1, ActionType.raise, 1700),
        (2, ActionType.fold, null),
        (3, ActionType.raise, 5000), // all-in
        (1, ActionType.call, null),
      ],
      hero: ['As', 'Ah', 'Ks', 'Kh'],
      shown: {3: ['Kd', 'Kc', 'Qd', 'Qc']},
      board: ['2c', '7d', 'Jh', '4s', '3h'],
      potWinners: [
        [1]
      ],
    );
    final a = computeAllInEv(h), b = computeAllInEv(h);
    expect(a.street, Street.preflop);
    expect(a.exact, isFalse);
    expect(a.equity[1], closeTo(0.691, 0.015)); // published exact 69.1%
    expect(a.heroEv, b.heroEv); // same hand → same number
    // 10,200 pot: ~0.691 × 10,200 − 5,000 ≈ 2,048.
    expect(a.heroEv, closeTo(2048, 160));
    expect(a.heroActual, 5200);
  });

  test('a villain who mucked leaves the EV unknown, not invented', () {
    final h = play(
      cfg4({1: 10000, 2: 10000, 3: 10000, 4: 10000}),
      turnJam(),
      hero: ['Qh', 'Jh', '3s', '4d'],
      shown: const {},
      board: ['Ah', 'Kh', '7h', '2c', '9d'],
      potWinners: [
        [1]
      ],
    );
    expect(computeAllInEv(h).status, AllInStatus.missingCards);
  });

  test('money going in on the river is not an all-in spot', () {
    final h = play(
      cfg4({1: 10000, 2: 10000, 3: 10000, 4: 10000}),
      [
        (4, ActionType.fold, null),
        (1, ActionType.call, null),
        (2, ActionType.fold, null),
        (3, ActionType.check, null),
        for (final _ in [0, 1, 2]) ...[
          (3, ActionType.check, null),
          (1, ActionType.check, null),
        ],
      ],
      hero: ['Qh', 'Jh', '3s', '4d'],
      shown: {3: ['7s', '7d', '9c', '8c']},
      board: ['Ah', 'Kh', '7h', '2c', '9d'],
      potWinners: [
        [1]
      ],
    );
    expect(computeAllInEv(h).status, AllInStatus.notAllIn);
  });

  test('same all-in, different run-outs: same EV, different result', () {
    LoadedHand jam(Map<int, List<String>> shown, List<String> board,
            int winner) =>
        play(cfg4({1: 10000, 2: 10000, 3: 10000, 4: 10000}), turnJam(),
            hero: ['Qh', 'Jh', '3s', '4d'],
            shown: shown,
            board: board,
            potWinners: [
              [winner]
            ]);
    final lost = computeAllInEv(jam(
        {3: ['7s', '7d', '9c', '8c']}, ['Ah', 'Kh', '7h', '2c', 'Ad'], 3));
    final won = computeAllInEv(jam(
        {3: ['7s', '7d', '9c', '8c']}, ['Ah', 'Kh', '7h', '2c', '9d'], 1));
    final mucked =
        computeAllInEv(jam(const {}, ['Ah', 'Kh', '7h', '2c', '9d'], 1));
    expect(lost.heroEv, 5150);
    expect(won.heroEv, 5150);
    expect(lost.heroActual, -10000);
    expect(won.heroActual, 10200);
    expect(mucked.status, AllInStatus.missingCards);
  });
}
