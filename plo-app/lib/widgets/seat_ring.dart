import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../plo_engine.dart';
import '../util.dart';

/// The signature element: a ring mirroring the live table. Hero is always
/// anchored at the bottom; the seat with action carries the amber pointer.
class SeatRing extends StatelessWidget {
  final HandEngine engine;
  final int heroSeat;
  final Map<int, String> positions;
  const SeatRing({
    super.key,
    required this.engine,
    required this.heroSeat,
    required this.positions,
  });

  static const _amber = Color(0xFFEF9F27);
  static const _teal = Color(0xFF1D9E75);

  @override
  Widget build(BuildContext context) {
    final seats = engine.players.keys.toList()..sort();
    final n = seats.length;
    final heroIdx = seats.indexOf(heroSeat);
    final actor = engine.whoseTurn();

    return Stack(
      children: [
        // Felt
        Align(
          alignment: Alignment.center,
          child: FractionallySizedBox(
            widthFactor: 0.72,
            heightFactor: 0.62,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.elliptical(400, 280)),
                color: const Color(0xFF12302A),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12), width: 1),
              ),
            ),
          ),
        ),
        // Pot + street
        Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(engine.street.name.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: Colors.white.withValues(alpha: 0.5))),
              Text('Pot ${money(engine.pot)}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        // Seats
        for (var k = 0; k < n; k++)
          Align(
            alignment: _seatAlignment(k, heroIdx, n),
            child: _SeatChip(
              player: engine.players[seats[k]]!,
              label: positions[seats[k]] ?? '?',
              isHero: seats[k] == heroSeat,
              isActor: seats[k] == actor,
              isButton: seats[k] == engine.buttonSeat,
            ),
          ),
      ],
    );
  }

  /// Hero sits at the bottom (angle π/2 in screen coords, y-down);
  /// other seats spaced evenly clockwise from there.
  Alignment _seatAlignment(int k, int heroIdx, int n) {
    final theta = math.pi / 2 + (k - heroIdx) * 2 * math.pi / n;
    return Alignment(math.cos(theta) * 0.94, math.sin(theta) * 0.92);
  }
}

class _SeatChip extends StatelessWidget {
  final PlayerState player;
  final String label;
  final bool isHero;
  final bool isActor;
  final bool isButton;
  const _SeatChip({
    required this.player,
    required this.label,
    required this.isHero,
    required this.isActor,
    required this.isButton,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isActor
        ? SeatRing._amber
        : isHero
            ? SeatRing._teal
            : Colors.white.withValues(alpha: 0.18);

    return Opacity(
      opacity: player.folded ? 0.30 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isActor
                  ? SeatRing._amber.withValues(alpha: 0.15)
                  : const Color(0xFF1B201E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: isActor ? 2 : 1),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActor ? SeatRing._amber : Colors.white)),
                    if (isButton) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 12,
                        height: 12,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Colors.white),
                        child: const Text('D',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.black)),
                      ),
                    ],
                  ],
                ),
                Text(
                  player.isAllIn ? 'ALL-IN' : money(player.stack),
                  style: TextStyle(
                      fontSize: 11,
                      color: player.isAllIn
                          ? const Color(0xFFE24B4A)
                          : Colors.white.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          if (player.streetCommit > 0 && !player.folded)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: SeatRing._teal.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(money(player.streetCommit),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5DCAA5))),
              ),
            ),
        ],
      ),
    );
  }
}
