import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../export/download_web.dart';
import '../export/solver_export.dart';
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

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _exportForSolver() async {
    final messenger = ScaffoldMessenger.of(context);
    final hands =
        await HandStore.instance.handJsonsForSession(widget.session.id);
    if (hands.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No hands to export yet.')));
      return;
    }
    final now = DateTime.now();
    final date = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    final bundle = exportPopulation(hands, capturedThrough: date);
    final venue =
        widget.session.venue.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    downloadZip('population_${venue}_$date.zip', bundle.files);
    if (!mounted) return;
    await _showExportSummary(bundle);
  }

  Future<void> _showExportSummary(SolverBundle b) async {
    String label(RefusalReason r) => switch (r) {
          RefusalReason.limp => 'Limped pots (no-limp trees)',
          RefusalReason.raiseCapExceeded => 'Past the 5-bet cap',
          RefusalReason.offBandStack => 'Off-band stack depth',
          RefusalReason.offBandStraddle => 'Off-band straddle size',
          RefusalReason.noHeroAction => 'Hero never acted',
          RefusalReason.illegalReplay => 'Could not replay',
        };
    final refused = b.refusals.entries.where((e) => e.value > 0).toList();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solver export'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${b.acceptedHands} of ${b.totalHands} hands placed '
              'across ${b.manifest['node_count']} nodes.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (refused.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Dropped (${b.totalHands - b.acceptedHands}):',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.7))),
              const SizedBox(height: 4),
              for (final e in refused)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${e.value} · ${label(e.key)}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7))),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: Text('${s.stakesLabel} · ${s.venue}'),
        actions: [
          IconButton(
            tooltip: 'Export for solver',
            icon: const Icon(Icons.ios_share),
            onPressed: _exportForSolver,
          ),
        ],
      ),
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
              final isSpot = (h['is_spot'] as int? ?? 0) == 1;
              return ListTile(
                leading: isSpot
                    ? const Icon(Icons.bookmark,
                        color: Color(0xFFF0C75A), size: 20)
                    : marked
                        ? const Icon(Icons.flag,
                            color: Color(0xFFEF9F27), size: 20)
                        : const Icon(Icons.style_outlined, size: 20),
                title: isSpot
                    ? const Text('Decision spot',
                        style: TextStyle(
                            color: Color(0xFFF0C75A),
                            fontWeight: FontWeight.w600))
                    : Text(pot != null ? 'Pot ${money(pot)}' : 'Hand'),
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
