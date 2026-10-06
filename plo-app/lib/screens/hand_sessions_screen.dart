import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../models/hand_session.dart';
import '../tracker/format.dart';
import 'hand_list_screen.dart';

/// Every hand-logging session, newest first, with its hand count — the way
/// back to past hands for review, replay and solver export. No money here:
/// results live in the session tracker.
class HandSessionsScreen extends StatefulWidget {
  const HandSessionsScreen({super.key});
  @override
  State<HandSessionsScreen> createState() => _HandSessionsScreenState();
}

class _HandSessionsScreenState extends State<HandSessionsScreen> {
  late Future<List<({HandSession session, int handCount})>> _future =
      HandStore.instance.listHandSessions();

  void _refresh() =>
      setState(() => _future = HandStore.instance.listHandSessions());

  Future<void> _open(HandSession s) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => HandListScreen(session: s)));
    _refresh();
  }

  Future<void> _confirmDelete(HandSession s, int handCount) async {
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
    if (yes != true) return;
    await HandStore.instance.deleteHandSession(s.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Session deleted'), duration: Duration(seconds: 2)));
    _refresh();
  }

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
              child: Text('No hands logged yet.',
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final (:session, :handCount) = rows[i];
              final s = session;
              return ListTile(
                title: Text('${s.stakesLabel} · ${s.venue}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${shortDate(s.createdAt)}, ${s.createdAt.year} · '
                    '${durationLabel(s.duration())}'),
                trailing: s.isActive
                    ? const Text('LIVE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFFF0C75A)))
                    : Text('$handCount hand${handCount == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7))),
                onTap: () => _open(s),
                onLongPress: () => _confirmDelete(s, handCount),
              );
            },
          );
        },
      ),
    );
  }
}
