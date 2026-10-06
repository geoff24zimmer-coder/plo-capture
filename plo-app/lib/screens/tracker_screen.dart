import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../db/hand_store.dart';
import '../export/download_web.dart';
import '../export/file_pick_web.dart';
import '../models/session.dart';
import '../tracker/backup.dart';
import '../tracker/format.dart';
import '../widgets/ledger_calendar.dart';
import '../widgets/session_editor.dart';
import '../widgets/tracker_stats_view.dart';
import 'session_list_screen.dart';

/// The session tracker: Calendar (the paper ledger, digital), Stats (win rate),
/// and Sessions (every session, with its result). Sessions are started live
/// here (clock, add-ons, End → cash-out) or logged after the fact. Separate
/// from hand logging by design: the tracker never reads captured hands.
/// Also home to the device backup — the only copy of a player's history lives
/// in this browser.
class TrackerScreen extends StatefulWidget {
  final int initialTab;
  const TrackerScreen({super.key, this.initialTab = 0});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  List<Session>? _sessions;
  Object? _error;
  Timer? _tick; // keeps the live session clock current

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _live != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sessions = await HandStore.instance.listTrackerSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The session being played right now, if any.
  Session? get _live {
    for (final s in _sessions ?? const <Session>[]) {
      if (s.isActive) return s;
    }
    return null;
  }

  Future<void> _save(Session s) async {
    await HandStore.instance.updateTrackerSession(s);
    await _load();
  }

  Future<void> _open(Session s) async {
    final next = await editSession(context, initial: s);
    if (next != null) await _save(next);
  }

  Future<void> _startSession() async {
    final s = await editSession(context, startNow: true);
    if (s == null) return;
    await HandStore.instance.createTrackerSession(s);
    await _load();
  }

  Future<void> _logSession() async {
    final s = await editSession(context);
    if (s == null) return;
    await HandStore.instance.createTrackerSession(s);
    await _load();
  }

  Future<void> _addOn(Session s) async {
    final amt = await rebuyDialog(context);
    if (amt == null || amt == 0) return;
    await _save(s.copyWith(buyIn: () => (s.buyIn ?? 0) + amt));
  }

  Future<void> _end(Session s) async {
    final messenger = ScaffoldMessenger.of(context);
    final ended = await endSessionDialog(context, s);
    if (ended == null) return;
    await _save(ended);
    final net = ended.net;
    messenger.showSnackBar(SnackBar(
        content: Text(net == null
            ? 'Session ended — tap it any time to add the result.'
            : 'Session ended · ${usd(net, signed: true)}')));
  }

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  Future<void> _menu(String v) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (v) {
      case 'backup':
        final doc = await HandStore.instance.exportAll();
        downloadText('plo-show-backup_${_stamp()}.json', jsonEncode(doc));
        messenger.showSnackBar(const SnackBar(
            content: Text('Backup downloaded — keep it somewhere safe.')));
      case 'csv':
        downloadText('plo-show-sessions_${_stamp()}.csv',
            sessionsCsv(_sessions ?? const []),
            mime: 'text/csv');
      case 'restore':
        await _restore();
    }
  }

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    final String? text;
    try {
      text = await pickTextFile();
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Couldn’t read that file.')));
      return;
    }
    if (text == null || !mounted) return;
    final BackupData data;
    try {
      data = parseBackup(text);
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
            'Adds ${_count(data.trackerSessions.length, 'tracker session')} '
            'and ${_count(data.hands.length, 'logged hand')}. Anything '
            'already on this device is kept as-is.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (yes != true) return;
    final r = await HandStore.instance.importBackup(data);
    await _load();
    messenger.showSnackBar(SnackBar(
        content: Text('Restored '
            '${_count(r.trackerAdded, 'tracker session')}, '
            '${_count(r.handsAdded, 'logged hand')}'
            '${r.skipped > 0 ? ' (${r.skipped} already here)' : ''}.')));
  }

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final loaded = _sessions;
    final sessions = loaded ?? const <Session>[];
    final live = _live;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tracker'),
          actions: [
            IconButton(
              tooltip: 'Log a past session',
              icon: const Icon(Icons.edit_calendar),
              onPressed: _logSession,
            ),
            PopupMenuButton<String>(
              tooltip: 'Backup & export',
              onSelected: _menu,
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                        leading: Icon(Icons.download, size: 20),
                        title: Text('Download backup'),
                        subtitle: Text(
                            'Tracker + logged hands, to restore later'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'restore',
                    child: ListTile(
                        leading: Icon(Icons.restore, size: 20),
                        title: Text('Restore from backup'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'csv',
                    child: ListTile(
                        leading: Icon(Icons.table_chart_outlined, size: 20),
                        title: Text('Export sessions (CSV)'),
                        contentPadding: EdgeInsets.zero)),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Calendar'),
            Tab(text: 'Stats'),
            Tab(text: 'Sessions'),
          ]),
        ),
        floatingActionButton: live != null || loaded == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _startSession,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start session'),
              ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load sessions:\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFE24B4A))),
                ),
              )
            : loaded == null
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    if (live != null)
                      _LiveBar(
                        session: live,
                        onAddOn: () => _addOn(live),
                        onEnd: () => _end(live),
                        onEdit: () => _open(live),
                      ),
                    Expanded(
                      child: TabBarView(children: [
                        LedgerCalendar(sessions: sessions, onOpen: _open),
                        TrackerStatsView(sessions: sessions),
                        SessionListView(
                            sessions: sessions,
                            onOpen: _open,
                            onChanged: _load),
                      ]),
                    ),
                  ]),
      ),
    );
  }
}

/// The session being played now: clock, money in, Add on, End (→ cash-out).
class _LiveBar extends StatelessWidget {
  final Session session;
  final VoidCallback onAddOn, onEnd, onEdit;
  const _LiveBar({
    required this.session,
    required this.onAddOn,
    required this.onEnd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Material(
      color: const Color(0xFF16181B),
      child: InkWell(
        onTap: onEdit,
        child: Container(
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFC9A536)))),
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.circle, size: 9, color: Color(0xFFF0C75A)),
                    const SizedBox(width: 6),
                    Text('LIVE · ${durationLabel(s.duration())}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Color(0xFFF0C75A))),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${s.stakesLabel} · '
                    '${s.buyIn == null ? 'no buy-in yet' : 'in for ${usd(s.buyIn!)}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: onAddOn,
              child: Text(s.buyIn == null ? 'Buy-in' : 'Add on'),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: onEnd,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE24B4A),
                backgroundColor: const Color(0x1AE24B4A),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: const Text('End'),
            ),
          ]),
        ),
      ),
    );
  }
}
