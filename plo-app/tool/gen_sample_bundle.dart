// Generates a sample population bundle for the Monker Killer (preflop_desktop)
// agent to round-trip through `monker_csv::load_monker_spot`. Run with:
//   dart run tool/gen_sample_bundle.dart [outDir]
// Writes <outDir>/sample_population_bundle.zip + an unzipped copy + a README.
//
// The hands are hand-crafted to span: a no-straddle open node with a MIXED
// strategy (so CSVs carry real fractional freqs), a 3-bet node, a button-
// straddle open node, and the two main refusal paths (limp, off-band stack).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:plo_capture/export/solver_export.dart';
import 'package:plo_capture/hand_recorder.dart';
import 'package:plo_capture/plo_engine.dart';

typedef Act = ({int seat, ActionType type, int? amount});

Map<String, dynamic> makeHand({
  required Map<int, int> stacks,
  required int buttonSeat,
  required int sb,
  required int bb,
  required int heroSeat,
  required List<ForcedBet> forced,
  required Map<int, String> positions,
  required List<String> heroCards,
  required List<Act> actions,
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

const noStrPos = {
  1: 'BTN', 2: 'SB', 3: 'BB', 4: 'UTG',
  5: 'UTG1', 6: 'MP', 7: 'HJ', 8: 'CO',
};
const bStrPos = {
  4: 'BTN', 5: 'SB', 6: 'BB', 7: 'UTG',
  8: 'UTG1', 1: 'MP', 2: 'HJ', 3: 'CO',
};
Map<int, int> deep() => {for (var s = 1; s <= 8; s++) s: 50000}; // $500 @ $5
const noStrForced = [ForcedBet(2, PostType.sb, 200), ForcedBet(3, PostType.bb, 500)];
const bStrForced = [
  ForcedBet(5, PostType.sb, 200),
  ForcedBet(6, PostType.bb, 500),
  ForcedBet(4, PostType.straddleButton, 1000),
];

List<Act> foldsTo(int last, {required Act hero}) {
  // Fold every earlier seat in no-straddle action order (UTG..) up to `last`.
  const order = [4, 5, 6, 7, 8, 1, 2, 3]; // UTG,UTG1,MP,HJ,CO,BTN,SB,BB
  final out = <Act>[];
  for (final s in order) {
    if (s == last) break;
    out.add((seat: s, type: ActionType.fold, amount: null));
  }
  out.add(hero);
  return out;
}

void main(List<String> args) {
  final outDir = args.isNotEmpty ? args.first : 'sample_bundle';
  final hands = <Map<String, dynamic>>[];

  // --- Node A: no-straddle, hero CO first to open. MIXED strategy: 3 distinct
  //     hands open (pot), 2 fold, 1 of the openers appears twice -> fractional.
  Map<String, dynamic> coOpen(List<String> cards, ActionType act, [int? amt]) =>
      makeHand(
        stacks: deep(), buttonSeat: 1, sb: 200, bb: 500, heroSeat: 8,
        forced: noStrForced, positions: noStrPos, heroCards: cards,
        actions: foldsTo(8, hero: (seat: 8, type: act, amount: amt)),
      );
  hands.addAll([
    coOpen(['Ah', 'As', 'Kh', 'Kd'], ActionType.raise, 1500),
    coOpen(['Ah', 'As', 'Kh', 'Kd'], ActionType.fold), // same class, 50/50
    coOpen(['Js', 'Ts', '9h', '8h'], ActionType.raise, 1500),
    coOpen(['Qd', 'Qs', 'Jd', 'Th'], ActionType.raise, 1500),
    coOpen(['7c', '2d', '8s', '3h'], ActionType.fold),
    coOpen(['6c', '2h', '9s', '4d'], ActionType.fold),
  ]);

  // --- Node B: no-straddle 3-bet node. Folds to CO who opens, hero on BTN.
  Map<String, dynamic> btn3bet(List<String> cards, ActionType act, [int? amt]) =>
      makeHand(
        stacks: deep(), buttonSeat: 1, sb: 200, bb: 500, heroSeat: 1,
        forced: noStrForced, positions: noStrPos, heroCards: cards,
        actions: [
          (seat: 4, type: ActionType.fold, amount: null),
          (seat: 5, type: ActionType.fold, amount: null),
          (seat: 6, type: ActionType.fold, amount: null),
          (seat: 7, type: ActionType.fold, amount: null),
          (seat: 8, type: ActionType.raise, amount: 1500), // CO opens
          (seat: 1, type: act, amount: amt), // BTN = hero decides
        ],
      );
  hands.addAll([
    btn3bet(['Ah', 'As', 'Ks', 'Kd'], ActionType.raise, 5000), // 3bet
    btn3bet(['Ad', 'Ac', 'Td', '9c'], ActionType.call, 1500), // flat
    btn3bet(['Kh', 'Qh', 'Jc', 'Tc'], ActionType.fold),
  ]);

  // --- Node C: button straddle, hero CO opens (SB-first order, button closes).
  Map<String, dynamic> bstrCoOpen(List<String> cards) => makeHand(
        stacks: deep(), buttonSeat: 4, sb: 200, bb: 500, heroSeat: 3,
        forced: bStrForced, positions: bStrPos, heroCards: cards,
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
  hands.addAll([
    bstrCoOpen(['Ah', 'As', 'Qh', 'Qd']),
    bstrCoOpen(['Kh', 'Ks', 'Jh', 'Td']),
  ]);

  // --- Refusals: a limped pot and an off-band (40bb) hand.
  hands.add(makeHand(
    stacks: deep(), buttonSeat: 1, sb: 200, bb: 500, heroSeat: 8,
    forced: noStrForced, positions: noStrPos, heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
    actions: const [
      (seat: 4, type: ActionType.call, amount: 500), // UTG limps -> refuse
      (seat: 5, type: ActionType.fold, amount: null),
      (seat: 6, type: ActionType.fold, amount: null),
      (seat: 7, type: ActionType.fold, amount: null),
      (seat: 8, type: ActionType.raise, amount: 2000),
    ],
  ));
  hands.add(makeHand(
    stacks: {for (var s = 1; s <= 8; s++) s: 20000}, // 40bb -> off-band
    buttonSeat: 1, sb: 200, bb: 500, heroSeat: 8,
    forced: noStrForced, positions: noStrPos, heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
    actions: foldsTo(8, hero: (seat: 8, type: ActionType.raise, amount: 1500)),
  ));

  final bundle = exportPopulation(hands, capturedThrough: '2026-06-10');

  // Write the unzipped tree + a zip + a README.
  final dir = Directory(outDir)..createSync(recursive: true);
  bundle.files.forEach((path, content) {
    final f = File('${dir.path}/$path')..createSync(recursive: true);
    f.writeAsStringSync(content);
  });
  File('${dir.path}/README.txt').writeAsStringSync(_readme(bundle));

  final archive = Archive();
  bundle.files.forEach((path, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  });
  final readme = utf8.encode(_readme(bundle));
  archive.addFile(ArchiveFile('README.txt', readme.length, readme));
  final zip = ZipEncoder().encode(archive);
  File('${dir.path}/../sample_population_bundle.zip').writeAsBytesSync(zip);

  stdout.writeln('Wrote ${bundle.files.length} files + zip to $outDir');
  stdout.writeln('Hands: ${bundle.totalHands}  accepted: ${bundle.acceptedHands}'
      '  nodes: ${bundle.manifest['node_count']}');
  stdout.writeln('Refusals: ${bundle.manifest['refusals']}');
}

String _readme(SolverBundle b) => '''
PLO Show — sample population bundle (for monker_csv::load_monker_spot round-trip)
================================================================================

Generated by HandHistory/plo-app/tool/gen_sample_bundle.dart against the spec in
HANDOFF_import.md (§4/§5a/§6/§7). This is the CSV-bridge path — NOT native .rng.

Layout:
  manifest.json            top-level: regime/line/N/depth band per node + refusals
  nodes/<node_id>/fold.csv
  nodes/<node_id>/call.csv
  nodes/<node_id>/pot.csv

CSV rows: HAND,FREQ,EV
  HAND = physical 8-char hand, <rank><suit> x4, ranks 2-9TJQKA, suits hcds
         (e.g. AhAsKhKd) — NOT the (KA)A2 canonical notation. You own the
         physical->canonical combo-weighted aggregation (§6).
  FREQ = observed population frequency of THIS file's action for that hand,
         in [0,1]; a mixed hand appears in multiple files summing to ~1.0.
  EV   = 0 (population read carries no EV).

node_id is a stable id WE control; the authoritative semantics (regime, ordered
action line, hero position, observed N, depth band) live in manifest.json — join
on that, not on the filename string.

This sample: ${b.totalHands} hands -> ${b.acceptedHands} accepted across
${b.manifest['node_count']} nodes; refusals = ${b.manifest['refusals']}.

What we need back: does load_monker_spot ingest these CSVs as-is? If the row
shape, header, hand string, or per-node file split is off, tell us the exact
delta and we'll conform. This is the one round-trip that converts our exporter
from "built to spec" to "verified against the consumer."
''';
