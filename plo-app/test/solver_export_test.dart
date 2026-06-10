import 'package:test/test.dart';
import 'package:plo_capture/plo_engine.dart';
import 'package:plo_capture/hand_recorder.dart';
import 'package:plo_capture/export/solver_export.dart';

/// Build a canonical hand JSON the same way the app does: configure, replay the
/// given actions through the engine, then serialize. `actions` should stop at
/// (and include) the hero's first voluntary decision — a real decision spot.
Map<String, dynamic> makeHand({
  required Map<int, int> stacks,
  required int buttonSeat,
  required int sb,
  required int bb,
  required int heroSeat,
  required List<ForcedBet> forced,
  required Map<int, String> positions,
  required List<String> heroCards,
  required List<({int seat, ActionType type, int? amount})> actions,
  StraddleActionRule rule = StraddleActionRule.sbFirst,
}) {
  final cfg = HandConfig(
    initialStacks: stacks,
    buttonSeat: buttonSeat,
    smallBlind: sb,
    bigBlind: bb,
    forcedBets: forced,
    straddleRule: rule,
    heroSeat: heroSeat,
  );
  final e = cfg.buildEngine();
  for (final a in actions) {
    e.apply(a.seat, a.type, amount: a.amount);
  }
  return buildHandJson(
    engine: e,
    cfg: cfg,
    positions: positions,
    heroCards: heroCards,
    flop: const [],
    complete: false,
  );
}

// 8-max, button on seat 1, no straddle.
const _noStrPos = {
  1: 'BTN',
  2: 'SB',
  3: 'BB',
  4: 'UTG',
  5: 'UTG1',
  6: 'MP',
  7: 'HJ',
  8: 'CO',
};
final _hundredBb = {for (var s = 1; s <= 8; s++) s: 50000}; // $500 @ $5 bb

List<({int seat, ActionType type, int? amount})> _foldsThenHeroOpen(
        {required ActionType heroAct, int? heroAmount}) =>
    [
      (seat: 4, type: ActionType.fold, amount: null), // UTG
      (seat: 5, type: ActionType.fold, amount: null), // UTG1
      (seat: 6, type: ActionType.fold, amount: null), // MP
      (seat: 7, type: ActionType.fold, amount: null), // HJ
      (seat: 8, type: heroAct, amount: heroAmount), // CO = hero
    ];

void main() {
  group('exportPopulation', () {
    test('no-straddle: hero opens after folds → placed on the right node', () {
      final hand = makeHand(
        stacks: _hundredBb,
        buttonSeat: 1,
        sb: 200,
        bb: 500,
        heroSeat: 8,
        forced: const [ForcedBet(2, PostType.sb, 200), ForcedBet(3, PostType.bb, 500)],
        positions: _noStrPos,
        heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
        actions: _foldsThenHeroOpen(heroAct: ActionType.raise, heroAmount: 1500),
      );

      final b = exportPopulation([hand], capturedThrough: '2026-06-10');
      expect(b.acceptedHands, 1);
      expect(b.manifest['node_count'], 1);

      final node = (b.manifest['nodes'] as List).first as Map<String, dynamic>;
      expect(node['node_id'], 'nostr__UTG.F_UTG1.F_MP.F_HJ.F');
      expect(node['regime'], 'nostr');
      expect(node['hero_pos'], 'CO');
      expect(node['depth_band'], 'faithful');
      expect(node['n_hands'], 1);
      expect(node['straddle_ratio'], isNull);

      // Hero's open lands in pot.csv as the canonical physical hand.
      expect(b.files['nodes/nostr__UTG.F_UTG1.F_MP.F_HJ.F/pot.csv'],
          'HAND,FREQ,EV\nAhAsKhQd,1.0,0\n');
      expect(b.files['nodes/nostr__UTG.F_UTG1.F_MP.F_HJ.F/fold.csv'],
          'HAND,FREQ,EV\n');
    });

    test('limp anywhere before the hero is refused (no-limp trees)', () {
      final hand = makeHand(
        stacks: _hundredBb,
        buttonSeat: 1,
        sb: 200,
        bb: 500,
        heroSeat: 8,
        forced: const [ForcedBet(2, PostType.sb, 200), ForcedBet(3, PostType.bb, 500)],
        positions: _noStrPos,
        heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
        actions: [
          (seat: 4, type: ActionType.call, amount: 500), // UTG limps
          (seat: 5, type: ActionType.fold, amount: null),
          (seat: 6, type: ActionType.fold, amount: null),
          (seat: 7, type: ActionType.fold, amount: null),
          (seat: 8, type: ActionType.raise, amount: 2000), // hero isolates
        ],
      );

      final b = exportPopulation([hand], capturedThrough: '2026-06-10');
      expect(b.acceptedHands, 0);
      expect(b.refusals[RefusalReason.limp], 1);
    });

    test('off-band stack depth is refused', () {
      final shallow = {for (var s = 1; s <= 8; s++) s: 20000}; // 40bb
      final hand = makeHand(
        stacks: shallow,
        buttonSeat: 1,
        sb: 200,
        bb: 500,
        heroSeat: 8,
        forced: const [ForcedBet(2, PostType.sb, 200), ForcedBet(3, PostType.bb, 500)],
        positions: _noStrPos,
        heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
        actions: _foldsThenHeroOpen(heroAct: ActionType.raise, heroAmount: 1500),
      );

      final b = exportPopulation([hand], capturedThrough: '2026-06-10');
      expect(b.acceptedHands, 0);
      expect(b.refusals[RefusalReason.offBandStack], 1);
    });

    test('button straddle: regime + 2x straddle correction → 100bb faithful', () {
      // Button on seat 4 (straddler); SB acts first, hero CO = seat 3.
      const pos = {
        4: 'BTN',
        5: 'SB',
        6: 'BB',
        7: 'UTG',
        8: 'UTG1',
        1: 'MP',
        2: 'HJ',
        3: 'CO',
      };
      final hand = makeHand(
        stacks: _hundredBb,
        buttonSeat: 4,
        sb: 200,
        bb: 500,
        heroSeat: 3,
        forced: const [
          ForcedBet(5, PostType.sb, 200),
          ForcedBet(6, PostType.bb, 500),
          ForcedBet(4, PostType.straddleButton, 1000),
        ],
        positions: pos,
        heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
        actions: [
          (seat: 5, type: ActionType.fold, amount: null), // SB
          (seat: 6, type: ActionType.fold, amount: null), // BB
          (seat: 7, type: ActionType.fold, amount: null), // UTG
          (seat: 8, type: ActionType.fold, amount: null), // UTG1
          (seat: 1, type: ActionType.fold, amount: null), // MP
          (seat: 2, type: ActionType.fold, amount: null), // HJ
          (seat: 3, type: ActionType.raise, amount: 3000), // CO = hero opens
        ],
      );

      final b = exportPopulation([hand], capturedThrough: '2026-06-10');
      expect(b.acceptedHands, 1);
      final node = (b.manifest['nodes'] as List).first as Map<String, dynamic>;
      expect(node['regime'], 'bstr');
      expect(node['hero_pos'], 'CO');
      expect(node['depth_band'], 'faithful');
      expect(node['straddle_ratio'], 2.0);
      expect(node['node_id'],
          'bstr__SB.F_BB.F_UTG.F_UTG1.F_MP.F_HJ.F');
    });

    test('mixed strategy on one hand class aggregates to split frequencies', () {
      List<Map<String, dynamic>> sameLine(ActionType heroAct, int? amt) => [
            makeHand(
              stacks: _hundredBb,
              buttonSeat: 1,
              sb: 200,
              bb: 500,
              heroSeat: 8,
              forced: const [
                ForcedBet(2, PostType.sb, 200),
                ForcedBet(3, PostType.bb, 500)
              ],
              positions: _noStrPos,
              heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
              actions: _foldsThenHeroOpen(heroAct: heroAct, heroAmount: amt),
            )
          ];

      // Same node + same physical hand: once opened, once folded → 50/50.
      final hands = [
        ...sameLine(ActionType.raise, 1500),
        ...sameLine(ActionType.fold, null),
      ];
      final b = exportPopulation(hands, capturedThrough: '2026-06-10');
      expect(b.acceptedHands, 2);
      expect(b.manifest['node_count'], 1);

      const dir = 'nodes/nostr__UTG.F_UTG1.F_MP.F_HJ.F';
      expect(b.files['$dir/pot.csv'], 'HAND,FREQ,EV\nAhAsKhQd,0.5,0\n');
      expect(b.files['$dir/fold.csv'], 'HAND,FREQ,EV\nAhAsKhQd,0.5,0\n');

      final node = (b.manifest['nodes'] as List).first as Map<String, dynamic>;
      expect(node['n_hands'], 2);
    });

    test('a hand that never reaches the hero is dropped', () {
      // Folds around to the BTN who opens; HERO (CO) already folded earlier is
      // not possible here, so instead end the hand before CO acts.
      final hand = makeHand(
        stacks: _hundredBb,
        buttonSeat: 1,
        sb: 200,
        bb: 500,
        heroSeat: 8,
        forced: const [ForcedBet(2, PostType.sb, 200), ForcedBet(3, PostType.bb, 500)],
        positions: _noStrPos,
        heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
        actions: const [
          (seat: 4, type: ActionType.fold, amount: null),
          (seat: 5, type: ActionType.fold, amount: null),
          (seat: 6, type: ActionType.fold, amount: null),
          // stops before HJ + hero — hero never acts
        ],
      );

      final b = exportPopulation([hand], capturedThrough: '2026-06-10');
      expect(b.acceptedHands, 0);
      expect(b.refusals[RefusalReason.noHeroAction], 1);
    });
  });
}
