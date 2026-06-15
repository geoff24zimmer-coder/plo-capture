import 'package:flutter/material.dart';

/// The first-run walkthrough widget — a short, dismissible sequence of cards
/// that takes a brand-new user start-to-finish through logging one hand, with
/// the two genuinely non-obvious mechanics (you claim your seat mid-action;
/// cash is preflop-only) called out explicitly.
///
/// Pure Flutter (no platform glue) so it renders in widget tests. The
/// "show once" plumbing + the localStorage seen-flag live in onboarding.dart.
Widget buildFirstRunGuide() => const _GuideDialog();

const Color _gold = Color(0xFFC9A536);
const Color _goldLight = Color(0xFFF0C75A);
const Color _green = Color(0xFF10B981);

class _Step {
  final IconData icon;
  final Color accent;
  final String title;
  final List<TextSpan> body;
  const _Step(this.icon, this.accent, this.title, this.body);
}

TextSpan _t(String s) => TextSpan(text: s);
TextSpan _b(String s) => TextSpan(
    text: s,
    style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white));

final List<_Step> _steps = [
  _Step(Icons.bolt, _goldLight, 'Log a hand in ~15 seconds', [
    _t('A quick walkthrough of the whole flow — you’ll only see this once. '
        'You can reopen it anytime from the '),
    _b('?'),
    _t(' in the top bar.'),
  ]),
  _Step(Icons.tune, _green, '1 · Set up the hand', [
    _t('Blinds and stacks are pre-filled ('),
    _b('100bb'),
    _t(' by default). For a cash game, tap a straddle if there was one — '),
    _b('No straddle / UTG / Button'),
    _t(' — then tap '),
    _b('Start hand'),
    _t('.'),
  ]),
  _Step(Icons.touch_app, _goldLight, '2 · Replay the action in order', [
    _t('An '),
    _b('amber pointer'),
    _t(' marks who’s to act. Tap what each player did — '),
    _b('Fold, Call, Raise'),
    _t(' — going around the table. Only the legal pot-limit options appear, so '
        'you can’t mis-enter a raise size.'),
  ]),
  _Step(Icons.star, _gold, '3 · Claim your seat — the one trick', [
    _t('You do '),
    _b('not'),
    _t(' pick your seat first. When the pointer reaches your spot, tap '),
    _b('“This is me”'),
    _t(' and choose your four cards. That’s the whole trick.'),
  ]),
  _Step(Icons.casino, _green, '4 · Cash vs. Tournament', [
    _t('Cash captures '),
    _b('preflop only'),
    _t(' — it ends at the flop, on purpose. Tournaments play out fully: you’ll '
        'add the flop, turn, and river, then '),
    _b('tap the winning seat'),
    _t('.'),
  ]),
  _Step(Icons.check_circle, _goldLight, '5 · Save it', [
    _t('Tap '),
    _b('Save hand'),
    _t(' — it lands in your hand list to replay, share, or export to the '
        'solver. Then tap '),
    _b('+ Log hand'),
    _t(' for the next one. (Mid-hand, '),
    _b('Save spot'),
    _t(' banks just your decision.)'),
  ]),
];

class _GuideDialog extends StatefulWidget {
  const _GuideDialog();
  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  int _i = 0;

  bool get _isLast => _i == _steps.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
    } else {
      setState(() => _i++);
    }
  }

  void _back() => setState(() => _i = _i > 0 ? _i - 1 : 0);

  @override
  Widget build(BuildContext context) {
    final step = _steps[_i];
    return Dialog(
      backgroundColor: const Color(0xFF16181B),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF2A2D31)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: step.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(step.icon, color: step.accent, size: 24),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.5)),
                    child: Text(_isLast ? 'Close' : 'Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(step.title,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2)),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.82)),
                  children: step.body,
                ),
              ),
              const SizedBox(height: 20),
              // Progress dots on their own row so they never collide with the
              // nav buttons on a narrow screen.
              Wrap(
                children: [
                  for (int k = 0; k < _steps.length; k++)
                    Container(
                      width: k == _i ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5, bottom: 4),
                      decoration: BoxDecoration(
                        color: k == _i
                            ? _goldLight
                            : Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 4,
                overflowSpacing: 4,
                children: [
                  if (_i > 0)
                    TextButton(
                      onPressed: _back,
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.7)),
                      child: const Text('Back'),
                    ),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: const Color(0xFF0C0F0E),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    child: Text(_isLast ? 'Start logging' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
