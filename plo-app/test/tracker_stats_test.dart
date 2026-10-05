import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/models/session.dart';
import 'package:plo_capture/tracker/stats.dart';

var _n = 0;

/// A finished cash session: [start] + [hours], in for [buyIn] out [cashOut]
/// (dollars), at $sb/$bb.
Session cash(DateTime start, double hours, int buyIn, int? cashOut,
        {int sb = 2, int bb = 5, String venue = 'Lodge', String game = 'plo4'}) =>
    Session(
      id: 's${_n++}',
      createdAt: start,
      gameType: 'cash',
      smallBlind: sb * 100,
      bigBlind: bb * 100,
      venue: venue,
      maxSeats: 8,
      endedAt: start.add(Duration(minutes: (hours * 60).round())),
      game: game,
      buyIn: buyIn * 100,
      cashOut: cashOut == null ? null : cashOut * 100,
    );

void main() {
  group('cash stats', () {
    // Three sessions: +$500 over 5h, −$300 over 3h, +$200 over 2h at 5/10.
    final a = cash(DateTime(2026, 10, 2, 19), 5, 1000, 1500); // Fri
    final b = cash(DateTime(2026, 10, 3, 20), 3, 1000, 700); // Sat
    final c = cash(DateTime(2026, 10, 4, 18), 2, 2000, 2200, sb: 5, bb: 10);
    final st = computeCashStats([a, b, c]);

    test('totals, hourly and win rate', () {
      expect(st.sessions, 3);
      expect(st.hours, closeTo(10, 1e-9));
      expect(st.net, 40000); // $400
      expect(st.hourly, closeTo(4000, 1e-9)); // $40/hr
      expect(st.winningSessions, 2);
      expect(st.winRatePct, closeTo(66.667, 1e-3));
      expect(st.best, same(a));
      expect(st.worst, same(b));
    });

    test('bb/hr normalises each session by its own big blind', () {
      // 500/5 = 100bb, −300/5 = −60bb, 200/10 = 20bb → 60bb over 10h.
      expect(st.bbPerHour, closeTo(6.0, 1e-9));
    });

    test('per-hour SD is the time-weighted estimator, CI uses total hours', () {
      // rates $/hr: 100, −100, 100; w = 40.
      const w = 4000.0;
      final varSum = 5 * math.pow(10000 - w, 2) +
          3 * math.pow(-10000 - w, 2) +
          2 * math.pow(10000 - w, 2);
      final sd = math.sqrt(varSum / 2);
      expect(st.sdPerHour, closeTo(sd, 1e-6));
      final half = 1.96 * sd / math.sqrt(10);
      expect(st.ci95!.low, closeTo(w - half, 1e-6));
      expect(st.ci95!.high, closeTo(w + half, 1e-6));
      // Hours to tighten the interval to ±$10/hr.
      expect(st.hoursForMargin(1000),
          closeTo(math.pow(1.96 * sd / 1000, 2), 1e-6));
    });

    test('breakdowns', () {
      expect(st.byStakes.map((b) => b.label), ['\$2/\$5 PLO', '\$5/\$10 PLO']);
      expect(st.byStakes.first.net, 20000);
      expect(st.byStakes.first.hourly, closeTo(2500, 1e-9));
      expect({for (final b in st.byWeekday) b.label: b.net},
          {'Fri': 50000, 'Sat': -30000, 'Sun': 20000});
      expect({for (final b in st.byLength) b.label: b.sessions},
          {'2–4h': 2, '4–6h': 1});
    });

    test('running total follows end-time order', () {
      expect(st.runningTotal.map((p) => p.total), [50000, 20000, 40000]);
    });

    test('unresolved, active and MTT sessions are excluded', () {
      final unresolved = cash(DateTime(2026, 10, 5, 19), 4, 1000, null);
      final active = Session(
          id: 'act',
          createdAt: DateTime(2026, 10, 6, 19),
          gameType: 'cash',
          smallBlind: 200,
          bigBlind: 500,
          venue: 'Lodge',
          maxSeats: 8,
          buyIn: 100000);
      final mtt = Session(
          id: 'm',
          createdAt: DateTime(2026, 10, 1, 12),
          gameType: 'mtt',
          smallBlind: 0,
          bigBlind: 0,
          venue: 'WPT',
          maxSeats: 8,
          endedAt: DateTime(2026, 10, 1, 20),
          buyIn: 110000,
          cashOut: 0);
      final st2 = computeCashStats([a, b, c, unresolved, active, mtt]);
      expect(st2.sessions, 3);
      expect(st2.net, 40000);
    });

    test('empty and single-session cases have no rate spread', () {
      final e = computeCashStats(const []);
      expect(e.hourly, isNull);
      expect(e.sdPerHour, isNull);
      expect(e.winRatePct, isNull);
      final one = computeCashStats([a]);
      expect(one.hourly, closeTo(10000, 1e-9));
      expect(one.sdPerHour, isNull);
      expect(one.ci95, isNull);
    });
  });

  group('MTT stats', () {
    Session mtt(int buyIn, int cashOut) => Session(
        id: 'm${_n++}',
        createdAt: DateTime(2026, 9, 1, 12),
        gameType: 'mtt',
        smallBlind: 0,
        bigBlind: 0,
        venue: 'Series',
        maxSeats: 8,
        endedAt: DateTime(2026, 9, 1, 18),
        buyIn: buyIn * 100,
        cashOut: cashOut * 100);

    test('ROI, ITM and biggest cash', () {
      final st =
          computeMttStats([mtt(1100, 0), mtt(1100, 0), mtt(600, 4200)]);
      expect(st.entries, 3);
      expect(st.buyIns, 280000);
      expect(st.cashes, 420000);
      expect(st.net, 140000);
      expect(st.roiPct, closeTo(50, 1e-9));
      expect(st.itm, 1);
      expect(st.itmPct, closeTo(33.333, 1e-3));
      expect(st.biggestCash, 420000);
      expect(st.hours, closeTo(18, 1e-9));
    });
  });

  group('ledger', () {
    final s1 = cash(DateTime(2026, 9, 30, 20), 3, 1000, 1400); // Sep
    final s2 = cash(DateTime(2026, 10, 2, 21), 6, 1000, 400); // crosses midnight
    final s3 = cash(DateTime(2026, 10, 2, 12), 2, 500, 800); // same day
    final s4 = cash(DateTime(2026, 10, 9, 19), 4, 1000, 1900);
    final open = cash(DateTime(2026, 10, 12, 19), 4, 1000, null);
    final led = Ledger.from([s1, s2, s3, s4, open]);

    test('a session belongs to the day it started', () {
      final d = led.days[DateTime(2026, 10, 2)]!;
      expect(d.sessions, 2);
      expect(d.hours, closeTo(8, 1e-9));
      expect(d.net, -30000); // −600 + 300
      expect(led.days.containsKey(DateTime(2026, 10, 3)), isFalse);
    });

    test('month close-out: days, hours, best/worst, net, running total', () {
      final m = led.month(2026, 10);
      expect(m.daysPlayed, 2);
      expect(m.hours, closeTo(12, 1e-9));
      expect(m.net, 60000); // −300 + 900
      expect(m.bestDay!.day, DateTime(2026, 10, 9));
      expect(m.worstDay!.day, DateTime(2026, 10, 2));
      expect(m.runningTotal, 100000); // +400 from September carried in
      expect(led.month(2026, 9).runningTotal, 40000);
      expect(led.month(2026, 11).daysPlayed, 0);
      expect(led.month(2026, 11).runningTotal, 100000);
    });

    test('ended sessions without a result are flagged, not counted', () {
      expect(led.unresolvedDays, {DateTime(2026, 10, 12)});
      expect(led.days.containsKey(DateTime(2026, 10, 12)), isFalse);
    });

    test('December rolls over to January', () {
      final dec = cash(DateTime(2026, 12, 31, 20), 2, 100, 300);
      final l = Ledger.from([dec]);
      expect(l.month(2026, 12).net, 20000);
      expect(l.month(2027, 1).net, 0);
      expect(l.month(2027, 1).runningTotal, 20000);
    });
  });
}
