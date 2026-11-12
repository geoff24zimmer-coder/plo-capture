// The AI coach's review of a logged hand (ai-hand-reviewer D30). Opened from the replayer, after the hand: this is a
// study screen, never part of capture at the table.
//
// Built for older players first (ai-hand-reviewer docs/UX_SIMPLICITY.md): body text at least 20 px, buttons at least
// 56 px tall, one main action. The coach takes about a minute, so the waiting view says what's happening and the
// player can stop. Each decision's "Go deeper" (D31) stays closed until tapped, so the short review is easy to read.

import 'dart:async';

import 'package:flutter/material.dart';

import '../coach/coach_client.dart';

typedef ReviewRequest = Future<CoachReply> Function(Map<String, dynamic> hand);

const _gold = Color(0xFFF0C75A);
const _labelColors = {
  CoachLabel.clear: Color(0xFF10B981),
  CoachLabel.close: Color(0xFFF0C75A),
  CoachLabel.judgment: Color(0xFF8AB4F8),
};

const _steps = [
  'Looking at your hand…',
  'Working out the pot and the price…',
  'Comparing your cards with likely hands…',
  'Thinking through the ranges and blockers…',
  'Writing your deep dive…',
  'Checking every number…',
  'Taking a second look…',
  'Almost done…',
];

const disclosure = 'AI coach · for study only, not for use during play';

class CoachReviewScreen extends StatefulWidget {
  final Map<String, dynamic> hand;

  /// For tests; the real coach otherwise.
  final ReviewRequest request;
  const CoachReviewScreen({super.key, required this.hand, this.request = requestReview});

  @override
  State<CoachReviewScreen> createState() => _CoachReviewScreenState();
}

class _CoachReviewScreenState extends State<CoachReviewScreen> {
  CoachReview? _review;
  String? _error;
  int _step = 0;
  Timer? _ticker;
  int _run = 0;

  String? get _id => widget.hand['hand_id'] as String?;

  @override
  void initState() {
    super.initState();
    final cached = _id == null ? null : reviewCache[_id];
    if (cached != null) {
      _review = cached;
    } else {
      _ask();
    }
  }

  Future<void> _ask() async {
    final run = ++_run;
    setState(() {
      _error = null;
      _step = 0;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) setState(() => _step = (_step + 1).clamp(0, _steps.length - 1));
    });
    final reply = await widget.request(widget.hand);
    _ticker?.cancel();
    if (!mounted || run != _run) return;
    setState(() {
      if (reply.ok) {
        _review = reply.review;
        if (_id != null) reviewCache[_id!] = reply.review!;
      } else {
        _error = reply.message;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return Scaffold(
      appBar: AppBar(title: const Text('AI coach review')),
      body: SafeArea(
        child: review != null
            ? _reviewView(review)
            : _error != null
                ? _errorView(_error!)
                : _waitingView(),
      ),
    );
  }

  Widget _big(String text, {bool primary = true, required VoidCallback onPressed}) => SizedBox(
        width: double.infinity,
        height: 60,
        child: primary
            ? FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: Colors.black),
                child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              )
            : OutlinedButton(
                onPressed: onPressed,
                child: Text(text, style: const TextStyle(fontSize: 20)),
              ),
      );

  Widget _disclosure() => const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Text(disclosure,
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white60)),
      );

  Widget _waitingView() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: _gold),
            const SizedBox(height: 28),
            Text(_steps[_step],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('The coach takes about a minute.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: Colors.white70)),
            const SizedBox(height: 28),
            _big('Stop', primary: false, onPressed: () => Navigator.of(context).pop()),
            _disclosure(),
          ],
        ),
      );

  Widget _errorView(String message) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 28),
            _big('Try again', onPressed: _ask),
            const SizedBox(height: 12),
            _big('Back to the hand', primary: false, onPressed: () => Navigator.of(context).pop()),
            _disclosure(),
          ],
        ),
      );

  Widget _reviewView(CoachReview review) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          for (final d in review.decisions) _decisionCard(d),
          if (review.assumptions.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('What I assumed',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final a in review.assumptions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $a', style: const TextStyle(fontSize: 20)),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          _big('Back to the hand', onPressed: () => Navigator.of(context).pop()),
          _disclosure(),
        ],
      );

  Widget _decisionCard(CoachDecision d) {
    final color = _labelColors[d.label]!;
    const part = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 0.5);
    const body = TextStyle(fontSize: 20, height: 1.35);
    final ref = d.actionRef.isEmpty ? d.actionRef : d.actionRef[0].toUpperCase() + d.actionRef.substring(1);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${d.label.name_}  ',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                TextSpan(text: d.label.words, style: const TextStyle(fontSize: 20)),
              ])),
            ),
            const SizedBox(height: 12),
            Text(ref, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text('VERDICT', style: part),
            Text(d.verdict, style: body.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text('WHY', style: part),
            Text(d.why, style: body),
            const SizedBox(height: 12),
            const Text('NEXT TIME', style: part),
            Text(d.nextTime, style: body.copyWith(color: _gold)),
            if (d.deepDive.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DeepDive(points: d.deepDive),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Go deeper": a big tappable row that opens the coach's strategy points.
class _DeepDive extends StatefulWidget {
  final List<String> points;
  const _DeepDive({required this.points});
  @override
  State<_DeepDive> createState() => _DeepDiveState();
}

class _DeepDiveState extends State<_DeepDive> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _open,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _open = !_open),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Icon(_open ? Icons.expand_less : Icons.expand_more, color: _gold),
                      const SizedBox(width: 8),
                      const Text('Go deeper',
                          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: _gold)),
                    ]),
                  ),
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in widget.points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('• $p', style: const TextStyle(fontSize: 20, height: 1.4)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
}
