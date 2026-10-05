/// Omaha all-in equity: exact enumeration when the runouts are few (flop, turn,
/// fully-known river), Monte Carlo otherwise (preflop, unknown/random hands).
/// Pure Dart. Runs incrementally — call [EquityCalc.run] in slices so a UI can
/// stay responsive and show the estimate converging.
library;

import 'dart:math' as math;

import 'evaluator.dart';

class EquityResult {
  /// Share of the pot each player wins on average (ties split), 0..1.
  final List<double> equity;

  /// Fraction of runouts each player wins outright / ties for the best hand.
  final List<double> win, tie;

  /// Standard error of each [equity] (0 when exact).
  final List<double> stdError;
  final int trials;
  final bool exact;
  const EquityResult({
    required this.equity,
    required this.win,
    required this.tie,
    required this.stdError,
    required this.trials,
    required this.exact,
  });
}

class EquityCalc {
  final List<List<int>> hands;
  final List<int> board;
  final int holeSize;
  final math.Random _rng;

  late final List<int> _deck; // every card not known anywhere
  late final bool exact;
  late final int total; // exact: number of runouts; MC: 0 (unbounded)
  int done = 0;

  late final List<double> _share, _shareSq;
  late final List<int> _wins, _ties;
  late final List<HolePairs> _pairs;
  late final List<bool> _complete;
  final _triples = BoardTriples();
  late final List<int> _fullBoard;
  late final List<int> _combo; // exact-mode combination state (deck indexes)

  /// [hands]: each player's known cards (may be fewer than [holeSize], even
  /// none — the rest are dealt at random). [board]: 0, 3, 4 or 5 cards.
  /// Throws [ArgumentError] with a user-presentable message on bad input.
  EquityCalc({
    required this.hands,
    this.board = const [],
    List<int> dead = const [],
    required this.holeSize,
    math.Random? rng,
    int exactLimit = 60000,
  }) : _rng = rng ?? math.Random() {
    if (holeSize != 4 && holeSize != 5) {
      throw ArgumentError('Only 4- and 5-card Omaha are supported.');
    }
    if (hands.length < 2) throw ArgumentError('Need at least two players.');
    if (![0, 3, 4, 5].contains(board.length)) {
      throw ArgumentError('The board needs 0, 3, 4 or 5 cards.');
    }
    final seen = <int>{};
    for (final c in [...hands.expand((h) => h), ...board, ...dead]) {
      if (c < 0 || c > 51) throw ArgumentError('Bad card.');
      if (!seen.add(c)) {
        throw ArgumentError('${cardName(c)} is used twice.');
      }
    }
    for (final h in hands) {
      if (h.length > holeSize) {
        throw ArgumentError('A hand has more than $holeSize cards.');
      }
    }
    _deck = [for (var c = 0; c < 52; c++) if (!seen.contains(c)) c];
    final missing = hands.fold<int>(0, (a, h) => a + holeSize - h.length) +
        (5 - board.length);
    if (missing > _deck.length) throw ArgumentError('Not enough cards left.');

    final n = hands.length;
    _share = List.filled(n, 0.0);
    _shareSq = List.filled(n, 0.0);
    _wins = List.filled(n, 0);
    _ties = List.filled(n, 0);
    _complete = [for (final h in hands) h.length == holeSize];
    _pairs = [for (final h in hands) HolePairs(h.length == holeSize ? h : null)];
    _fullBoard = [...board, ...List.filled(5 - board.length, 0)];

    final k = 5 - board.length;
    final runouts = _choose(_deck.length, k);
    exact = _complete.every((c) => c) && runouts <= exactLimit;
    total = exact ? runouts : 0;
    _combo = [for (var i = 0; i < k; i++) i];
    OmahaEvaluator.instance.table; // build the lookup table up front
  }

  bool get finished => exact && done >= total;

  /// Advance by up to [n] runouts (exact) or random deals (Monte Carlo).
  void run(int n) {
    final ev = OmahaEvaluator.instance;
    final players = hands.length;
    final scores = List<int>.filled(players, 0);
    final k = 5 - board.length;
    final hand = List<int>.filled(holeSize, 0);
    for (var t = 0; t < n && !finished; t++) {
      if (exact) {
        for (var i = 0; i < k; i++) {
          _fullBoard[board.length + i] = _deck[_combo[i]];
        }
        _nextCombo(k);
      } else {
        // Partial Fisher–Yates: a uniform deal of every unknown card.
        var next = 0;
        int draw() {
          final j = next + _rng.nextInt(_deck.length - next);
          final c = _deck[j];
          _deck[j] = _deck[next];
          _deck[next] = c;
          next++;
          return c;
        }

        for (var p = 0; p < players; p++) {
          if (_complete[p]) continue;
          final known = hands[p];
          for (var i = 0; i < holeSize; i++) {
            hand[i] = i < known.length ? known[i] : draw();
          }
          _pairs[p].set(hand);
        }
        for (var i = board.length; i < 5; i++) {
          _fullBoard[i] = draw();
        }
      }
      _triples.set(_fullBoard);
      var best = -1, nBest = 0;
      for (var p = 0; p < players; p++) {
        final s = ev.bestWith(_pairs[p], _triples);
        scores[p] = s;
        if (s > best) {
          best = s;
          nBest = 1;
        } else if (s == best) {
          nBest++;
        }
      }
      final share = 1.0 / nBest;
      for (var p = 0; p < players; p++) {
        if (scores[p] != best) continue;
        _share[p] += share;
        _shareSq[p] += share * share;
        if (nBest == 1) {
          _wins[p]++;
        } else {
          _ties[p]++;
        }
      }
      done++;
    }
  }

  /// Run to completion (exact) or for [samples] deals (Monte Carlo).
  EquityResult runAll({int samples = 100000}) {
    run(exact ? total : samples);
    return result;
  }

  EquityResult get result {
    final n = math.max(done, 1);
    final eq = [for (final s in _share) s / n];
    return EquityResult(
      equity: eq,
      win: [for (final w in _wins) w / n],
      tie: [for (final t in _ties) t / n],
      stdError: [
        for (var p = 0; p < eq.length; p++)
          exact
              ? 0.0
              : math.sqrt(math.max(0, _shareSq[p] / n - eq[p] * eq[p]) / n)
      ],
      trials: done,
      exact: exact,
    );
  }

  void _nextCombo(int k) {
    final m = _deck.length;
    var i = k - 1;
    while (i >= 0 && _combo[i] == m - k + i) {
      i--;
    }
    if (i < 0) return; // exhausted — [finished] stops the loop
    _combo[i]++;
    for (var j = i + 1; j < k; j++) {
      _combo[j] = _combo[j - 1] + 1;
    }
  }

  static int _choose(int n, int k) {
    if (k < 0 || k > n) return 0;
    var r = 1;
    for (var i = 0; i < k; i++) {
      r = r * (n - i) ~/ (i + 1);
    }
    return r;
  }
}
