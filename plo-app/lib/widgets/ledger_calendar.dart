import 'package:flutter/material.dart';

import '../models/session.dart';
import '../tracker/format.dart';
import '../tracker/stats.dart';

const _gold = Color(0xFFC9A536);
const _goldBright = Color(0xFFF0C75A);
const _green = Color(0xFF5DCAA5);
const _red = Color(0xFFE24B4A);
const _amber = Color(0xFFEF9F27);
const _ledgerGreen = Color(0xFF63B944);

Color _netColor(int net) => net >= 0 ? _green : _red;
TextStyle _muted(double size) =>
    TextStyle(fontSize: size, color: Colors.white.withValues(alpha: 0.5));

/// The digital twin of the paper ledger: a month grid where every played day
/// shows HRS and +/-, and the MONTH LEDGER close-out underneath.
class LedgerCalendar extends StatefulWidget {
  final List<Session> sessions;
  final Future<void> Function(Session) onOpen;
  const LedgerCalendar(
      {super.key, required this.sessions, required this.onOpen});

  @override
  State<LedgerCalendar> createState() => _LedgerCalendarState();
}

class _LedgerCalendarState extends State<LedgerCalendar> {
  late DateTime _month; // first of the shown month

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final ledger = Ledger.from(widget.sessions);
    final m = ledger.month(_month.year, _month.month);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Row(
          children: [
            IconButton(
                tooltip: 'Previous month',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: monthNames[_month.month - 1].toUpperCase()),
                  TextSpan(
                      text: ' ${_month.year}',
                      style: const TextStyle(color: _goldBright)),
                ]),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1),
              ),
            ),
            IconButton(
                tooltip: 'Next month',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right)),
          ],
        ),
        const SizedBox(height: 4),
        _grid(ledger),
        const SizedBox(height: 14),
        _MonthLedgerBox(m: m),
        if (ledger.unresolvedDays
            .any((d) => d.year == _month.year && d.month == _month.month))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              const Icon(Icons.circle, size: 8, color: _amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Marked days have a session with no result yet — tap to add '
                    'it. They aren’t counted until then.',
                    style: _muted(12)),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _grid(Ledger ledger) {
    // Weeks start on Sunday, like the paper calendar.
    final lead = _month.weekday % 7;
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((lead + daysIn) / 7).ceil() * 7;
    final today = Ledger.dayOf(DateTime.now());
    const heads = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    return Column(
      children: [
        Row(children: [
          for (final h in heads)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(h,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _gold)),
              ),
            ),
        ]),
        for (var w = 0; w < cells ~/ 7; w++)
          Row(children: [
            for (var d = 0; d < 7; d++)
              Expanded(
                  child: _cell(
                      DateTime(_month.year, _month.month, w * 7 + d - lead + 1),
                      ledger,
                      today)),
          ]),
      ],
    );
  }

  Widget _cell(DateTime day, Ledger ledger, DateTime today) {
    final inMonth = day.month == _month.month;
    final e = ledger.days[day];
    final open = ledger.unresolvedDays.contains(day);
    final has = e != null || open;
    return AspectRatio(
      aspectRatio: 0.82,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: inMonth
              ? Colors.white.withValues(alpha: e != null ? 0.07 : 0.03)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: has ? () => _openDay(day) : null,
            child: Opacity(
              // Spill-over days from the neighbouring months read as faded,
              // like the greyed dates on the paper calendar.
              opacity: inMonth ? 1 : 0.35,
              child: Container(
                decoration: day == today
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _goldBright, width: 1.2))
                    : null,
                padding: const EdgeInsets.fromLTRB(5, 4, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('${day.day}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white
                                  .withValues(alpha: inMonth ? 0.9 : 0.25))),
                      const Spacer(),
                      if (open)
                        const Icon(Icons.circle, size: 7, color: _amber),
                    ]),
                    const Spacer(),
                    if (e != null) ...[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child:
                            Text('${hoursShort(e.hours)}h', style: _muted(10)),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(usdCompact(e.net),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _netColor(e.net))),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDay(DateTime day) async {
    final list = widget.sessions
        .where((s) => !s.isActive && Ledger.dayOf(s.createdAt) == day)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final picked = await showModalBottomSheet<Session>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                  '${weekdayLabels[day.weekday - 1]}, ${shortDate(day)}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            for (final s in list)
              ListTile(
                title: Text('${s.stakesLabel} · ${s.venue}'),
                subtitle: Text('${clock(s.createdAt)} – ${clock(s.endedAt!)} · '
                    '${durationLabel(s.duration())}'),
                trailing: s.net == null
                    ? const Text('Add result',
                        style: TextStyle(
                            color: _amber, fontWeight: FontWeight.w700))
                    : Text(usd(s.net!, signed: true),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _netColor(s.net!))),
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await widget.onOpen(picked);
  }
}

class _MonthLedgerBox extends StatelessWidget {
  final MonthLedger m;
  const _MonthLedgerBox({required this.m});

  @override
  Widget build(BuildContext context) {
    String day(DayEntry? e) =>
        e == null ? '—' : '${usd(e.net, signed: true)} · ${shortDate(e.day)}';
    final rows = <(String, String, Color?)>[
      ('DAYS PLAYED', '${m.daysPlayed}', null),
      ('HOURS', m.daysPlayed == 0 ? '—' : hoursShort(m.hours), null),
      (
        'BEST DAY',
        day(m.bestDay),
        m.bestDay == null ? null : _netColor(m.bestDay!.net)
      ),
      (
        'WORST DAY',
        day(m.worstDay),
        m.worstDay == null ? null : _netColor(m.worstDay!.net)
      ),
      (
        'NET',
        m.daysPlayed == 0 ? '—' : usd(m.net, signed: true),
        m.daysPlayed == 0 ? null : _netColor(m.net)
      ),
      (
        'RUNNING TOTAL',
        usd(m.runningTotal, signed: true),
        _netColor(m.runningTotal)
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MONTH LEDGER',
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w800,
                  color: _ledgerGreen)),
          const SizedBox(height: 6),
          for (final (label, value, color) in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(children: [
                Text(label, style: _muted(11).copyWith(letterSpacing: 1.4)),
                const Spacer(),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color ?? Colors.white)),
              ]),
            ),
        ],
      ),
    );
  }
}
