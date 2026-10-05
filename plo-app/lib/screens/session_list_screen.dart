import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../models/session.dart';
import '../tracker/format.dart';

typedef SessionRow = ({Session session, int handCount, int handsNet});

/// The tracker's Sessions tab: every session newest-first with its result.
/// The right-hand number is the session result (cash-out − buy-in), never the
/// sum of captured hands; sessions without a result say so.
class SessionListView extends StatelessWidget {
  final List<SessionRow> rows;
  final Future<void> Function(Session) onOpen;
  final VoidCallback onChanged;
  const SessionListView(
      {super.key,
      required this.rows,
      required this.onOpen,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
              'No sessions yet.\nStart one from the home screen, or tap '
              '“Log session” to add one you’ve already played.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final r = rows[i];
        final s = r.session;
        final net = s.net;
        final hands = r.handCount == 0
            ? ''
            : ' · ${r.handCount} hand${r.handCount == 1 ? '' : 's'}';
        return ListTile(
          title: Text('${s.stakesLabel} · ${s.venue}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${shortDate(s.createdAt)}, ${s.createdAt.year} · '
              '${durationLabel(s.duration())}$hands'),
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
          onLongPress: () => _confirmDelete(context, s, r.handCount),
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, Session s, int handCount) async {
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
