import 'package:flutter/material.dart';

import '../models/session.dart';
import '../tracker/format.dart';

const _gold = Color(0xFFF0C75A);

/// Full tracker session form: log a past session ([initial] null), start a
/// live one now ([startNow]), or edit one. Returns the [Session], or null if
/// cancelled.
Future<Session?> editSession(
  BuildContext context, {
  Session? initial,
  bool startNow = false,
}) =>
    Navigator.push<Session>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _SessionEditor(initial: initial, startNow: startNow),
      ),
    );

/// The cash-out prompt when ending a live session. Returns the session with
/// the result filled in and [Session.endedAt] set, or null if cancelled.
/// "End without result" ends it unresolved (it'll show as needing a result).
///
/// The start time is shown and editable: a player who opens the app only
/// after the session (start → cash-out in a minute) can set when they really
/// sat down, so the session gets real hours instead of none.
Future<Session?> endSessionDialog(BuildContext context, Session s) async {
  final inCtrl = TextEditingController(text: dollarsField(s.buyIn));
  final outCtrl = TextEditingController();
  var start = s.createdAt;
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        final now = DateTime.now();
        final played = now.difference(start);
        final short = played < Session.minTimed;
        return AlertDialog(
          title: const Text('End session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${s.stakesLabel} · ${s.venue}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text('Started ${clock(start)}'),
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(start),
                          helpText: 'WHEN DID YOU START PLAYING?');
                      if (t == null) return;
                      final picked = startFromClock(
                          t.hour, t.minute, DateTime.now());
                      setDialog(() => start = picked);
                    },
                  ),
                  Text(durationLabel(played),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65))),
                ],
              ),
              if (short)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Logging after you played? Tap the start time and set when '
                    'you sat down — otherwise this session won’t count toward '
                    'your hourly rate.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFFEF9F27)),
                  ),
                ),
              const SizedBox(height: 10),
              _MoneyField(
                  controller: inCtrl,
                  label: s.isMtt
                      ? 'Total buy-ins'
                      : 'Total buy-in (incl. rebuys)'),
              const SizedBox(height: 10),
              _MoneyField(
                  controller: outCtrl,
                  label: s.isMtt ? 'Prize won (0 if busted)' : 'Cash-out',
                  autofocus: true),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'skip'),
                child: const Text('End without result')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'end'),
                child: const Text('End session')),
          ],
        );
      },
    ),
  );
  if (action == null) return null;
  final now = DateTime.now();
  final ended = s.copyWith(
    createdAt: start,
    endedAt: () => now,
    buyIn: () => parseDollars(inCtrl.text),
  );
  if (action == 'skip') return ended;
  return ended.copyWith(cashOut: () => parseDollars(outCtrl.text));
}

/// The most recent moment at [hour]:[minute] not after [now] — a start time
/// picked "later than now" means yesterday (a session past midnight).
DateTime startFromClock(int hour, int minute, DateTime now) {
  final t = DateTime(now.year, now.month, now.day, hour, minute);
  return t.isAfter(now) ? t.subtract(const Duration(days: 1)) : t;
}

/// Add a rebuy/add-on to a live session's buy-in. Returns cents, or null.
Future<int?> rebuyDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add on'),
      content: _MoneyField(controller: ctrl, label: 'Amount', autofocus: true),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add')),
      ],
    ),
  );
  return ok == true ? parseDollars(ctrl.text) : null;
}

class _MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  const _MoneyField(
      {required this.controller, required this.label, this.autofocus = false});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, prefixText: '\$ '),
      );
}

class _SessionEditor extends StatefulWidget {
  final Session? initial;
  final bool startNow;
  const _SessionEditor({this.initial, required this.startNow});

  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  late String _type, _game;
  late DateTime _start;
  DateTime? _end; // null only while editing a live session
  late final TextEditingController _venue,
      _sb,
      _bb,
      _in,
      _out,
      _finish,
      _entrants,
      _notes;

  bool get _isNew => widget.initial == null;
  bool get _isMtt => _type == 'mtt';

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    final now = DateTime.now();
    // A new log defaults to "a 4-hour session that just ended".
    final end = DateTime(
        now.year, now.month, now.day, now.hour, now.minute - now.minute % 15);
    _type = s?.gameType ?? 'cash';
    _game = s?.game ?? 'plo4';
    final live = s == null && widget.startNow;
    _start = s?.createdAt ??
        (live ? now : end.subtract(const Duration(hours: 4)));
    _end = s == null ? (live ? null : end) : s.endedAt;
    _venue = TextEditingController(text: s?.venue ?? '');
    _sb = TextEditingController(
        text: s == null ? '2' : dollarsField(s.smallBlind));
    _bb =
        TextEditingController(text: s == null ? '5' : dollarsField(s.bigBlind));
    _in = TextEditingController(text: dollarsField(s?.buyIn));
    _out = TextEditingController(text: dollarsField(s?.cashOut));
    _finish = TextEditingController(text: s?.mttFinish?.toString() ?? '');
    _entrants = TextEditingController(text: s?.mttEntrants?.toString() ?? '');
    _notes = TextEditingController(text: s?.notes ?? '');
    // Live net preview beside the cash-out field.
    _in.addListener(_onMoney);
    _out.addListener(_onMoney);
  }

  void _onMoney() => setState(() {});

  @override
  void dispose() {
    for (final c in [_venue, _sb, _bb, _in, _out, _finish, _entrants, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    final len = _end?.difference(_start);
    setState(() {
      _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
      if (len != null) _end = _start.add(len);
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final base = start ? _start : (_end ?? _start);
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return;
    setState(() {
      if (start) {
        final len = _end?.difference(_start);
        _start =
            DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
        if (len != null && !len.isNegative) _end = _start.add(len);
      } else {
        // An end time "before" the start means the session ran past midnight.
        var e =
            DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
        if (!e.isAfter(_start)) e = e.add(const Duration(days: 1));
        _end = e;
      }
    });
  }

  void _save() {
    final buyIn = parseDollars(_in.text);
    final cashOut = parseDollars(_out.text);
    final base = widget.initial ??
        Session(
          id: 'session-${DateTime.now().microsecondsSinceEpoch}',
          createdAt: _start,
          gameType: _type,
          smallBlind: 0,
          bigBlind: 0,
          venue: '',
          maxSeats: 8,
          endedAt: _end,
        );
    final venue = _venue.text.trim();
    Navigator.pop(
      context,
      base.copyWith(
        createdAt: _start,
        gameType: _type,
        game: _game,
        smallBlind: _isMtt ? 0 : parseDollars(_sb.text) ?? base.smallBlind,
        bigBlind: _isMtt ? 0 : parseDollars(_bb.text) ?? base.bigBlind,
        venue: venue.isEmpty ? (_isMtt ? 'Tournament' : 'Cash game') : venue,
        endedAt: () => _end,
        buyIn: () => buyIn,
        cashOut: () => _end == null ? null : cashOut,
        mttFinish: () => _isMtt ? int.tryParse(_finish.text.trim()) : null,
        mttEntrants: () => _isMtt ? int.tryParse(_entrants.text.trim()) : null,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = _end == null;
    final buyIn = parseDollars(_in.text), cashOut = parseDollars(_out.text);
    final net = buyIn != null && cashOut != null ? cashOut - buyIn : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(!_isNew
            ? 'Edit session'
            : live
                ? 'Start session'
                : 'Log a session'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
                onPressed: _save,
                child: Text(_isNew && live ? 'Start' : 'Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Cash')),
              ButtonSegment(value: 'mtt', label: Text('Tournament')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              for (final e in Session.gameLabels.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {_game},
            onSelectionChanged: (v) => setState(() => _game = v.first),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _venue,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
                labelText: _isMtt ? 'Tournament / venue' : 'Venue'),
          ),
          if (!_isMtt) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _MoneyField(controller: _sb, label: 'SB')),
              const SizedBox(width: 12),
              Expanded(child: _MoneyField(controller: _bb, label: 'BB')),
            ]),
          ],
          const SizedBox(height: 18),
          _sectionLabel('WHEN'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text('${shortDate(_start)}, ${_start.year}'),
                  onPressed: _pickDate),
              ActionChip(
                  label: Text('Start ${clock(_start)}'),
                  onPressed: () => _pickTime(start: true)),
              if (!live)
                ActionChip(
                    label: Text('End ${clock(_end!)}'),
                    onPressed: () => _pickTime(start: false)),
              Text(
                live
                    ? 'In progress · ${durationLabel(DateTime.now().difference(_start))}'
                    : durationLabel(_end!.difference(_start)),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionLabel('RESULT'),
          _MoneyField(
              controller: _in,
              label: _isMtt
                  ? 'Total buy-ins (incl. fee, re-entries)'
                  : 'Total buy-in (incl. rebuys)'),
          if (!live) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _out,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _isMtt
                    ? 'Prize won incl. bounties (0 if busted)'
                    : 'Cash-out',
                prefixText: '\$ ',
                helperText:
                    net == null ? 'Leave blank if you don’t know yet' : null,
                suffixText: net == null ? null : usd(net, signed: true),
                suffixStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: (net ?? 0) >= 0
                        ? const Color(0xFF5DCAA5)
                        : const Color(0xFFE24B4A)),
              ),
            ),
          ],
          if (_isMtt) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _finish,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Finish (place)'))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _entrants,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Entrants'))),
            ]),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: _gold)),
      );
}
