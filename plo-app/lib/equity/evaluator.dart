/// Poker hand evaluation for Omaha: 5-card ranking + the "exactly two from
/// hand, exactly three from the board" rule. Pure Dart, no Flutter.
///
/// Cards are ints `rank * 4 + suit`, rank 0..12 = 2..A, suit 0..3 (s h d c).
/// A score is an int where higher beats lower and equal is a tie:
/// `category << 20 | kickers` (five 4-bit ranks, most significant first).
library;

import 'dart:typed_data';

const _rankChars = '23456789TJQKA';
const _suitChars = 'shdc';

int rankOf(int card) => card >> 2;
int suitOf(int card) => card & 3;

/// 'As' → int. Throws [FormatException] on anything else.
int parseCard(String s) {
  if (s.length != 2) throw FormatException('Bad card "$s"');
  final r = _rankChars.indexOf(s[0].toUpperCase());
  final u = _suitChars.indexOf(s[1].toLowerCase());
  if (r < 0 || u < 0) throw FormatException('Bad card "$s"');
  return r * 4 + u;
}

String cardName(int c) => '${_rankChars[rankOf(c)]}${_suitChars[suitOf(c)]}';

/// 'AsKhQdJc' → ints.
List<int> parseCards(String s) => [
      for (var i = 0; i + 1 < s.length; i += 2) parseCard(s.substring(i, i + 2))
    ];

enum HandCategory {
  highCard,
  pair,
  twoPair,
  trips,
  straight,
  flush,
  fullHouse,
  quads,
  straightFlush,
}

HandCategory categoryOf(int score) => HandCategory.values[score >> 20];

/// Score five ranks (0..12, any order, repeats allowed) as if unsuited. Exact,
/// allocation-light; used to build the lookup table and as a reference.
int scoreRanks(int a, int b, int c, int d, int e) {
  final cnt = List<int>.filled(13, 0);
  cnt[a]++;
  cnt[b]++;
  cnt[c]++;
  cnt[d]++;
  cnt[e]++;
  // Ranks ordered by (count desc, rank desc) — the kicker order.
  final order = <int>[];
  for (var k = 4; k >= 1; k--) {
    for (var r = 12; r >= 0; r--) {
      if (cnt[r] == k) order.add(r);
    }
  }
  final distinct = order.length;
  int pack(List<int> rs, int cat) {
    var v = cat;
    for (var i = 0; i < 5; i++) {
      v = (v << 4) | (i < rs.length ? rs[i] : 0);
    }
    return v;
  }

  if (distinct == 5) {
    final hi = order[0], lo = order[4];
    if (hi - lo == 4) return pack([hi], HandCategory.straight.index);
    // The wheel: A-5-4-3-2 is a five-high straight.
    if (hi == 12 && order[1] == 3) return pack([3], HandCategory.straight.index);
    return pack(order, HandCategory.highCard.index);
  }
  final top = cnt[order[0]];
  final HandCategory cat;
  if (top == 4) {
    cat = HandCategory.quads;
  } else if (top == 3) {
    cat = distinct == 2 ? HandCategory.fullHouse : HandCategory.trips;
  } else {
    cat = distinct == 3 ? HandCategory.twoPair : HandCategory.pair;
  }
  return pack(order, cat.index);
}

/// A flush has five distinct ranks, so its score is the unsuited score with
/// the category bumped: high card → flush, straight → straight flush.
int flushScore(int unsuited) {
  final cat = unsuited >> 20;
  final bumped = cat == HandCategory.straight.index
      ? HandCategory.straightFlush.index
      : HandCategory.flush.index;
  return (bumped << 20) | (unsuited & 0xFFFFF);
}

/// Score any 5 cards (reference path — the fast path is [OmahaEvaluator]).
int score5(List<int> cards) {
  final s = scoreRanks(rankOf(cards[0]), rankOf(cards[1]), rankOf(cards[2]),
      rankOf(cards[3]), rankOf(cards[4]));
  final u = suitOf(cards[0]);
  for (var i = 1; i < 5; i++) {
    if (suitOf(cards[i]) != u) return s;
  }
  return flushScore(s);
}

const _p4 = 13 * 13 * 13 * 13, _p3 = 13 * 13 * 13, _p2 = 13 * 13;

/// Table-driven Omaha evaluation. `table[i]` holds the unsuited score of five
/// ranks for every ordering, indexed `r0·13⁴ + r1·13³ + r2·13² + r3·13 + r4`,
/// so a hole pair and a board triple each contribute a precomputed partial
/// index and best-of-60 (PLO4) / best-of-100 (PLO5) is just additions and
/// lookups. Built once, lazily (~371k entries).
class OmahaEvaluator {
  OmahaEvaluator._();
  static final OmahaEvaluator instance = OmahaEvaluator._();

  late final Int32List table = _build();

  static Int32List _build() {
    final t = Int32List(13 * _p4);
    // Fill each rank multiset once, then every permutation of it.
    for (var a = 0; a < 13; a++) {
      for (var b = a; b < 13; b++) {
        for (var c = b; c < 13; c++) {
          for (var d = c; d < 13; d++) {
            for (var e = d; e < 13; e++) {
              if (a == e) continue; // five of a rank doesn't exist
              final v = scoreRanks(a, b, c, d, e);
              _permute([a, b, c, d, e], (p) {
                t[p[0] * _p4 + p[1] * _p3 + p[2] * _p2 + p[3] * 13 + p[4]] = v;
              });
            }
          }
        }
      }
    }
    return t;
  }

  static void _permute(List<int> xs, void Function(List<int>) f) {
    void go(int k) {
      if (k == xs.length) {
        f(xs);
        return;
      }
      for (var i = k; i < xs.length; i++) {
        var t = xs[k];
        xs[k] = xs[i];
        xs[i] = t;
        go(k + 1);
        t = xs[k];
        xs[k] = xs[i];
        xs[i] = t;
      }
    }

    go(0);
  }

  /// Best Omaha score for [hole] (4 or 5 cards) on a 5-card [board]: exactly
  /// two hole cards with exactly three board cards.
  int best(List<int> hole, List<int> board) {
    final triples = BoardTriples(board);
    return bestWith(HolePairs(hole), triples);
  }

  int bestWith(HolePairs h, BoardTriples b) {
    final t = table;
    var best = 0;
    for (var i = 0; i < h.count; i++) {
      final hp = h.part[i], hs = h.suit[i];
      for (var j = 0; j < 10; j++) {
        var v = t[hp + b.part[j]];
        if (hs >= 0 && hs == b.suit[j]) v = flushScore(v);
        if (v > best) best = v;
      }
    }
    return best;
  }
}

/// The 6 (PLO4) or 10 (PLO5) two-card subsets of a hole hand, as partial
/// table indexes plus their common suit (-1 when offsuit).
class HolePairs {
  final Int32List part = Int32List(10);
  final Int8List suit = Int8List(10);
  int count = 0;

  HolePairs([List<int>? hole]) {
    if (hole != null) set(hole);
  }

  void set(List<int> hole) {
    count = 0;
    for (var i = 0; i < hole.length; i++) {
      for (var j = i + 1; j < hole.length; j++) {
        final a = hole[i], b = hole[j];
        part[count] = rankOf(a) * _p4 + rankOf(b) * _p3;
        suit[count] = suitOf(a) == suitOf(b) ? suitOf(a) : -1;
        count++;
      }
    }
  }
}

/// The 10 three-card subsets of a 5-card board, as partial indexes + suit.
class BoardTriples {
  final Int32List part = Int32List(10);
  final Int8List suit = Int8List(10);

  BoardTriples([List<int>? board]) {
    if (board != null) set(board);
  }

  void set(List<int> board) {
    var k = 0;
    for (var i = 0; i < 5; i++) {
      for (var j = i + 1; j < 5; j++) {
        for (var l = j + 1; l < 5; l++) {
          final a = board[i], b = board[j], c = board[l];
          part[k] = rankOf(a) * _p2 + rankOf(b) * 13 + rankOf(c);
          final s = suitOf(a);
          suit[k] = (suitOf(b) == s && suitOf(c) == s) ? s : -1;
          k++;
        }
      }
    }
  }
}
