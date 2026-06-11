import 'dart:convert';
import 'package:test/test.dart';
import 'package:plo_capture/plo_engine.dart';
import 'package:plo_capture/hand_recorder.dart';
import 'package:plo_capture/util.dart' show positionNames;
import 'package:plo_capture/export/review_export.dart';

Map<String, dynamic> hand({required bool complete, required bool straddle}) {
  final stacks = {for (var s = 1; s <= 8; s++) s: 50000};
  final forced = straddle
      ? const [
          ForcedBet(5, PostType.sb, 200),
          ForcedBet(6, PostType.bb, 500),
          ForcedBet(4, PostType.straddleButton, 1000),
        ]
      : const [ForcedBet(2, PostType.sb, 200), ForcedBet(3, PostType.bb, 500)];
  final buttonSeat = straddle ? 4 : 1;
  final heroSeat = straddle ? 3 : 8; // CO in both layouts
  final cfg = HandConfig(
    initialStacks: stacks,
    buttonSeat: buttonSeat,
    smallBlind: 200,
    bigBlind: 500,
    forcedBets: forced,
    straddleRule: StraddleActionRule.sbFirst,
    heroSeat: heroSeat,
  );
  final seats = stacks.keys.toList()..sort();
  return buildHandJson(
    engine: cfg.buildEngine(),
    cfg: cfg,
    positions: positionNames(seats, buttonSeat),
    heroCards: const ['Ah', 'As', 'Kh', 'Qd'],
    flop: const [],
    complete: complete,
  );
}

void main() {
  test('decision-spot filename + lossless contents', () {
    final j = hand(complete: false, straddle: true);
    final rec = buildReviewExport(j);
    expect(rec.filename, endsWith('.plohand.json'));
    expect(rec.filename, contains('_CO_'));
    expect(rec.filename, contains('_bstr_'));
    expect(rec.filename, contains('_spot_'));
    expect(jsonDecode(rec.contents), equals(j)); // byte-for-byte round-trip
  });

  test('completed no-straddle hand → hand kind, nostr regime', () {
    final j = hand(complete: true, straddle: false);
    final rec = buildReviewExport(j);
    expect(rec.filename, contains('_CO_'));
    expect(rec.filename, contains('_nostr_'));
    expect(rec.filename, contains('_hand_'));
  });
}
