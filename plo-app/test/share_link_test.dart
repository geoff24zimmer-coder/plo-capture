import 'package:test/test.dart';
import 'package:plo_capture/share_link.dart';

/// A representative slice of the canonical hand schema — enough nesting and
/// repetition to exercise the gzip round-trip.
Map<String, dynamic> sampleHand() => {
      'schema_version': '1.0',
      'hand_id': 'hand-1700000000000',
      'captured_at': '2026-06-11T18:30:00.000Z',
      'session': {
        'session_id': 'session-1',
        'game_type': 'mtt',
        'stakes': {'sb': 100, 'bb': 200},
      },
      'table': {'button_seat': 1, 'straddle_action_rule': 'utg_first_straddler_last'},
      'players': [
        for (var s = 1; s <= 8; s++)
          {
            'seat': s,
            'stack': {'amount': 20000, 'approximate': false},
            'position': 'P$s',
          }
      ],
      'hero': {'seat': 4, 'cards': ['Ah', 'Kh', 'Qs', 'Js']},
      'forced_bets': [
        {'seat': 2, 'post_type': 'sb', 'amount': 100, 'is_live': true},
        {'seat': 3, 'post_type': 'bb', 'amount': 200, 'is_live': true},
        {'seat': 3, 'post_type': 'ante', 'amount': 200, 'is_live': false},
      ],
      'actions': [
        {'seat': 4, 'action': 'raise', 'amount': 700},
        {'seat': 5, 'action': 'fold', 'amount': null},
        {'seat': 3, 'action': 'call', 'amount': 700},
      ],
      'board': {'flop': ['2c', '7d', 'Th'], 'turn': 'Ks', 'river': '3c'},
      'showdown': [
        {'seat': 3, 'reveal': 'full', 'cards': ['As', 'Ad', 'Kc', 'Qd']},
      ],
      'results': {
        'hero_net': 1400,
        'pots': [
          {'amount': 1700, 'winners': [{'seat': 4, 'amount': 1700}]}
        ],
      },
    };

void main() {
  group('share link encode/decode', () {
    test('round-trips an arbitrary hand exactly', () {
      final hand = sampleHand();
      final restored = decodeHand(encodeHand(hand));
      expect(restored, equals(hand));
    });

    test('token is URL-safe and unpadded', () {
      final token = encodeHand(sampleHand());
      expect(token, isNot(contains('=')));
      expect(token, isNot(contains('+')));
      expect(token, isNot(contains('/')));
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('compresses well below the raw JSON size', () {
      final token = encodeHand(sampleHand());
      // The sample JSON is ~1KB; gzip+base64 should leave us a sane URL.
      expect(token.length, lessThan(1200));
    });
  });

  group('parseShareLink', () {
    test('decodes a hand from a /r?h= fragment', () {
      // parseShareLink reads Uri.base, so drive decode directly here and assert
      // the wire shape the URL carries.
      final token = encodeHand(sampleHand());
      final frag = '$shareRoute?h=$token';
      final q = frag.indexOf('?');
      expect(frag.substring(0, q), shareRoute);
      final parsed = Uri.splitQueryString(frag.substring(q + 1));
      expect(parsed['h'], token);
      expect(decodeHand(parsed['h']!)['hand_id'], 'hand-1700000000000');
    });

    test('a corrupted token throws (callers fall back to broken-link)', () {
      expect(() => decodeHand('not-a-real-token!!!'), throwsA(anything));
    });
  });
}
