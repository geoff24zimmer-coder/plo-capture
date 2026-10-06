import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../models/session.dart';
import '../tracker/format.dart';

/// The tracker's Sessions tab: every session newest-first with its result
/// (cash-out − buy-in); sessions without a result say so.
class SessionListView extends StatelessWidget {
  final List<Session> sessions;
  final Future<void> Function(Session) onOpen;
  final VoidCallback onChanged;
  const SessionListView(
      {super.key,
      required this.sessions,
      required this.onOpen,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
              'No sessions yet.\nTap “Start session” when you sit down, or '
              'the calendar icon to log one you’ve already played.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final s = sessions[i];
        final net = s.net;
        return ListTile(
          title: Text('${s.stakesLabel} · ${s.venue}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${shortDate(s.createdAt)}, ${s.createdAt.year} · '
              '${durationLabel(s.duration())}'),
          trailing: s.isActive
              ? const _Tag('LIVE', Color(0xFFF0C75A))
              : net == null
                  ? const _Tag('ADD RESULT', Color(0xFFEF9F27))
                  : Text(
                      usd(net, signed: true),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: net >= 0
                            ? const Color(0xFF5DCAA5)
                            : const Color(0xFFE24B4A),
                      ),
                    ),
          onTap: () => onOpen(s),
          onLongPress: () => _confirmDelete(context, s),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Session s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text('Delete “${s.stakesLabel} · ${s.venue}”? '
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
      await HandStore.instance.deleteTrackerSession(s.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Session deleted'), duration: Duration(seconds: 2)),
      );
      onChanged();
    }
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: color)),
      );
}
