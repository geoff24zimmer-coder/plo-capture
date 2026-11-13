// The AI coach's own list (ai-hand-reviewer D36), opened from the home screen: every logged hand the coach can
// review, newest first, from all sessions. Geoff found the coach "slightly cumbersome to find": before this, an old
// hand took Past sessions → session → hand → scrolling past the replay controls. Now it's two taps from home.
//
// Built for older players first (docs/UX_SIMPLICITY.md): large text, big rows, one action per row.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../coach/coach_client.dart';
import '../db/hand_store.dart';
import '../tracker/format.dart';
import '../util.dart';
import 'coach_review_screen.dart';

typedef LoadRecentHands = Future<List<Map<String, dynamic>>> Function();

Future<List<Map<String, dynamic>>> _recentHands() =>
    HandStore.instance.recentHands();

const _gold = Color(0xFFF0C75A);

class CoachHandsScreen extends StatefulWidget {
  /// For tests; the device's hand store otherwise.
  final LoadRecentHands load;
  final Widget Function(Map<String, dynamic> hand)? reviewScreen;
  final bool Function(Map<String, dynamic> hand) canReview;
  const CoachHandsScreen({
    super.key,
    this.load = _recentHands,
    this.reviewScreen,
    this.canReview = coachCanReview,
  });

  @override
  State<CoachHandsScreen> createState() => _CoachHandsScreenState();
}

class _CoachHandsScreenState extends State<CoachHandsScreen> {
  late Future<List<_Row>> _rows = _read();

  Future<List<_Row>> _read() async => [
        for (final r in await widget.load())
          if (_reviewable(r)) _Row(r),
      ];

  bool _reviewable(Map<String, dynamic> r) {
    try {
      return widget
          .canReview(jsonDecode(r['json'] as String) as Map<String, dynamic>);
    } catch (_) {
      return false;
    }
  }

  Future<void> _open(_Row row) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            widget.reviewScreen?.call(row.hand) ??
            CoachReviewScreen(hand: row.hand)));
    // A new review shows as reviewed.
    if (mounted) setState(() => _rows = _read());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AI coach')),
        body: SafeArea(
          child: FutureBuilder<List<_Row>>(
            future: _rows,
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _gold));
              }
              final rows = snap.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Text(
                    rows.isEmpty
                        ? 'No hands for the coach yet.\n\nLog a cash-game hand where you act before the flop, '
                            'then come back here.'
                        : 'Tap a hand for the coach\'s review of your play before the flop.',
                    style: const TextStyle(fontSize: 20, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  for (final row in rows) _tile(row),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(disclosure,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.white60)),
                  ),
                ],
              );
            },
          ),
        ),
      );

  Widget _tile(_Row row) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(row),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.label,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(row.when,
                          style: const TextStyle(
                              fontSize: 17, color: Colors.white70)),
                    ],
                  ),
                ),
                if (row.reviewed)
                  const _Badge('Reviewed')
                else
                  const Icon(Icons.school_outlined, color: _gold, size: 28),
                const Icon(Icons.chevron_right, color: Colors.white54),
              ]),
            ),
          ),
        ),
      );
}

class _Row {
  final Map<String, dynamic> hand;
  final String label;
  final String when;
  final bool reviewed;

  _Row._(this.hand, this.label, this.when, this.reviewed);

  factory _Row(Map<String, dynamic> r) {
    final hand = jsonDecode(r['json'] as String) as Map<String, dynamic>;
    final at = DateTime.fromMillisecondsSinceEpoch(r['captured_at'] as int);
    final stakes = hand['session']?['stakes'];
    final blinds = stakes is Map && stakes['sb'] is int && stakes['bb'] is int
        ? ' · ${money(stakes['sb'] as int)}/${money(stakes['bb'] as int)}'
        : '';
    return _Row._(
        hand,
        handLabel(hand),
        '${shortDate(at)} · ${clock(at)}$blinds',
        (r['reviewed'] as int? ?? 0) == 1);
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: _gold),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: _gold)),
      );
}
