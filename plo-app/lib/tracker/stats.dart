/// Session-tracker math: win rate, variance, breakdowns, and the calendar
/// ledger. Pure Dart, no Flutter — fed a list of [Session]s, returns numbers.
///
/// Only sessions with a recorded result ([Session.hasResult]) count. Money is
/// cents throughout (doubles only for rates). Cash and MTT are kept apart —
/// an hourly rate means nothing for tournaments, ROI nothing for cash — and
/// only combined in the calendar ledger, which is about money in and out.
library;

import 'dart:math' as math;

import '../models/session.dart';

/// One slice of a breakdown (a stake, a venue, a weekday…).
class Bucket {
  final String label;
  int sessions = 0;
  double hours = 0;
  int net = 0;
  Bucket(this.label);

  /// Cents per hour, or null with no time logged.
  double? get hourly => hours > 0 ? net / hours : null;
}

class CashStats {
  final int sessions;
  final double hours;
  final int net;
  final int winningSessions;

  /// Cents per hour.
  final double? hourly;

  /// Big blinds per hour — each session normalised by its own big blind, so
  /// it compares across stakes.
  final double? bbPerHour;

  /// Standard deviation of the result per hour of play, cents (needs ≥2
  /// sessions with time logged).
  final double? sdPerHour;

  /// 95% confidence interval on [hourly], cents/hr.
  final ({double low, double high})? ci95;
  final Session? best, worst;
  final List<Bucket> byStakes, byVenue, byGame, byWeekday, byLength;

  /// Cumulative net and hours after each session, in end-time order — the
  /// graph, plotted against hours played so its slope is the hourly rate.
  final List<({DateTime at, double hours, int total})> runningTotal;

  const CashStats({
    required this.sessions,
    required this.hours,
    required this.net,
    required this.winningSessions,
    required this.hourly,
    required this.bbPerHour,
    required this.sdPerHour,
    required this.ci95,
    required this.best,
    required this.worst,
    required this.byStakes,
    required this.byVenue,
    required this.byGame,
    required this.byWeekday,
    required this.byLength,
    required this.runningTotal,
  });

  double? get winRatePct =>
      sessions == 0 ? null : 100.0 * winningSessions / sessions;

  /// Total hours of play needed before the 95% interval on the hourly rate
  /// narrows to ±[marginPerHour] cents — the honest "how much more sample".
  double? hoursForMargin(double marginPerHour) {
    final sd = sdPerHour;
    if (sd == null || marginPerHour <= 0) return null;
    final h = 1.96 * sd / marginPerHour;
    return h * h;
  }
}

class MttStats {
  final int entries;
  final double hours;
  final int buyIns;
  final int cashes;
  final int itm; // entries that returned anything
  final int? biggestCash;
  const MttStats({
    required this.entries,
    required this.hours,
    required this.buyIns,
    required this.cashes,
    required this.itm,
    required this.biggestCash,
  });

  int get net => cashes - buyIns;

  /// Return on investment, percent.
  double? get roiPct => buyIns > 0 ? 100.0 * net / buyIns : null;
  double? get itmPct => entries > 0 ? 100.0 * itm / entries : null;
}

const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const lengthLabels = ['< 2h', '2–4h', '4–6h', '6–8h', '8h+'];

String _lengthBucket(double h) => h < 2
    ? lengthLabels[0]
    : h < 4
        ? lengthLabels[1]
        : h < 6
            ? lengthLabels[2]
            : h < 8
                ? lengthLabels[3]
                : lengthLabels[4];

CashStats computeCashStats(Iterable<Session> all) {
  final ss = all.where((s) => !s.isMtt && s.hasResult).toList()
    ..sort((a, b) => a.endedAt!.compareTo(b.endedAt!));

  var hours = 0.0, net = 0, wins = 0;
  var bbSum = 0.0, bbHours = 0.0;
  Session? best, worst;
  final stakes = <String, Bucket>{}, venues = <String, Bucket>{};
  final games = <String, Bucket>{};
  final weekdays = {for (final l in weekdayLabels) l: Bucket(l)};
  final lengths = {for (final l in lengthLabels) l: Bucket(l)};
  final running = <({DateTime at, double hours, int total})>[];

  void add(Bucket b, Session s, double h) {
    b.sessions++;
    b.hours += h;
    b.net += s.net!;
  }

  for (final s in ss) {
    final h = s.hours(), r = s.net!;
    hours += h;
    net += r;
    if (r > 0) wins++;
    if (s.bigBlind > 0) {
      bbSum += r / s.bigBlind;
      bbHours += h;
    }
    if (best == null || r > best.net!) best = s;
    if (worst == null || r < worst.net!) worst = s;
    add(stakes.putIfAbsent(s.stakesLabel, () => Bucket(s.stakesLabel)), s, h);
    add(venues.putIfAbsent(s.venue, () => Bucket(s.venue)), s, h);
    add(games.putIfAbsent(s.gameLabel, () => Bucket(s.gameLabel)), s, h);
    add(weekdays[weekdayLabels[s.createdAt.weekday - 1]]!, s, h);
    add(lengths[_lengthBucket(h)]!, s, h);
    running.add((at: s.endedAt!, hours: hours, total: net));
  }

  final hourly = hours > 0 ? net / hours : null;

  // Per-hour standard deviation, each session weighted by its length:
  //   σ² = Σ hᵢ·(rᵢ/hᵢ − w)² / (n − 1)
  // (sessions with no time logged can't contribute a rate).
  double? sd;
  ({double low, double high})? ci;
  final timed = ss.where((s) => s.hours() > 0).toList();
  if (hourly != null && timed.length >= 2) {
    var acc = 0.0;
    for (final s in timed) {
      final h = s.hours();
      final dev = s.net! / h - hourly;
      acc += h * dev * dev;
    }
    sd = math.sqrt(acc / (timed.length - 1));
    final half = 1.96 * sd / math.sqrt(hours);
    ci = (low: hourly - half, high: hourly + half);
  }

  List<Bucket> byHours(Map<String, Bucket> m) =>
      m.values.toList()..sort((a, b) => b.hours.compareTo(a.hours));

  return CashStats(
    sessions: ss.length,
    hours: hours,
    net: net,
    winningSessions: wins,
    hourly: hourly,
    bbPerHour: bbHours > 0 ? bbSum / bbHours : null,
    sdPerHour: sd,
    ci95: ci,
    best: best,
    worst: worst,
    byStakes: byHours(stakes),
    byVenue: byHours(venues),
    byGame: byHours(games),
    byWeekday: weekdays.values.where((b) => b.sessions > 0).toList(),
    byLength: lengths.values.where((b) => b.sessions > 0).toList(),
    runningTotal: running,
  );
}

MttStats computeMttStats(Iterable<Session> all) {
  final ss = all.where((s) => s.isMtt && s.hasResult).toList();
  var hours = 0.0, buyIns = 0, cashes = 0, itm = 0;
  int? biggest;
  for (final s in ss) {
    hours += s.hours();
    buyIns += s.buyIn!;
    cashes += s.cashOut!;
    if (s.cashOut! > 0) {
      itm++;
      if (biggest == null || s.cashOut! > biggest) biggest = s.cashOut;
    }
  }
  return MttStats(
    entries: ss.length,
    hours: hours,
    buyIns: buyIns,
    cashes: cashes,
    itm: itm,
    biggestCash: biggest,
  );
}

// ---------------------------------------------------------------- ledger

/// One calendar day: what the paper ledger's HRS and +/- boxes hold.
class DayEntry {
  final DateTime day; // local midnight
  double hours = 0;
  int net = 0;
  int sessions = 0;
  DayEntry(this.day);
}

/// The month close-out box: days played, hours, best/worst day, net, and the
/// all-time running total through the end of the month.
class MonthLedger {
  final int daysPlayed;
  final double hours;
  final DayEntry? bestDay, worstDay;
  final int net;
  final int runningTotal;
  const MonthLedger({
    required this.daysPlayed,
    required this.hours,
    required this.bestDay,
    required this.worstDay,
    required this.net,
    required this.runningTotal,
  });
}

/// Calendar view of every resolved session, cash and MTT together. A session
/// belongs to the day it started (a 9pm–3am session is one day, not two).
class Ledger {
  /// Resolved days, keyed by local midnight.
  final Map<DateTime, DayEntry> days;

  /// Days holding an ended session with no result yet — shown as "needs a
  /// result", never folded into the numbers.
  final Set<DateTime> unresolvedDays;

  Ledger._(this.days, this.unresolvedDays);

  factory Ledger.from(Iterable<Session> all) {
    final days = <DateTime, DayEntry>{};
    final unresolved = <DateTime>{};
    for (final s in all) {
      if (s.isActive) continue;
      final d = dayOf(s.createdAt);
      if (!s.hasResult) {
        unresolved.add(d);
        continue;
      }
      final e = days.putIfAbsent(d, () => DayEntry(d));
      e.hours += s.hours();
      e.net += s.net!;
      e.sessions++;
    }
    return Ledger._(days, unresolved);
  }

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  MonthLedger month(int year, int month) {
    final first = DateTime(year, month);
    final next = DateTime(year, month + 1);
    var hours = 0.0, net = 0, running = 0, played = 0;
    DayEntry? best, worst;
    for (final e in days.values) {
      if (e.day.isBefore(next)) running += e.net;
      if (e.day.isBefore(first) || !e.day.isBefore(next)) continue;
      played++;
      hours += e.hours;
      net += e.net;
      if (best == null || e.net > best.net) best = e;
      if (worst == null || e.net < worst.net) worst = e;
    }
    return MonthLedger(
      daysPlayed: played,
      hours: hours,
      bestDay: best,
      worstDay: worst,
      net: net,
      runningTotal: running,
    );
  }
}
