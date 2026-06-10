import 'package:flutter/material.dart';
import '../plo_engine.dart';
import '../util.dart';

/// Renders ONLY what the engine says is legal. No poker logic lives here —
/// every amount is pre-computed, pot-limit-capped, and stack-capped upstream.
///
/// Sizing presets differ by game: cash gets Fold / Call / Pot; MTT gets
/// Fold / Call / 2x / 2.5x / 3x / Pot (multipliers of the bet being faced,
/// clamped to the pot-limit max). A small "…" stays for capturing odd sizes.
class ActionBar extends StatelessWidget {
  final LegalActions la;
  final void Function(ActionType type, {int? amount}) onAction;
  final bool isMtt;
  final int currentBet; // highest street commitment faced — the "x" base
  const ActionBar({
    super.key,
    required this.la,
    required this.onAction,
    required this.isMtt,
    required this.currentBet,
  });

  static const _red = Color(0xFFE24B4A);
  static const _green = Color(0xFF1D9E75);

  @override
  Widget build(BuildContext context) {
    final isBet = la.canCheck; // facing no bet → aggression is a "bet"
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
                  la.canCheck ? 'Check' : 'Call ${fmtAmt(la.toCall)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
        if (la.canBetOrRaise && la.sizing != null) ...[
          const SizedBox(height: 8),
          Row(children: _raiseButtons(context, isBet)),
        ],
      ],
    );
  }

  List<Widget> _raiseButtons(BuildContext context, bool isBet) {
    final act = isBet ? ActionType.bet : ActionType.raise;
    final min = la.minRaiseTo!;
    final max = la.maxRaiseTo!;
    final pot = la.sizing!.pot;
    final out = <Widget>[];

    if (isMtt) {
      for (final m in const [2.0, 2.5, 3.0]) {
        final raw = (m * currentBet).round();
        if (raw >= min && raw < max) {
          out.add(Expanded(
            child: _sizeBtn(_multLabel(m), raw, () => onAction(act, amount: raw)),
          ));
          out.add(const SizedBox(width: 6));
        }
      }
    }

    // Pot (emphasised) — the only raise size offered in cash.
    out.add(Expanded(
      flex: 2,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: () => onAction(act, amount: pot),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('POT',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            Text(fmtAmt(pot),
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    ));
    out.add(const SizedBox(width: 6));
    // Custom — kept so any non-preset size can still be captured accurately.
    out.add(OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
        minimumSize: const Size(0, 0),
      ),
      onPressed: () => _customRaise(context, isBet),
      child: const Text('…', style: TextStyle(fontSize: 16)),
    ));
    return out;
  }

  String _multLabel(double m) =>
      m == m.roundToDouble() ? '${m.toInt()}x' : '${m}x';

  Widget _sizeBtn(String label, int amount, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        minimumSize: const Size(0, 0),
      ),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text(fmtAmt(amount),
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Future<void> _customRaise(BuildContext context, bool isBet) async {
    final min = la.minRaiseTo!;
    final max = la.maxRaiseTo!;
    if (min >= max) {
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
                  '${isBet ? 'Bet' : 'Raise to'} ${fmtAmt(value)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600),
                ),
                Slider(
                  min: min.toDouble(),
                  max: max.toDouble(),
                  value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
                  onChanged: (v) => setSheet(() {
                    final snapped = (v / 100).round() * 100;
                    value = snapped.clamp(min, max);
                  }),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Min ${fmtAmt(min)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5))),
                    Text('Max (pot) ${fmtAmt(max)}',
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
