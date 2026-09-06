import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../db/hand_store.dart';
import '../export/download_web.dart';
import '../export/gif_export.dart';
import '../export/video_export.dart';
import '../hand_loader.dart';
import '../plo_engine.dart';
import '../share_link.dart';
import '../util.dart';
import '../widgets/seat_ring.dart';
import 'landing_screen.dart';

/// Step through a stored hand action-by-action. Each step rebuilds the
/// engine from the start — every frame is a node in the hand's game tree,
/// guaranteed consistent with capture because it's the same state machine.
///
/// Two entry points share this screen:
/// - From the hand list: pass [handId], loaded from the local DB.
/// - From a share link: pass [handJson] directly with [shared] = true — the
///   hand never touches the recipient's DB, autoplay starts on its own, and a
///   "home" affordance leads into the app.
class ReplayerScreen extends StatefulWidget {
  final String? handId;
  final Map<String, dynamic>? handJson;
  final bool shared;
  const ReplayerScreen({
    super.key,
    this.handId,
    this.handJson,
    this.shared = false,
  }) : assert(handId != null || handJson != null,
            'replayer needs a handId or a handJson');
  @override
  State<ReplayerScreen> createState() => _ReplayerScreenState();
}

class _ReplayerScreenState extends State<ReplayerScreen> {
  LoadedHand? _hand;
  HandEngine? _engine;
  int _step = 0;

  // Autoplay: a periodic timer advances one action per tick; the interval is
  // the base step divided by the speed multiplier. Default 2x — the speed the
  // tester asked for when sharing for quick analysis.
  static const _baseStepMs = 1000;
  double _speed = 2;
  bool _playing = false;
  Timer? _timer;

  // Captured for the GIF export: wraps the felt + caption so the rendered clip
  // matches exactly what the replay shows (minus the transport bar).
  final GlobalKey _captureKey = GlobalKey();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final json =
        widget.handJson ?? await HandStore.instance.getHand(widget.handId!);
    final loaded = loadHand(json);
    chipMode = json['session']?['game_type'] == 'mtt';
    tableBigBlind = loaded.cfg.bigBlind;
    if (!mounted) return;
    setState(() {
      _hand = loaded;
      _step = 0;
      _engine = loaded.engineAtStep(0);
    });
    // A shared link is meant to play itself — kick off autoplay once loaded.
    if (widget.shared) _play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goTo(int step) {
    final h = _hand!;
    final s = step.clamp(0, h.actions.length);
    setState(() {
      _step = s;
      _engine = h.engineAtStep(s);
    });
  }

  // ----------------------------------------------------------- autoplay

  void _arm() {
    _timer?.cancel();
    final ms = (_baseStepMs / _speed).round();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (_step >= _hand!.actions.length) {
        _pause();
        return;
      }
      _goTo(_step + 1);
    });
  }

  void _play() {
    if (_hand == null) return;
    // Replay from the top if we're sitting at the end.
    if (_step >= _hand!.actions.length) _goTo(0);
    setState(() => _playing = true);
    _arm();
  }

  void _pause() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _playing = false);
  }

  /// Manual transport (chevrons / slider) interrupts autoplay.
  void _scrubTo(int step) {
    _pause();
    _goTo(step);
  }

  void _cycleSpeed() {
    setState(() => _speed = _speed >= 4
        ? 1
        : _speed >= 2
            ? 4
            : 2);
    if (_playing) _arm();
  }

  String get _speedLabel =>
      _speed == _speed.roundToDouble() ? '${_speed.toInt()}×' : '$_speed×';

  // -------------------------------------------------------------- share

  Future<void> _share() async {
    final url = shareUrlForHand(_hand!.raw);
    // Best-effort auto-copy: a clipboard rejection (e.g. an unfocused browser
    // tab) must never swallow the share sheet, which has its own Copy button.
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.link, size: 20, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('Replay link copied',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Anyone with this link can watch this hand replay — it opens '
                'right in the browser and autoplays. The whole hand travels in '
                'the link; nothing is uploaded.',
                style: TextStyle(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  url,
                  maxLines: 3,
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace', height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy link'),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                mp4ExportAvailable()
                    ? 'Or download an MP4 clip — a standalone file that plays '
                        'and autoplays anywhere (no link, no app needed), but '
                        'not interactive.'
                    : 'Or download a GIF clip — a standalone file that plays '
                        'anywhere (no link, no app needed), but larger and not '
                        'interactive.',
                style: TextStyle(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _exportClip();
                },
                icon: Icon(
                    mp4ExportAvailable()
                        ? Icons.movie_outlined
                        : Icons.gif_box_outlined,
                    size: 20),
                label: Text(mp4ExportAvailable()
                    ? 'Download MP4 clip'
                    : 'Download GIF clip'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Step through every node, snapshot the felt boundary, and normalise each
  /// frame to [maxWidth] immediately — so a high-res capture never holds the
  /// whole raw RGBA sequence in memory at once (matters on phones).
  Future<List<GifFrame>> _captureFrames({required int maxWidth}) async {
    final boundary =
        _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final n = _hand!.actions.length;
    final frames = <GifFrame>[];
    const pixelRatio = 3.0; // capture ≥1080px wide on phones, then downscale
    for (var k = 0; k <= n; k++) {
      _goTo(k);
      // Let CanvasKit lay out and paint the new step before we snapshot it.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 32));
      final im = await boundary.toImage(pixelRatio: pixelRatio);
      final w = im.width, h = im.height;
      final bd = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
      im.dispose();
      if (bd == null) continue;
      frames.add(normalizeFrame(
          GifFrame(w, h,
              bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes)),
          maxWidth: maxWidth));
    }
    return frames;
  }

  /// Render the replay to a shareable clip — a standalone file that plays
  /// anywhere (Discord, messages) with no app or link needed. Prefers MP4
  /// (small, crisp, autoplays inline); falls back to GIF where WebCodecs/H.264
  /// is unavailable. Either way it's the same captured frames.
  Future<void> _exportClip() async {
    final messenger = ScaffoldMessenger.of(context);
    _pause();
    setState(() => _exporting = true);
    final preferMp4 = mp4ExportAvailable();
    messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 45),
        content: Text('Rendering replay ${preferMp4 ? 'MP4' : 'GIF'}…')));
    try {
      // MP4 carries full resolution (1080p, never upscaled past the capture);
      // GIF stays compact (256-colour anyway).
      final frames = await _captureFrames(maxWidth: preferMp4 ? 1080 : 500);
      Uint8List? bytes;
      var name = 'hand_replay.gif';
      var mime = 'image/gif';
      if (preferMp4 && frames.isNotEmpty) {
        try {
          // Repeat the final frame so the result lingers a beat.
          final padded = [...frames, frames.last, frames.last, frames.last];
          bytes = await encodeReplayMp4(padded, fps: 1); // 1× pace: 1s per step
          name = 'hand_replay.mp4';
          mime = 'video/mp4';
        } catch (_) {
          bytes = encodeReplayGif(frames); // runtime H.264 failure → GIF (downscales)
        }
      } else {
        bytes = encodeReplayGif(frames);
      }
      messenger.hideCurrentSnackBar();
      if (bytes == null) {
        messenger
            .showSnackBar(const SnackBar(content: Text('Nothing to render.')));
        return;
      }
      downloadBytes(name, bytes, mime);
      final size = bytes.length >= 1024 * 1024
          ? '${(bytes.length / (1024 * 1024)).toStringAsFixed(1)}MB'
          : '${(bytes.length / 1024).round()}KB';
      messenger.showSnackBar(SnackBar(
          content: Text('Saved $name · ${frames.length} frames · $size')));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger
          .showSnackBar(SnackBar(content: Text('Couldn\'t render clip: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _goHome() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const LandingScreen()));

  @override
  Widget build(BuildContext context) {
    final h = _hand;
    final e = _engine;
    if (h == null || e == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final reached = e.status == HandStatus.showdown ? 3 : e.street.index;
    final shownBoard = <String>[
      if (reached >= 1) ...h.flop,
      if (reached >= 2 && h.turnCard != null) h.turnCard!,
      if (reached >= 3 && h.riverCard != null) h.riverCard!,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shared ? 'Shared replay' : 'Replay'),
        actions: [
          IconButton(
            tooltip: 'Share replay link',
            icon: const Icon(Icons.ios_share),
            onPressed: _exporting ? null : _share,
          ),
          TextButton(
            onPressed: () => setState(() => tableUnit =
                tableUnit == TableUnit.money ? TableUnit.bb : TableUnit.money),
            child: Text(tableUnitLabel,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          // From a share link there's no app behind us — offer a way in.
          if (widget.shared)
            IconButton(
              tooltip: 'Open The PLO Show',
              icon: const Icon(Icons.home_outlined),
              onPressed: _goHome,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // The felt + caption are wrapped in the capture boundary so the
            // exported GIF frames match the replay exactly (sans transport).
            Expanded(
              child: RepaintBoundary(
                key: _captureKey,
                child: Column(
                  children: [
                    Expanded(
                      child: SeatRing(
                          engine: e,
                          heroSeat: h.cfg.heroSeat,
                          heroCards: h.heroCards,
                          board: shownBoard,
                          // Villains' cards are revealed only once the replay
                          // reaches showdown — not during the earlier streets.
                          shownCards: e.status == HandStatus.showdown
                              ? h.shownCards
                              : const {},
                          positions: h.positions),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 24,
                      child: Text(
                        _caption(h, e),
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.75)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child:
                  _exporting ? const LinearProgressIndicator(minHeight: 2) : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _playing ? 'Pause' : 'Play',
                    iconSize: 30,
                    color: const Color(0xFF10B981),
                    onPressed:
                        _exporting ? null : (_playing ? _pause : _play),
                    icon: Icon(_playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill),
                  ),
                  IconButton(
                      onPressed: _exporting || _step == 0
                          ? null
                          : () => _scrubTo(_step - 1),
                      icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: h.actions.length.toDouble(),
                      divisions: h.actions.isEmpty ? 1 : h.actions.length,
                      value: _step.toDouble(),
                      label: '$_step',
                      onChanged: _exporting ? null : (v) => _scrubTo(v.round()),
                    ),
                  ),
                  IconButton(
                      onPressed: _exporting || _step >= h.actions.length
                          ? null
                          : () => _scrubTo(_step + 1),
                      icon: const Icon(Icons.chevron_right)),
                  // Speed toggle: 1× / 2× / 4×.
                  SizedBox(
                    width: 44,
                    child: TextButton(
                      onPressed: _exporting ? null : _cycleSpeed,
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0)),
                      child: Text(_speedLabel,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _caption(LoadedHand h, HandEngine e) {
    if (_step == 0) return 'Cards are dealt';
    final a = e.log.last;
    final pos = h.positions[a.seat] ?? 'Seat ${a.seat}';
    final desc = switch (a.action) {
      ActionType.fold => '$pos folds',
      ActionType.check => '$pos checks',
      ActionType.call => '$pos calls ${money(a.amountToCall)}',
      ActionType.bet => '$pos bets ${money(a.amount!)}',
      ActionType.raise => '$pos raises to ${money(a.amount!)}',
    };
    final allIn = a.isAllIn ? ' (all-in)' : '';
    if (_step == h.actions.length) {
      final result = _resultText(h);
      if (result.isNotEmpty) return '$desc$allIn — $result';
      // Older records: a winner but no pot breakdown.
      if (h.winnerSeat != null) {
        final w = h.positions[h.winnerSeat] ?? 'Seat ${h.winnerSeat}';
        return '$desc$allIn — $w wins ${money(e.pot)}';
      }
    }
    return '$desc$allIn';
  }

  /// Pot-by-pot outcome: "CO wins $2,554", "CO & BTN split $2,554", or with
  /// side pots "CO wins main $2,000 · MP wins side $554".
  String _resultText(LoadedHand h) {
    String names(List<int> seats) =>
        seats.map((s) => h.positions[s] ?? 'Seat $s').join(' & ');
    final parts = <String>[];
    for (final p in h.pots) {
      if (p.winners.isEmpty) continue;
      final verb = p.winners.length == 1 ? 'wins' : 'split';
      final label =
          h.pots.length == 1 ? '' : (p.potType == 'main' ? 'main ' : 'side ');
      parts.add('${names(p.winners)} $verb $label${money(p.amount)}');
    }
    return parts.join(' · ');
  }
}
