import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../models/session.dart';
import '../util.dart';
import 'capture_screen.dart';
import 'replayer_screen.dart';

class HandListScreen extends StatefulWidget {
  final Session session;
  const HandListScreen({super.key, required this.session});
  @override
  State<HandListScreen> createState() => _HandListScreenState();
}

class _HandListScreenState extends State<HandListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    chipMode = widget.session.isMtt;
    _future = HandStore.instance.handsForSession(widget.session.id);
  }

  void _refresh() => setState(
      () => _future = HandStore.instance.handsForSession(widget.session.id));

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar:
          AppBar(title: Text('${s.stakesLabel} · ${s.venue}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CaptureScreen(session: s)),
          );
          _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Log hand'),
      ),
      body: FutureBuilder(
        future: _future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final hands = snap.data!;
          if (hands.isEmpty) {
            return Center(
              child: Text('No hands logged yet.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            );
          }
          return ListView.separated(
            itemCount: hands.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final h = hands[i];
              final net = h['hero_net'] as int?;
              final pot = h['pot'] as int?;
              final at = DateTime.fromMillisecondsSinceEpoch(
                  h['captured_at'] as int);
              final marked = (h['marked'] as int) == 1;
              return ListTile(
                leading: marked
                    ? const Icon(Icons.flag, color: Color(0xFFEF9F27), size: 20)
                    : const Icon(Icons.style_outlined, size: 20),
                title: Text(pot != null ? 'Pot ${money(pot)}' : 'Hand'),
                subtitle: Text(
                    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'),
                trailing: net == null
                    ? null
                    : Text(
                        money(net),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: net >= 0
                              ? const Color(0xFF5DCAA5)
                              : const Color(0xFFE24B4A),
                        ),
                      ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ReplayerScreen(handId: h['hand_id'] as String)),
                ),
                onLongPress: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete hand?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (yes == true) {
                    await HandStore.instance
                        .deleteHand(h['hand_id'] as String);
                    _refresh();
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
