// Emits raw .plohand.json records — the UNAGGREGATED output the app stores —
// for the Monker Killer side to round-trip through solver/src/import.rs.
//
//   dart run tool/gen_sample_captures.dart [outDir]
//
// Faithfulness is the whole point (REQUEST_single_capture.md): positions come
// from the app's real positionNames(), the record is the real buildHandJson()
// map, and it's written with the same jsonEncode() hand_store uses — NOTHING is
// massaged to match the importer. Covers a no-straddle open, a button-straddle
// open, and a limp we expect to be refused.

import 'dart:convert';
import 'dart:io';

import 'package:plo_capture/hand_recorder.dart';
import 'package:plo_capture/plo_engine.dart';
import 'package:plo_capture/util.dart' show positionNames;

typedef Act = ({int seat, ActionType type, int? amount});

/// Build a real stored record: configure, replay, serialize exactly as the app
/// does on save (positions via positionNames, complete:false decision spot).
Map<String, dynamic> record({
  required Map<int, int> stacks,
  required int buttonSeat,
  required int sb,
  required int bb,
  required int heroSeat,
  required List<ForcedBet> forced,
  required List<String> heroCards,
  required List<Act> actions,
  required double captureSeconds,
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
  final seats = stacks.keys.toList()..sort();
  final positions = positionNames(seats, buttonSeat);
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
    sessionId: 'session-sample',
    captureSeconds: captureSeconds,
    complete: false, // saved at the hero's decision (a decision spot)
  );
}

Map<int, int> deep() => {for (var s = 1; s <= 8; s++) s: 50000}; // $500 @ $5
const noStrForced = [
  ForcedBet(2, PostType.sb, 200),
  ForcedBet(3, PostType.bb, 500),
];

void main(List<String> args) {
  final outDir = args.isNotEmpty ? args.first : 'sample_captures';
  final dir = Directory(outDir)..createSync(recursive: true);

  final records = <String, Map<String, dynamic>>{};

  // 1) No-straddle: folds to CO, hero (CO) opens. Button on seat 1 → CO = 8.
  records['01_nostraddle_co_open'] = record(
    stacks: deep(),
    buttonSeat: 1,
    sb: 200,
    bb: 500,
    heroSeat: 8,
    forced: noStrForced,
    heroCards: const ['Ad', 'Kd', 'Qc', 'Jc'],
    captureSeconds: 13.4,
    actions: const [
      (seat: 4, type: ActionType.fold, amount: null), // UTG
      (seat: 5, type: ActionType.fold, amount: null), // UTG1
      (seat: 6, type: ActionType.fold, amount: null), // MP
      (seat: 7, type: ActionType.fold, amount: null), // HJ
      (seat: 8, type: ActionType.raise, amount: 1500), // CO = hero opens to 3bb
    ],
  );

  // 2) Button straddle: folds around to hero (CO) open. Button/straddler = 4,
  //    SB acts first, hero CO = seat 3. straddle_action_rule the app writes now.
  records['02_buttonstraddle_co_open'] = record(
    stacks: deep(),
    buttonSeat: 4,
    sb: 200,
    bb: 500,
    heroSeat: 3,
    forced: const [
      ForcedBet(5, PostType.sb, 200),
      ForcedBet(6, PostType.bb, 500),
      ForcedBet(4, PostType.straddleButton, 1000),
    ],
    heroCards: const ['Ah', 'Ad', 'Kc', 'Qc'],
    captureSeconds: 16.1,
    actions: const [
      (seat: 5, type: ActionType.fold, amount: null), // SB
      (seat: 6, type: ActionType.fold, amount: null), // BB
      (seat: 7, type: ActionType.fold, amount: null), // UTG
      (seat: 8, type: ActionType.fold, amount: null), // UTG1
      (seat: 1, type: ActionType.fold, amount: null), // MP
      (seat: 2, type: ActionType.fold, amount: null), // HJ
      (seat: 3, type: ActionType.raise, amount: 3000), // CO = hero opens to 3x
    ],
  );

  // 3) Expected refusal: UTG limps, folds to hero (CO) who isolates. Our trees
  //    are no-limp, so the importer should dead-end with a limp reason.
  records['03_limp_then_hero_iso_REFUSE'] = record(
    stacks: deep(),
    buttonSeat: 1,
    sb: 200,
    bb: 500,
    heroSeat: 8,
    forced: noStrForced,
    heroCards: const ['As', 'Ks', 'Qh', 'Jd'],
    captureSeconds: 12.8,
    actions: const [
      (seat: 4, type: ActionType.call, amount: 500), // UTG limps
      (seat: 5, type: ActionType.fold, amount: null),
      (seat: 6, type: ActionType.fold, amount: null),
      (seat: 7, type: ActionType.fold, amount: null),
      (seat: 8, type: ActionType.raise, amount: 2000), // CO = hero isolates (pot-capped)
    ],
  );

  records.forEach((name, rec) {
    // Exactly the bytes hand_store persists: jsonEncode(handJson).
    File('${dir.path}/$name.plohand.json').writeAsStringSync(jsonEncode(rec));
    final t = rec['table'] as Map<String, dynamic>;
    final hero = (rec['players'] as List).firstWhere((p) => p['is_hero'] == true)
        as Map<String, dynamic>;
    stdout.writeln('$name  →  hero ${hero['position']}, '
        'button_seat ${t['button_seat']}, '
        'straddle_rule ${t['straddle_action_rule']}, '
        '${(rec['actions'] as List).length} actions');
  });
  stdout.writeln('Wrote ${records.length} records to $outDir');
}
