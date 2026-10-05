import 'dart:convert';

import 'package:flutter/material.dart';

import '../db/hand_store.dart';
import '../export/download_web.dart';
import '../export/file_pick_web.dart';
import '../models/session.dart';
import '../tracker/backup.dart';
import '../widgets/ledger_calendar.dart';
import '../widgets/session_editor.dart';
import '../widgets/tracker_stats_view.dart';
import 'hand_list_screen.dart';
import 'session_list_screen.dart';

/// The session tracker: Calendar (the paper ledger, digital), Stats (win rate),
/// and Sessions (every session, with its result). Also home to the device
/// backup — the only copy of a player's history lives in this browser.
class TrackerScreen extends StatefulWidget {
  final int initialTab;
  const TrackerScreen({super.key, this.initialTab = 0});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  List<SessionRow>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await HandStore.instance.listSessions();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(Session s) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => HandListScreen(session: s)));
    await _load();
  }

  Future<void> _logSession() async {
    final s = await editSession(context);
    if (s == null) return;
    await HandStore.instance.createSession(s);
    await _load();
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
            sessionsCsv([for (final r in _rows ?? <SessionRow>[]) r.session]),
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
            'Adds ${data.sessions.length} session'
            '${data.sessions.length == 1 ? '' : 's'} and ${data.hands.length} '
            'hand${data.hands.length == 1 ? '' : 's'}. Anything already on this '
            'device is kept as-is.'),
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
    final skipped = r.sessionsSkipped + r.handsSkipped;
    messenger.showSnackBar(SnackBar(
        content: Text('Restored ${r.sessionsAdded} sessions, ${r.handsAdded} '
            'hands${skipped > 0 ? ' ($skipped already here)' : ''}.')));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final sessions = [for (final r in rows ?? <SessionRow>[]) r.session];
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tracker'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Backup & export',
              onSelected: _menu,
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                        leading: Icon(Icons.download, size: 20),
                        title: Text('Download backup'),
                        subtitle: Text('Sessions + hands, to restore later'),
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _logSession,
          icon: const Icon(Icons.edit_calendar),
          label: const Text('Log session'),
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
            : rows == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    LedgerCalendar(sessions: sessions, onOpen: _open),
                    TrackerStatsView(sessions: sessions),
                    SessionListView(
                        rows: rows, onOpen: _open, onChanged: _load),
                  ]),
      ),
    );
  }
}
