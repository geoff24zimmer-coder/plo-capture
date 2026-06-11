// Review export: hand it a stored record, get one raw .plohand.json back for
// Monker Killer's IMPORT HAND (import.rs) review flow. No snapping / aggregating
// / refusing happens here — the consumer owns all of that, and a decision spot
// (no hero action, meta.complete == false) is valid input. This is the route a
// decision spot takes; the population aggregator (which needs the hero's action)
// is the other route. See SOLUTION_decision_spot_routing.md.

import 'dart:convert';

/// One record ready to drop in sample_captures/ — a human-meaningful filename
/// plus the canonical JSON, byte-for-byte as the app stores it.
class ReviewRecord {
  final String filename; // e.g. 2026-06-10_CO_bstr_spot_a1b2c3.plohand.json
  final String contents;
  const ReviewRecord(this.filename, this.contents);
}

ReviewRecord buildReviewExport(Map<String, dynamic> handJson) =>
    ReviewRecord(_filename(handJson), jsonEncode(handJson));

String _filename(Map<String, dynamic> j) {
  final id = (j['hand_id'] as String?) ?? 'hand';
  final at = (j['captured_at'] as String?) ?? '';
  final date = at.length >= 10 ? at.substring(0, 10) : 'hand';

  var heroPos = 'hero';
  for (final p in (j['players'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    if (p['is_hero'] == true) {
      heroPos = (p['position'] as String?) ?? 'hero';
      break;
    }
  }

  var regime = 'nostr';
  for (final f in (j['forced_bets'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    final t = f['post_type'] as String?;
    if (t == 'straddle_button' || t == 'straddle_mississippi') {
      regime = 'bstr';
      break;
    }
    if (t == 'straddle_utg' || t == 'straddle_utg2') regime = 'ustr';
  }

  final complete = (j['meta'] as Map<String, dynamic>?)?['complete'];
  final kind = complete == false ? 'spot' : 'hand';
  final shortId = id.length > 6 ? id.substring(id.length - 6) : id;

  final raw = '${date}_${heroPos}_${regime}_${kind}_$shortId';
  return '${raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '')}.plohand.json';
}
