import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../plo_engine.dart';
import '../util.dart';

/// The signature element: a solver-style table — brass rail, radial-green felt,
/// circular seat badges, a white dealer disk at the button, a clearly-marked
/// hero seat, live pot + SPR in the centre, and PLO Show emblems flanking it.
/// Shared by capture AND the replayer. Hero is anchored at the bottom.
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

  // palette
  static const _goldLt = Color(0xFFEBCE7A);
  static const _goldMid = Color(0xFFB8862F);
  static const _goldDk = Color(0xFF5E441C);
  static const _teal = Color(0xFF21D6A6);
  static const _feltCtr = Color(0xFF2C7A52);
  static const _feltEdge = Color(0xFF123E2A);
  static const _seatFill = Color(0xFF16181B);
  static const _red = Color(0xFFE24B4A);

  double? _spr() {
    final pot = engine.pot;
    if (pot <= 0) return null;
    final inHand = engine.players.values.where((p) => !p.folded).toList();
    if (inHand.length < 2) return null;
    final eff =
        inHand.map((p) => p.stack).reduce((a, b) => a < b ? a : b);
    return eff / pot;
  }

  @override
  Widget build(BuildContext context) {
    final seats = engine.players.keys.toList()..sort();
    final n = seats.length;
    final heroIdx = seats.indexOf(heroSeat);
    final actor = engine.whoseTurn();
    final btnIdx = seats.indexOf(engine.buttonSeat);

    double theta(int k) => math.pi / 2 + (k - heroIdx) * 2 * math.pi / n;

    return Center(
      child: AspectRatio(
        aspectRatio: 1.9,
        child: LayoutBuilder(builder: (ctx, c) {
          final tableW = c.maxWidth;
          final seatD = (tableW * 0.115).clamp(40.0, 60.0);
          final btnTh = theta(btnIdx);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // ---- brass rail
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.96,
                  heightFactor: 0.94,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_goldLt, _goldMid, _goldDk],
                        stops: [0.0, 0.45, 1.0],
                      ),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black54,
                            blurRadius: 18,
                            offset: Offset(0, 6)),
                      ],
                    ),
                  ),
                ),
              ),
              // ---- felt
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.90,
                  heightFactor: 0.82,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const RadialGradient(
                        center: Alignment.center,
                        radius: 0.75,
                        colors: [_feltCtr, _feltEdge],
                      ),
                    ),
                  ),
                ),
              ),
              // ---- inner betting line
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.78,
                  heightFactor: 0.60,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: _goldLt.withValues(alpha: 0.22), width: 1),
                    ),
                  ),
                ),
              ),
              // ---- flanking emblems (subtle circular watermark)
              for (final dx in const [-0.5, 0.5])
                Align(
                  alignment: Alignment(dx, 0),
                  child: Opacity(
                    opacity: 0.34,
                    child: ClipOval(
                      child: Image.asset('assets/emblem.png',
                          width: tableW * 0.13,
                          height: tableW * 0.13,
                          fit: BoxFit.cover),
                    ),
                  ),
                ),
              // ---- centre pot + SPR
              Align(
                alignment: const Alignment(0, 0),
                child: _PotPill(pot: engine.pot, spr: _spr()),
              ),
              // ---- bet pills (street commitment in front of each seat)
              for (var k = 0; k < n; k++)
                if (!engine.players[seats[k]]!.folded &&
                    engine.players[seats[k]]!.streetCommit > 0)
                  Align(
                    alignment: Alignment(
                        math.cos(theta(k)) * 0.66, math.sin(theta(k)) * 0.62),
                    child: _BetPill(
                        amount: engine.players[seats[k]]!.streetCommit),
                  ),
              // ---- dealer disk, just inside the rail at the button
              Align(
                alignment:
                    Alignment(math.cos(btnTh) * 0.66, math.sin(btnTh) * 0.62),
                child: _DealerDisk(d: seatD * 0.42),
              ),
              // ---- seats
              for (var k = 0; k < n; k++)
                Align(
                  alignment: Alignment(
                      math.cos(theta(k)) * 0.96, math.sin(theta(k)) * 0.92),
                  child: _SeatBadge(
                    diameter: seatD,
                    player: engine.players[seats[k]]!,
                    label: positions[seats[k]] ?? '?',
                    isHero: seats[k] == heroSeat,
                    isActor: seats[k] == actor,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _PotPill extends StatelessWidget {
  final int pot;
  final double? spr;
  const _PotPill({required this.pot, required this.spr});

  @override
  Widget build(BuildContext context) {
    final suffix = tableUnit == TableUnit.bb ? ' BB' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0D0F0B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SeatRing._goldMid, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'POT: ${fmtAmt(pot)}$suffix',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5),
          ),
          if (spr != null)
            Text(
              'SPR ${spr!.toStringAsFixed(1)}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: SeatRing._goldLt,
                  letterSpacing: 1.0),
            ),
        ],
      ),
    );
  }
}

class _BetPill extends StatelessWidget {
  final int amount;
  const _BetPill({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xE6121009),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SeatRing._goldMid, width: 1),
      ),
      child: Text(
        fmtAmt(amount),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: SeatRing._goldLt),
      ),
    );
  }
}

class _DealerDisk extends StatelessWidget {
  final double d;
  const _DealerDisk({required this.d});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFD6D6D6)],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text('D',
          style: TextStyle(
              fontSize: d * 0.5,
              fontWeight: FontWeight.w900,
              color: Colors.black87)),
    );
  }
}

class _SeatBadge extends StatelessWidget {
  final double diameter;
  final PlayerState player;
  final String label;
  final bool isHero;
  final bool isActor;
  const _SeatBadge({
    required this.diameter,
    required this.player,
    required this.label,
    required this.isHero,
    required this.isActor,
  });

  @override
  Widget build(BuildContext context) {
    final ring = isActor
        ? SeatRing._teal
        : isHero
            ? SeatRing._goldLt
            : Colors.white.withValues(alpha: 0.20);
    final glow = isActor
        ? SeatRing._teal
        : isHero
            ? SeatRing._goldMid
            : null;

    return Opacity(
      opacity: player.folded ? 0.32 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SeatRing._seatFill,
              border: Border.all(
                  color: ring, width: (isActor || isHero) ? 2.6 : 1.2),
              boxShadow: glow == null
                  ? null
                  : [
                      BoxShadow(
                          color: glow.withValues(alpha: 0.55),
                          blurRadius: isActor ? 14 : 9,
                          spreadRadius: isActor ? 1.5 : 0.5),
                    ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: diameter * 0.24,
                    fontWeight: FontWeight.w800,
                    color: isActor
                        ? SeatRing._teal
                        : isHero
                            ? SeatRing._goldLt
                            : Colors.white,
                  ),
                ),
                Text(
                  player.isAllIn ? 'ALL-IN' : fmtAmt(player.stack),
                  style: TextStyle(
                    fontSize: diameter * 0.185,
                    fontWeight: FontWeight.w600,
                    color: player.isAllIn
                        ? SeatRing._red
                        : Colors.white.withValues(alpha: 0.66),
                  ),
                ),
              ],
            ),
          ),
          if (isHero)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: SeatRing._goldMid,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text('YOU',
                  style: TextStyle(
                      fontSize: diameter * 0.17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.black)),
            ),
        ],
      ),
    );
  }
}
