import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../models/session.dart';
import '../util.dart';
import 'hand_list_screen.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});
  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  late Future<List<({Session session, int handCount, int net})>> _future;

  @override
  void initState() {
    super.initState();
    _future = HandStore.instance.listSessions();
  }

  void _refresh() =>
      setState(() => _future = HandStore.instance.listSessions());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past sessions')),
      body: FutureBuilder(
        future: _future,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load sessions:\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE24B4A))),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return Center(
              child: Text('No past sessions yet.\nStart one from the home screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final r = rows[i];
              final s = r.session;
              final net = r.net;
              return ListTile(
                title: Text('${s.stakesLabel} · ${s.venue}'),
                subtitle: Text(
                    '${_dateLabel(s.createdAt)} · ${r.handCount} hands'),
                trailing: Text(
                  moneyFor(net, s.gameType),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: net >= 0
                        ? const Color(0xFF5DCAA5)
                        : const Color(0xFFE24B4A),
                  ),
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => HandListScreen(session: s)),
                  );
                  _refresh();
                },
                onLongPress: () => _confirmDelete(s, r.handCount),
              );
            },
          );
        },
      ),
    );
  }

  String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _confirmDelete(Session s, int handCount) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(handCount == 0
            ? 'Delete “${s.stakesLabel} · ${s.venue}”?'
            : 'Delete “${s.stakesLabel} · ${s.venue}” and its '
                '$handCount hand${handCount == 1 ? '' : 's'}? '
                'This can’t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE24B4A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await HandStore.instance.deleteSession(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Session deleted'),
            duration: Duration(seconds: 2)),
      );
      _refresh();
    }
  }
}
