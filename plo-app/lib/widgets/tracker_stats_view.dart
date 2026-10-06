import 'package:flutter/material.dart';

import '../models/session.dart';
import '../tracker/format.dart';
import '../tracker/stats.dart';
import 'running_total_chart.dart';

const _green = Color(0xFF5DCAA5);
const _red = Color(0xFFE24B4A);
const _gold = Color(0xFFF0C75A);

Color _signColor(num v) => v >= 0 ? _green : _red;
String _thousands(int v) =>
    v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
final _mutedInk = Colors.white.withValues(alpha: 0.55);

enum _Period { all, year, d90, month }

const _periodLabels = {
  _Period.all: 'All time',
  _Period.year: 'This year',
  _Period.d90: 'Last 90 days',
  _Period.month: 'This month',
};

/// The tracker's Stats tab: cash win rate (with an honest read on how much the
/// sample can say) and tournament ROI — kept apart, never blended.
class TrackerStatsView extends StatefulWidget {
  final List<Session> sessions;
  const TrackerStatsView({super.key, required this.sessions});

  @override
  State<TrackerStatsView> createState() => _TrackerStatsViewState();
}

class _TrackerStatsViewState extends State<TrackerStatsView> {
  bool _mtt = false;
  _Period _period = _Period.all;

  DateTime? get _from {
    final now = DateTime.now();
    return switch (_period) {
      _Period.all => null,
      _Period.year => DateTime(now.year),
      _Period.d90 => now.subtract(const Duration(days: 90)),
      _Period.month => DateTime(now.year, now.month),
    };
  }

  List<Session> get _filtered {
    final from = _from;
    return from == null
        ? widget.sessions
        : widget.sessions.where((s) => !s.createdAt.isBefore(from)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ss = _filtered;
    final unresolved = ss.where((s) => !s.isActive && !s.hasResult && s.isMtt == _mtt).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Cash')),
            ButtonSegment(value: true, label: Text('Tournaments')),
          ],
          selected: {_mtt},
          onSelectionChanged: (v) => setState(() => _mtt = v.first),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final p in _Period.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(_periodLabels[p]!),
                  selected: _period == p,
                  onSelected: (_) => setState(() => _period = p),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        ...(_mtt ? _mttBody(computeMttStats(ss)) : _cashBody(computeCashStats(ss))),
        if (unresolved > 0)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              '$unresolved session${unresolved == 1 ? '' : 's'} in this period '
              'ha${unresolved == 1 ? 's' : 've'} no result yet and '
              '${unresolved == 1 ? 'isn’t' : 'aren’t'} counted — add '
              '${unresolved == 1 ? 'it' : 'them'} from Sessions.',
              style: TextStyle(fontSize: 12, color: _mutedInk),
            ),
          ),
      ],
    );
  }

  Widget _empty(String what) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          'No $what with results in this period yet.\nEnd a session with your '
          'cash-out, or log one you’ve played.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _mutedInk),
        ),
      );

  List<Widget> _cashBody(CashStats st) {
    if (st.sessions == 0) return [_empty('cash sessions')];
    const margin = 1000.0; // ±$10/hr
    final need = st.hoursForMargin(margin);
    return [
      _TileGrid(tiles: [
        _Tile('NET', usd(st.net, signed: true), _signColor(st.net)),
        _Tile('WIN RATE', usdRate(st.hourly), _signColor(st.hourly ?? 0)),
        _Tile('BB / HR',
            st.bbPerHour == null ? '—' : st.bbPerHour!.toStringAsFixed(1),
            _signColor(st.bbPerHour ?? 0)),
        _Tile('HOURS', hoursShort(st.hours)),
        _Tile('SESSIONS', '${st.sessions}'),
        _Tile('WINNING', '${st.winRatePct!.round()}%'),
      ]),
      if (st.untimedSessions > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '${st.untimedSessions} session${st.untimedSessions == 1 ? ' has' : 's have'} '
            'no playing time recorded, so ${st.untimedSessions == 1 ? 'it counts' : 'they count'} '
            'toward your net but not your hourly rate. Open '
            '${st.untimedSessions == 1 ? 'it' : 'them'} in Sessions and set the start '
            'and end times.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFEF9F27)),
          ),
        ),
      const SizedBox(height: 12),
      _Card(
        title: 'HOW SURE IS THAT?',
        child: st.ci95 == null
            ? Text('Log at least two timed sessions to see how much your win '
                'rate can be trusted.',
                style: TextStyle(color: _mutedInk))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Your true rate is likely between '),
                    TextSpan(
                        text: usdRate(st.ci95!.low),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const TextSpan(text: ' and '),
                    TextSpan(
                        text: usdRate(st.ci95!.high),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const TextSpan(text: ' (95%).'),
                  ])),
                  const SizedBox(height: 6),
                  Text(
                    'Swings: ${usdRate(st.sdPerHour)} standard deviation. '
                    '${need == null ? '' : need <= st.hours ? 'Your sample pins the rate within ±\$10/hr.' : 'About ${_thousands((need - st.hours).ceil())} more hours to pin it within ±\$10/hr.'}',
                    style: TextStyle(fontSize: 13, color: _mutedInk),
                  ),
                ],
              ),
      ),
      const SizedBox(height: 12),
      // Plotted against hours played — meaningless until some are recorded.
      if (st.hours > 0) ...[
        _Card(
          title: 'RUNNING TOTAL',
          child: RunningTotalChart(points: st.runningTotal),
        ),
        const SizedBox(height: 12),
      ],
      _Card(
        title: 'BEST & WORST',
        child: Column(children: [
          _sessionLine('Best', st.best!),
          const SizedBox(height: 6),
          _sessionLine('Worst', st.worst!),
        ]),
      ),
      for (final (title, buckets) in [
        ('BY STAKES', st.byStakes),
        ('BY GAME', st.byGame),
        ('BY VENUE', st.byVenue),
        ('BY DAY OF WEEK', st.byWeekday),
        ('BY SESSION LENGTH', st.byLength),
      ])
        if (buckets.length > 1) ...[
          const SizedBox(height: 12),
          _Card(title: title, child: _BucketTable(buckets)),
        ],
    ];
  }

  Widget _sessionLine(String label, Session s) => Row(children: [
        SizedBox(
            width: 48,
            child: Text(label, style: TextStyle(fontSize: 12, color: _mutedInk))),
        Expanded(
          child: Text(
              '${shortDate(s.createdAt)}, ${s.createdAt.year} · ${s.venue} · '
              '${durationLabel(s.duration())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        ),
        Text(usd(s.net!, signed: true),
            style: TextStyle(
                fontWeight: FontWeight.w700, color: _signColor(s.net!))),
      ]);

  List<Widget> _mttBody(MttStats st) {
    if (st.entries == 0) return [_empty('tournaments')];
    return [
      _TileGrid(tiles: [
        _Tile('NET', usd(st.net, signed: true), _signColor(st.net)),
        _Tile('ROI', '${st.roiPct!.round()}%', _signColor(st.roiPct!)),
        _Tile('IN THE MONEY', '${st.itmPct!.round()}%'),
        _Tile('ENTRIES', '${st.entries}'),
        _Tile('BUY-INS', usd(st.buyIns)),
        _Tile('CASHES', usd(st.cashes)),
        _Tile('BIGGEST CASH',
            st.biggestCash == null ? '—' : usd(st.biggestCash!)),
        _Tile('HOURS', hoursShort(st.hours)),
      ]),
      const SizedBox(height: 12),
      Text(
        'Tournament results swing hard — ROI over a few dozen entries says '
        'very little on its own.',
        style: TextStyle(fontSize: 12, color: _mutedInk),
      ),
    ];
  }
}

class _Tile {
  final String label, value;
  final Color? color;
  const _Tile(this.label, this.value, [this.color]);
}

class _TileGrid extends StatelessWidget {
  final List<_Tile> tiles;
  const _TileGrid({required this.tiles});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          const gap = 8.0;
          final w = (c.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final t in tiles)
                Container(
                  width: w,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.label,
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                              color: _mutedInk)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(t.value,
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: t.color ?? Colors.white)),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                    color: _gold)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
}

class _BucketTable extends StatelessWidget {
  final List<Bucket> buckets;
  const _BucketTable(this.buckets);

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(fontSize: 10, letterSpacing: 1, color: _mutedInk);
    Widget cell(String t, {TextStyle? style, bool left = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(t,
              textAlign: left ? TextAlign.left : TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style ?? const TextStyle(fontSize: 13)),
        );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.2),
        1: FlexColumnWidth(0.8),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1.4),
        4: FlexColumnWidth(1.4),
      },
      children: [
        TableRow(children: [
          cell('', left: true),
          cell('SESS', style: head),
          cell('HRS', style: head),
          cell('NET', style: head),
          cell('PER HR', style: head),
        ]),
        for (final b in buckets)
          TableRow(children: [
            cell(b.label, left: true),
            cell('${b.sessions}'),
            cell(hoursShort(b.hours)),
            cell(usd(b.net, signed: true),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _signColor(b.net))),
            cell(usdRate(b.hourly)),
          ]),
      ],
    );
  }
}
