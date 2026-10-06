import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../export/download_web.dart';
import '../export/review_export.dart';
import '../export/solver_export.dart';
import '../models/hand_session.dart';
import '../tracker/format.dart';
import '../util.dart';
import '../widgets/hand_session_sheet.dart';
import 'capture_screen.dart';
import 'replayer_screen.dart';

/// One hand session's logged hands: replay, export for the solver, delete.
/// No money — session results live in the tracker.
class HandListScreen extends StatefulWidget {
  final HandSession session;
  const HandListScreen({super.key, required this.session});
  @override
  State<HandListScreen> createState() => _HandListScreenState();
}

class _HandListScreenState extends State<HandListScreen> {
  late HandSession _s = widget.session;
  late Future<List<Map<String, dynamic>>> _future;
  Timer? _tick; // keeps the live session clock current

  @override
  void initState() {
    super.initState();
    chipMode = _s.isMtt;
    _future = HandStore.instance.handsForSession(_s.id);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _s.isActive) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _refresh() =>
      setState(() => _future = HandStore.instance.handsForSession(_s.id));

  /// Edit venue, stakes, table size and times. PLO/PLO5 is fixed once the
  /// session has hands; the hands keep their own recorded blinds either way.
  Future<void> _edit() async {
    final hasHands =
        (await HandStore.instance.handsForSession(_s.id)).isNotEmpty;
    if (!mounted) return;
    final next = await handSessionSheet(context,
        gameType: _s.gameType, initial: _s, lockGame: hasHands);
    if (next == null) return;
    await HandStore.instance.updateHandSession(next);
    if (mounted) setState(() => _s = next);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static bool _isSpotJson(Map<String, dynamic> h) =>
      (h['meta'] as Map<String, dynamic>?)?['complete'] == false;

  Future<void> _exportForSolver() async {
    final messenger = ScaffoldMessenger.of(context);
    final all = await HandStore.instance.handJsonsForSession(_s.id);
    if (all.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No hands to export yet.')));
      return;
    }
    // Decision spots carry no hero action — they belong to the review flow, not
    // the population aggregator (which would refuse them as noHeroAction). Route
    // by meta.complete; only completed hands contribute frequencies.
    final spots = all.where(_isSpotJson).length;
    final complete = all.where((h) => !_isSpotJson(h)).toList();
    if (complete.isEmpty) {
      messenger.showSnackBar(SnackBar(
          content: Text('$spots decision spot${spots == 1 ? '' : 's'} — '
              'export each for review (tap ⋮ → Export for review).')));
      return;
    }
    final now = DateTime.now();
    final date = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    final bundle = exportPopulation(complete, capturedThrough: date);
    final venue =
        _s.venue.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    downloadZip('population_${venue}_$date.zip', bundle.files);
    if (!mounted) return;
    await _showExportSummary(bundle, spots);
  }

  Future<void> _exportHandForReview(String handId) async {
    final messenger = ScaffoldMessenger.of(context);
    final hand = await HandStore.instance.getHand(handId);
    final rec = buildReviewExport(hand);
    downloadText(rec.filename, rec.contents);
    if (!mounted) return;
    messenger
        .showSnackBar(SnackBar(content: Text('Exported ${rec.filename}')));
  }

  Future<void> _confirmEndSession() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End session?'),
        content: const Text('Its hands stay in Past sessions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End session')),
        ],
      ),
    );
    if (yes != true) return;
    final now = DateTime.now();
    await HandStore.instance.endHandSession(_s.id);
    if (!mounted) return;
    setState(() => _s = _s.ended(now));
    Navigator.pop(context); // back home
  }

  Future<void> _confirmDeleteRow(String handId) async {
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
      await HandStore.instance.deleteHand(handId);
      _refresh();
    }
  }

  Future<void> _showExportSummary(SolverBundle b, int spotCount) async {
    String label(RefusalReason r) => switch (r) {
          RefusalReason.limp => 'Limped pots (no-limp trees)',
          RefusalReason.raiseCapExceeded => 'Past the 5-bet cap',
          RefusalReason.offBandStack => 'Off-band stack depth',
          RefusalReason.offBandStraddle => 'Off-band straddle size',
          RefusalReason.noHeroAction => 'Hero never acted',
          RefusalReason.illegalReplay => 'Could not replay',
          RefusalReason.notPlo4 => 'PLO5 (the solver is 4-card only)',
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
            if (spotCount > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$spotCount decision spot${spotCount == 1 ? '' : 's'} not '
                'included — export each for review (⋮ → Export for review).',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
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
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: Text('${s.stakesLabel} · ${s.venue}'),
        actions: [
          IconButton(
            tooltip: 'Edit session',
            icon: const Icon(Icons.edit_note),
            onPressed: _edit,
          ),
          // The solver is 4-card PLO only — no solver exports for PLO5.
          if (!s.isPlo5)
            IconButton(
              tooltip: 'Export for solver',
              icon: const Icon(Icons.ios_share),
              onPressed: _exportForSolver,
            ),
          if (s.isActive)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _confirmEndSession,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('End'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE24B4A),
                  backgroundColor: const Color(0x1AE24B4A),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SessionHeader(session: s),
          const Divider(height: 1),
          Expanded(child: _handList()),
        ],
      ),
    );
  }

  Widget _handList() {
    return FutureBuilder(
        future: _future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final hands = snap.data!;
          if (hands.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No hands logged yet.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.5))),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
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
              final label = handLabel(
                  jsonDecode(h['json'] as String) as Map<String, dynamic>);
              final time =
                  '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
              return ListTile(
                leading: isSpot
                    ? const Icon(Icons.bookmark,
                        color: Color(0xFFF0C75A), size: 20)
                    : marked
                        ? const Icon(Icons.flag,
                            color: Color(0xFFEF9F27), size: 20)
                        : const Icon(Icons.style_outlined, size: 20),
                title: Text(
                  isSpot ? '$label  (spot)' : label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: isSpot ? const Color(0xFFF0C75A) : null),
                ),
                subtitle: Text(
                    !isSpot && pot != null ? '$time · Pot ${money(pot)}' : time),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (net != null)
                      Text(
                        money(net),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: net >= 0
                              ? const Color(0xFF5DCAA5)
                              : const Color(0xFFE24B4A),
                        ),
                      ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          color: isSpot ? const Color(0xFFF0C75A) : null),
                      tooltip: 'Hand actions',
                      onSelected: (v) {
                        final id = h['hand_id'] as String;
                        if (v == 'review') _exportHandForReview(id);
                        if (v == 'delete') _confirmDeleteRow(id);
                      },
                      itemBuilder: (_) => [
                        if (!_s.isPlo5) // the solver is 4-card only
                          const PopupMenuItem(
                              value: 'review',
                              child: ListTile(
                                  leading: Icon(Icons.ios_share, size: 20),
                                  title: Text('Export for review'),
                                  contentPadding: EdgeInsets.zero)),
                        const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                                leading: Icon(Icons.delete_outline, size: 20),
                                title: Text('Delete'),
                                contentPadding: EdgeInsets.zero)),
                      ],
                    ),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ReplayerScreen(handId: h['hand_id'] as String)),
                ),
                onLongPress: () => _confirmDeleteRow(h['hand_id'] as String),
              );
            },
          );
        },
      );
  }
}

/// Session status strip: the live clock, or — once ended — when it ran.
class _SessionHeader extends StatelessWidget {
  final HandSession session;
  const _SessionHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: s.isActive
          ? Row(children: [
              const Icon(Icons.circle, size: 9, color: Color(0xFFF0C75A)),
              const SizedBox(width: 6),
              Text('LIVE · ${durationLabel(s.duration())}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Color(0xFFF0C75A))),
            ])
          : Text(
              '${shortDate(s.createdAt)} · ${clock(s.createdAt)}–'
              '${clock(s.endedAt!)} · ${durationLabel(s.duration())}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
