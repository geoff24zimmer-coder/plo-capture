import 'package:flutter/material.dart';
import '../plo_engine.dart';
import '../util.dart';

/// Renders ONLY what the engine says is legal. No poker logic lives here —
/// every amount is pre-computed, pot-limit-capped, and stack-capped upstream.
class ActionBar extends StatelessWidget {
  final LegalActions la;
  final void Function(ActionType type, {int? amount}) onAction;
  const ActionBar({super.key, required this.la, required this.onAction});

  static const _red = Color(0xFFE24B4A);
  static const _green = Color(0xFF1D9E75);

  @override
  Widget build(BuildContext context) {
    final isBet = la.canCheck; // facing no bet → aggression is a "bet"
    final s = la.sizing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: const BorderSide(color: _red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => onAction(ActionType.fold),
                child: const Text('Fold', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => onAction(
                    la.canCheck ? ActionType.check : ActionType.call),
                child: Text(
                  la.canCheck ? 'Check' : 'Call ${money(la.toCall)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
        if (la.canBetOrRaise && s != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onAction(
                      isBet ? ActionType.bet : ActionType.raise,
                      amount: s.half),
                  child: Text('½  ${money(s.half)}',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onAction(
                      isBet ? ActionType.bet : ActionType.raise,
                      amount: s.threeQuarter),
                  child: Text('¾  ${money(s.threeQuarter)}',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _green),
                  onPressed: () => onAction(
                      isBet ? ActionType.bet : ActionType.raise,
                      amount: s.pot),
                  child: Text('POT  ${money(s.pot)}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _customRaise(context, isBet),
                child: const Text('…'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _customRaise(BuildContext context, bool isBet) async {
    final min = la.minRaiseTo!;
    final max = la.maxRaiseTo!;
    if (min >= max) {
      // Only one legal raise size (a stack-capped all-in) — no slider needed.
      onAction(isBet ? ActionType.bet : ActionType.raise, amount: max);
      return;
    }
    var value = la.sizing!.half;

    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${isBet ? 'Bet' : 'Raise to'} ${money(value)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600),
                ),
                Slider(
                  min: min.toDouble(),
                  max: max.toDouble(),
                  value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
                  onChanged: (v) => setSheet(() {
                    // Snap to whole dollars; endpoints stay exact.
                    final snapped = (v / 100).round() * 100;
                    value = snapped.clamp(min, max);
                  }),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Min ${money(min)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5))),
                    Text('Max (pot) ${money(max)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5))),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, value),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (chosen != null) {
      onAction(isBet ? ActionType.bet : ActionType.raise, amount: chosen);
    }
  }
}
