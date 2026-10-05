import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../models/session.dart';
import '../tracker/format.dart';
import 'capture_screen.dart';
import 'equity_screen.dart';
import 'hand_list_screen.dart';
import 'tracker_screen.dart';

/// App home. Resume the current (unfinished) session in one tap, or start a new
/// one; the tracker (calendar, win rate, every past session) is one tap away.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  ({Session session, int handCount, int handsNet})? _current;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    HandStore.instance.currentSession().then((c) {
      if (mounted) setState(() => _current = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo takes the space left over after the (fixed) controls and
              // scales to fit — so the buttons are ALWAYS visible, even on short
              // screens where a fixed-size logo would push them off the bottom.
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_current != null) _ResumeCard(current: _current!, onTap: _resume),
              _StartButton(
                label: 'Cash Game',
                icon: Icons.payments_outlined,
                color: const Color(0xFF10B981),
                onTap: () => _start(context, 'cash'),
              ),
              const SizedBox(height: 14),
              _StartButton(
                label: 'Tournament',
                icon: Icons.emoji_events_outlined,
                color: const Color(0xFFC9A536),
                onTap: () => _start(context, 'mtt'),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: _ToolButton(
                    label: 'Tracker',
                    icon: Icons.calendar_month_outlined,
                    onTap: () => _push(const TrackerScreen()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ToolButton(
                    label: 'Equity',
                    icon: Icons.percent,
                    onTap: () => _push(const EquityScreen()),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Future<void> _resume(Session s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HandListScreen(session: s)),
    );
    _load();
  }

  Future<void> _start(BuildContext context, String gameType) async {
    final session = await _sessionSheet(context, gameType);
    if (session == null) return;
    await HandStore.instance.createSession(session);
    if (!context.mounted) return;
    // PLO4 goes straight to capturing a hand (the 15-second path); other games
    // track results only, so they land on the session screen.
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => session.canCaptureHands
              ? CaptureScreen(session: session)
              : HandListScreen(session: session)),
    );
    _load();
  }

  /// Quick session setup: venue (+ cash stakes) + table size. Returns a built
  /// Session, or null if cancelled.
  Future<Session?> _sessionSheet(BuildContext context, String gameType) async {
    final isMtt = gameType == 'mtt';
    final venueCtrl = TextEditingController();
    final sbCtrl = TextEditingController(text: '2');
    final bbCtrl = TextEditingController(text: '5');
    final buyInCtrl = TextEditingController();
    var seats = 8;
    var game = 'plo4';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(isMtt ? 'New tournament' : 'New cash game',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: [
                  for (final e in Session.gameLabels.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {game},
                onSelectionChanged: (v) => setSheet(() => game = v.first),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: venueCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                    labelText: isMtt ? 'Tournament / venue' : 'Venue'),
              ),
              if (!isMtt) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: sbCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'SB \$'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: bbCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'BB \$'))),
                ]),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: buyInCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: isMtt ? 'Buy-in incl. fee (optional)' : 'Buy-in (optional)',
                    prefixText: '\$ '),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Table size'),
                Expanded(
                  child: Slider(
                    min: 2,
                    max: 10,
                    divisions: 8,
                    value: seats.toDouble(),
                    label: '$seats',
                    onChanged: (v) => setSheet(() => seats = v.round()),
                  ),
                ),
                Text('$seats-max'),
              ]),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isMtt ? 'Start tournament' : 'Start cash game'),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return null;
    return Session(
      id: 'session-${DateTime.now().microsecondsSinceEpoch}',
      createdAt: DateTime.now(),
      gameType: gameType,
      smallBlind:
          isMtt ? 0 : ((double.tryParse(sbCtrl.text) ?? 2) * 100).round(),
      bigBlind:
          isMtt ? 0 : ((double.tryParse(bbCtrl.text) ?? 5) * 100).round(),
      venue: venueCtrl.text.trim().isEmpty
          ? (isMtt ? 'Tournament' : 'Cash game')
          : venueCtrl.text.trim(),
      maxSeats: seats,
      game: game,
      buyIn: parseDollars(buyInCtrl.text),
    );
  }
}

/// Prominent "pick up where you left off" card for the active session.
class _ResumeCard extends StatelessWidget {
  final ({Session session, int handCount, int handsNet}) current;
  final Future<void> Function(Session) onTap;
  const _ResumeCard({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = current.session;
    final hands = current.handCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: const Color(0xFF16181B),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTap(s),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFC9A536), width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill,
                    color: Color(0xFFF0C75A), size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('RESUME SESSION',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFF0C75A),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0)),
                      const SizedBox(height: 3),
                      Text('${s.stakesLabel} · ${s.venue}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      Text(
                        [
                          durationLabel(s.duration()),
                          if (s.buyIn != null) 'in for ${usd(s.buyIn!)}',
                          if (hands > 0) '$hands hand${hands == 1 ? '' : 's'}',
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StartButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 24),
      label: Text(label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Secondary home-screen destination (Tracker, Equity).
class _ToolButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ToolButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.85),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
}
