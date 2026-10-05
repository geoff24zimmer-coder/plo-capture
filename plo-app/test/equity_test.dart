import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/equity/equity.dart';
import 'package:plo_capture/equity/evaluator.dart';

List<int> c(String s) => parseCards(s);

/// Independent Omaha reference: enumerate every 2-from-hand × 3-from-board
/// five-card set explicitly and score it with [score5].
int bruteBest(List<int> hole, List<int> board) {
  var best = 0;
  for (var i = 0; i < hole.length; i++) {
    for (var j = i + 1; j < hole.length; j++) {
      for (var a = 0; a < 5; a++) {
        for (var b = a + 1; b < 5; b++) {
          for (var d = b + 1; d < 5; d++) {
            best = math.max(
                best, score5([hole[i], hole[j], board[a], board[b], board[d]]));
          }
        }
      }
    }
  }
  return best;
}

void main() {
  group('5-card ranking', () {
    test('every 5-card hand: textbook category counts and 7,462 ranks', () {
      final counts = List<int>.filled(9, 0);
      final distinct = <int>{};
      final h = List<int>.filled(5, 0);
      for (var a = 0; a < 52; a++) {
        h[0] = a;
        for (var b = a + 1; b < 52; b++) {
          h[1] = b;
          for (var d = b + 1; d < 52; d++) {
            h[2] = d;
            for (var e = d + 1; e < 52; e++) {
              h[3] = e;
              for (var f = e + 1; f < 52; f++) {
                h[4] = f;
                final s = score5(h);
                counts[s >> 20]++;
                distinct.add(s);
              }
            }
          }
        }
      }
      expect(counts, [
        1302540, // high card
        1098240, // pair
        123552, // two pair
        54912, // trips
        10200, // straight
        5108, // flush
        3744, // full house
        624, // quads
        40, // straight flush (incl. royal)
      ]);
      expect(distinct.length, 7462);
    });

    test('ordering spot checks', () {
      int s(String x) => score5(c(x));
      expect(s('5s4h3d2cAs') < s('6s5h4d3c2s'), isTrue); // wheel lowest
      expect(categoryOf(s('5s4h3d2cAs')), HandCategory.straight);
      expect(s('AsKhQdJcTs') > s('KsQhJdTc9s'), isTrue);
      expect(categoryOf(s('5h4h3h2hAh')), HandCategory.straightFlush);
      expect(s('KsKhKdQcQs') > s('QsQhQdAcAs'), isTrue); // trips decide FH
      expect(s('AsAhKdKc2s') > s('AsAhKdKcQs') == false, isTrue); // kicker
      expect(s('AsAhKdKcQs') > s('AsAhKdKc2s'), isTrue);
      expect(s('7s7h7d7c2s') == s('7s7h7d7c2d'), isTrue); // suits never matter
    });
  });

  group('Omaha evaluation', () {
    final ev = OmahaEvaluator.instance;

    test('lookup table agrees with the reference on random deals (PLO4+5)',
        () {
      final rng = math.Random(1);
      for (final size in [4, 5]) {
        for (var t = 0; t < 4000; t++) {
          final deck = [for (var i = 0; i < 52; i++) i]..shuffle(rng);
          final hole = deck.sublist(0, size), board = deck.sublist(10, 15);
          expect(ev.best(hole, board), bruteBest(hole, board),
              reason: '${hole.map(cardName)} on ${board.map(cardName)}');
        }
      }
    });

    test('exactly two from hand: one suited card makes no flush', () {
      // Four hearts on board; a single heart in hand is not a flush in Omaha.
      final v = ev.best(c('Ah9s8d2c'), c('KhQhJh3h4s'));
      expect(categoryOf(v), isNot(HandCategory.flush));
      expect(categoryOf(ev.best(c('Ah2h8d9c'), c('KhQhJh3h4s'))),
          HandCategory.flush);
    });

    test('exactly three from board: a board straight doesn\'t play', () {
      final v = ev.best(c('2c2d7h8s'), c('AsKhQdJcTs'));
      expect(categoryOf(v), HandCategory.pair); // just the deuces
    });

    test('quads on the board don\'t play — only three board cards count', () {
      // 9-9-9-9 on board + AA in hand is a full house (999 + AA), not quads.
      expect(categoryOf(ev.best(c('AsAh2d3c'), c('9s9h9d9cKs'))),
          HandCategory.fullHouse);
      // One 9 in hand with three on board IS quads (two from hand: 9 + kicker).
      expect(categoryOf(ev.best(c('9sAh2d3c'), c('9h9d9cKs5h'))),
          HandCategory.quads);
    });

    test('PLO5 also uses exactly two', () {
      final v = ev.best(c('Ah9s8d2c3s'), c('KhQhJh3h4s'));
      expect(categoryOf(v), isNot(HandCategory.flush));
    });
  });

  group('equity', () {
    test('turn: outs you can count by hand (10 of 40)', () {
      // Hero has the A-high flush; villain's set of sevens fills up on any
      // A, K or 2 (9 cards) or quads on the 7c — 10 outs from 40 unseen.
      final r = EquityCalc(
        hands: [c('QhJh3s4d'), c('7s7d9c8c')],
        board: c('AhKh7h2c'),
        holeSize: 4,
      ).runAll();
      expect(r.exact, isTrue);
      expect(r.trials, 40);
      expect(r.equity[0], closeTo(30 / 40, 1e-12));
      expect(r.equity[1], closeTo(10 / 40, 1e-12));
    });

    test('flop, 3-way: enumeration matches an independent brute force', () {
      final hands = [c('AsKs9d8d'), c('QhQcJh7c'), c('Td9h6s5s')];
      final board = c('Kd9c7h');
      final r = EquityCalc(hands: hands, board: board, holeSize: 4).runAll();
      expect(r.exact, isTrue);

      final used = {...hands.expand((h) => h), ...board};
      final rest = [for (var i = 0; i < 52; i++) if (!used.contains(i)) i];
      final share = List<double>.filled(3, 0);
      var n = 0;
      for (var i = 0; i < rest.length; i++) {
        for (var j = i + 1; j < rest.length; j++) {
          final b = [...board, rest[i], rest[j]];
          final s = [for (final h in hands) bruteBest(h, b)];
          final top = s.reduce(math.max);
          final k = s.where((v) => v == top).length;
          for (var p = 0; p < 3; p++) {
            if (s[p] == top) share[p] += 1 / k;
          }
          n++;
        }
      }
      expect(r.trials, n);
      for (var p = 0; p < 3; p++) {
        expect(r.equity[p], closeTo(share[p] / n, 1e-12));
      }
      expect(r.equity.reduce((a, b) => a + b), closeTo(1, 1e-9));
    });

    test('preflop: suit-mirrored hands are exactly 50/50', () {
      // Swapping s↔h and d↔c maps one hand onto the other and is a bijection
      // on runouts, so exact enumeration must split precisely.
      final r = EquityCalc(
        hands: [c('AsKsQdJd'), c('AhKhQcJc')],
        holeSize: 4,
        exactLimit: 2000000,
      ).runAll();
      expect(r.exact, isTrue);
      expect(r.trials, 1086008); // C(44, 5)
      expect(r.equity[0], closeTo(0.5, 1e-12));
    });

    test('preflop exact matches published third-party figures', () {
      // pokerpro.tools PLO calculator (checked 2026-10-05): AAKK ds vs KKQQ ds
      // is 69.1% by exhaustive enumeration of all 1,086,008 boards; A♠A♥7♦2♣
      // vs T♥9♥8♠7♠ is 50.4%.
      double eq(String a, String b) => EquityCalc(
              hands: [c(a), c(b)], holeSize: 4, exactLimit: 2000000)
          .runAll()
          .equity[0];
      expect(eq('AsAhKsKh', 'KdKcQdQc'), closeTo(0.691, 0.0005));
      expect(eq('AsAh7d2c', 'Th9h8s7s'), closeTo(0.504, 0.0005));
    });

    test('preflop Monte Carlo lands within 4 SE of exact', () {
      final hands = [c('AsAhKsKh'), c('JdTd9c8c')];
      final exact =
          EquityCalc(hands: hands, holeSize: 4, exactLimit: 2000000).runAll();
      final mc = EquityCalc(
        hands: hands,
        holeSize: 4,
        rng: math.Random(42),
      ).runAll(samples: 200000);
      expect(mc.exact, isFalse);
      expect(mc.stdError[0], lessThan(0.0015));
      expect((mc.equity[0] - exact.equity[0]).abs(),
          lessThan(4 * mc.stdError[0]));
      // Sanity: the famous "AAKK ds is only a modest favourite vs a rundown".
      expect(exact.equity[0], inInclusiveRange(0.55, 0.70));
    });

    test('unknown hands are dealt at random: random vs random ≈ 50%', () {
      final r = EquityCalc(
        hands: [<int>[], <int>[]],
        holeSize: 5,
        rng: math.Random(7),
      ).runAll(samples: 40000);
      expect((r.equity[0] - 0.5).abs(), lessThan(4 * r.stdError[0]));
    });

    test('partial hands + dead cards respected', () {
      // Hero holds both remaining aces' worth of blockers: villain can never
      // be dealt an ace when all four are visible.
      final r = EquityCalc(
        hands: [c('AsAh'), <int>[]],
        board: c('AdAc2s'),
        dead: c('KsKh'),
        holeSize: 4,
        rng: math.Random(3),
      ).runAll(samples: 5000);
      expect(r.equity[0], greaterThan(0.95)); // quad aces nearly always win
    });

    test('rejects bad input with readable messages', () {
      expect(
          () => EquityCalc(hands: [c('AsKsQsJs'), c('AsQhJh2c')], holeSize: 4),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('As is used twice'))));
      expect(
          () => EquityCalc(
              hands: [c('AsKsQsJs'), c('AhQhJh2c')],
              board: c('2d3d'),
              holeSize: 4),
          throwsArgumentError);
      expect(() => EquityCalc(hands: [c('AsKsQsJs')], holeSize: 4),
          throwsArgumentError);
      expect(
          () => EquityCalc(hands: [<int>[], <int>[]], holeSize: 6),
          throwsArgumentError);
    });

    test('incremental runs add up to the same answer', () {
      final calc = EquityCalc(
          hands: [c('AsKs9d8d'), c('QhQcJh7c')], board: c('Kd9c7h'), holeSize: 4);
      while (!calc.finished) {
        calc.run(37);
      }
      final once = EquityCalc(
              hands: [c('AsKs9d8d'), c('QhQcJh7c')],
              board: c('Kd9c7h'),
              holeSize: 4)
          .runAll();
      expect(calc.result.equity, once.equity);
      expect(calc.result.trials, once.trials);
    });
  });
}
