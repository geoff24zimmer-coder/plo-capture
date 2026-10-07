import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../models/hand_session.dart';
import '../tracker/format.dart';
import '../widgets/backup_sheet.dart';
import '../widgets/hand_session_sheet.dart';
import '../widgets/home_actions.dart';
import 'capture_screen.dart';
import 'equity_screen.dart';
import 'hand_list_screen.dart';
import 'hand_sessions_screen.dart';
import 'tracker_screen.dart';

/// App home: log played hands (resume the current hand session in one tap, or
/// start one) and the past hand sessions, the session tracker (results), and
/// the equity calculator — separate features, equal-weight buttons.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  ({HandSession session, int handCount})? _current;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    HandStore.instance.currentHandSession().then((c) {
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
                child: Stack(children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Image.asset('assets/logo.png',
                          fit: BoxFit.contain,
                          semanticLabel: 'The PLO Show App'),
                    ),
                  ),
                  // Whole-device backup: covers the tracker AND logged hands,
                  // so it lives here rather than inside either feature.
                  Positioned(
                    top: 0,
                    right: -12,
                    child: IconButton(
                      tooltip: 'Backup & restore',
                      icon: Icon(Icons.import_export,
                          color: Colors.white.withValues(alpha: 0.6)),
                      onPressed: () =>
                          showBackupSheet(context, onRestored: _load),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              if (_current != null)
                _ResumeCard(current: _current!, onTap: _resume),
              // The app's three features, deliberately equal in weight: same
              // size and style, each with its own accent.
              HomeAction(
                title: 'Log played hands',
                subtitle: 'Capture a hand in 15 seconds',
                icon: Icons.style_outlined,
                accent: homeEmerald,
                onTap: _logHands,
              ),
              const SizedBox(height: 12),
              HomeAction(
                title: 'Past sessions',
                subtitle: 'Replay & review your hands',
                icon: Icons.history,
                accent: homeViolet,
                onTap: () => _push(const HandSessionsScreen()),
              ),
              const SizedBox(height: 12),
              HomeAction(
                title: 'Session tracker',
                subtitle: 'Results, calendar & win rate',
                icon: Icons.calendar_month_outlined,
                accent: homeGold,
                onTap: () => _push(const TrackerScreen()),
              ),
              const SizedBox(height: 12),
              HomeAction(
                title: 'Equity calculator',
                subtitle: 'PLO & PLO5 odds, any board',
                icon: Icons.percent,
                accent: homeBlue,
                onTap: () => _push(const EquityScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Log played hands" → cash or tournament → the session setup sheet.
  Future<void> _logHands() async {
    final type = await pickGameType(context);
    if (type == null || !mounted) return;
    await _start(context, type);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Future<void> _resume(HandSession s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HandListScreen(session: s)),
    );
    _load();
  }

  Future<void> _start(BuildContext context, String gameType) async {
    final session = await handSessionSheet(context, gameType: gameType);
    if (session == null) return;
    await HandStore.instance.createHandSession(session);
    if (!context.mounted) return;
    // Straight to capturing a hand — the 15-second path.
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CaptureScreen(session: session)),
    );
    _load();
  }
}

/// Prominent "pick up where you left off" card for the active session.
class _ResumeCard extends StatelessWidget {
  final ({HandSession session, int handCount}) current;
  final Future<void> Function(HandSession) onTap;
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
