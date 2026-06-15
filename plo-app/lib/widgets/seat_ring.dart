import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../plo_engine.dart';
import '../util.dart';
import 'card_picker.dart' show suitColor, suitGlyph;

/// Point on a stadium (rounded-rect with semicircular caps) at parametric angle
/// [t], in pixel coords. Seats ride this curve so they all sit ON the gold rail
/// — an ellipse would cut the corners. Works for either orientation: caps on
/// the left/right when [hw] >= [hh] (wide table), or on the top/bottom when
/// [hh] > [hw] (tall/vertical racetrack); the cap radius is min(hw, hh).
Offset _stadiumPoint(double t, double cx, double cy, double hw, double hh) {
  final dx = math.cos(t), dy = math.sin(t);
  final horiz = hw >= hh;
  final r = math.min(hw, hh); // cap radius
  final half = (horiz ? hw - hh : hh - hw); // half-length of the straight side
  final sx = dx.abs() < 1e-6 ? double.infinity : hw / dx.abs();
  final sy = dy.abs() < 1e-6 ? double.infinity : hh / dy.abs();
  var s = math.min(sx, sy); // rectangle boundary
  final inCap = horiz ? (dx * s).abs() > half : (dy * s).abs() > half;
  if (inCap) {
    // Cap circle centred along the straight axis; intersect the ray with it.
    final ccx = horiz ? (dx < 0 ? -half : half) : 0.0;
    final ccy = horiz ? 0.0 : (dy < 0 ? -half : half);
    final b = dx * ccx + dy * ccy; // dir is unit → = dot(dir, capCentre)
    final disc = b * b - (ccx * ccx + ccy * ccy - r * r);
    if (disc >= 0) s = b + math.sqrt(disc);
  }
  return Offset(cx + dx * s, cy + dy * s);
}

/// The signature element: a solver-style table — brass rail, radial-green felt,
/// circular seat badges, a white dealer disk at the button, a clearly-marked
/// hero seat, live pot + SPR in the centre, and PLO Show emblems flanking it.
/// Shared by capture AND the replayer. The [anchorSeat] (default: the hero) is
/// pinned to the bottom of the ring.
class SeatRing extends StatelessWidget {
  final HandEngine engine;
  /// The claimed hero seat, highlighted gold with a YOU pill. Null while no
  /// hero is chosen yet — the capture flow claims a seat mid-action.
  final int? heroSeat;
  /// Seat pinned to the bottom of the ring. Defaults to [heroSeat]; the replayer
  /// keeps hero at the bottom, while live capture anchors the button instead.
  final int? anchorSeat;
  /// Hero's hole cards, laid on the felt in front of the hero seat (wherever it
  /// sits) so they track the player instead of floating at the screen bottom.
  final List<String> heroCards;
  /// Community cards on the felt — empty preflop, up to 5 by the river.
  final List<String> board;
  /// Villain shown cards by seat, laid in front of their seats at showdown.
  final Map<int, List<String>> shownCards;
  final Map<int, String> positions;
  final void Function(int seat)? onSeatTap; // set: seats become tappable
  // Seat-select mode: the engine has blinds posted, but this isn't a live hand
  // yet, so suppress the pot pill, bet chips, and the first-actor glow — show
  // only seats, positions, and the dealer disk.
  final bool selecting;
  const SeatRing({
    super.key,
    required this.engine,
    required this.heroSeat,
    this.anchorSeat,
    this.heroCards = const [],
    this.board = const [],
    this.shownCards = const {},
    required this.positions,
    this.onSeatTap,
    this.selecting = false,
  });

  // palette — TODO: extract to shared theme tokens (mirrors Monker Killer solver)
  static const _goldLt = Color(0xFFF0C75A);
  static const _goldMid = Color(0xFFC9A536);
  static const _goldDk = Color(0xFF5E441C);
  static const _teal = Color(0xFF10B981); // actor / EV-positive accent (emerald)
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
    final anchorIdx =
        seats.indexOf(anchorSeat ?? heroSeat ?? engine.buttonSeat);
    final actor = selecting ? null : engine.whoseTurn();
    final btnIdx = seats.indexOf(engine.buttonSeat);

    double theta(int k) => math.pi / 2 + (k - anchorIdx) * 2 * math.pi / n;

    return Center(
      child: AspectRatio(
        aspectRatio: 0.6, // long vertical racetrack (pill) — fills the portrait
        child: LayoutBuilder(builder: (ctx, c) {
          final tableW = c.maxWidth;
          final tableH = c.maxHeight;
          final seatD = (tableW * 0.10).clamp(34.0, 52.0);
          final btnTh = theta(btnIdx);
          final cx = tableW / 2, cy = tableH / 2;
          // Uniform-thickness gold rail (a pill): the felt is inset from the
          // rail by the same pixel amount on every side, so the gold ring is
          // the same width all the way round. Seats ride the rail's centre.
          final railOutW = tableW * 0.97, railOutH = tableH * 0.97;
          final railT = tableW * 0.05;
          final bandHw = railOutW / 2 - railT / 2;
          final bandHh = railOutH / 2 - railT / 2;
          final seatPts = [
            for (var k = 0; k < n; k++)
              _stadiumPoint(theta(k), cx, cy, bandHw, bandHh)
          ];
          final btnPt = _stadiumPoint(btnTh, cx, cy, bandHw, bandHh);
          // Dealer disk tucked beside the button seat: pulled onto the felt and
          // offset tangentially toward the small-blind side, so it clears both
          // the badge and the bet chips — which sit on the radial line directly
          // in front of the seat (where the disk used to collide with them).
          final btnRadial = Offset(math.cos(btnTh), math.sin(btnTh));
          final btnTangent = Offset(-btnRadial.dy, btnRadial.dx);
          final dealerPt =
              btnPt - btnRadial * (seatD * 0.30) + btnTangent * (seatD * 0.82);
          // Hole cards (hero + any shown villains) ride just inboard of their
          // seat, on the felt, so they track the player. Hero is full opacity.
          final cardLayers = <({Offset pt, List<String> cards})>[];
          void addCards(int? seat, List<String> cards) {
            if (seat == null || cards.isEmpty) return;
            final i = seats.indexOf(seat);
            if (i < 0) return;
            cardLayers.add((
              pt: Offset.lerp(seatPts[i], Offset(cx, cy), 0.30)!,
              cards: cards,
            ));
          }

          // Villain shown cards ride in front of their seats (radial, small).
          // The hero's hand is drawn separately, big and centre-low.
          for (final e in shownCards.entries) {
            addCards(e.key, e.value);
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // ---- table: a uniform-thickness gold rail (pill) wrapping the
              // felt. The felt is a uniform inset (Padding) of the rail, so the
              // gold ring is the same width all the way round; an inset inner
              // ring marks the betting line.
              Center(
                child: SizedBox(
                  width: railOutW,
                  height: railOutH,
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
                    child: Padding(
                      padding: EdgeInsets.all(railT),
                      child: Container(
                        decoration: const BoxDecoration(
                          borderRadius:
                              BorderRadius.all(Radius.circular(999)),
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 0.75,
                            colors: [_feltCtr, _feltEdge],
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(railT * 1.7),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: _goldLt.withValues(alpha: 0.22),
                                  width: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ---- felt-logo watermark in the centre, like a real table; the
              // pot and cards sit on top of it (bg is transparent)
              Align(
                alignment: const Alignment(0, -0.05),
                child: Opacity(
                  opacity: 0.30,
                  child:
                      Image.asset('assets/emblem.png', width: tableW * 0.52),
                ),
              ),
              // ---- community board across the centre of the felt
              if (board.isNotEmpty)
                Align(
                  alignment: const Alignment(0, -0.16),
                  child: _HoleCards(cards: board, cardW: seatD * 0.5),
                ),
              // ---- pot + SPR; drops below the board once one is dealt
              if (!selecting)
                Align(
                  alignment: Alignment(0, board.isEmpty ? 0 : 0.20),
                  child: _PotPill(pot: engine.pot, spr: _spr()),
                ),
              // ---- chips in front of each seat that has committed this street;
              // they animate out from the seat so the recreation is visible.
              if (!selecting)
                for (var k = 0; k < n; k++)
                  if (!engine.players[seats[k]]!.folded &&
                      engine.players[seats[k]]!.streetCommit > 0)
                  Align(
                    // Anchor off the seat's actual point (like the hole cards)
                    // so chips sit in front of each seat at any table shape.
                    alignment: Alignment((seatPts[k].dx - cx) / cx * 0.78,
                        (seatPts[k].dy - cy) / cy * 0.78),
                    child: _BetChips(
                      seat: seats[k],
                      amount: engine.players[seats[k]]!.streetCommit,
                      dirX: math.cos(theta(k)),
                      dirY: math.sin(theta(k)),
                    ),
                  ),
              // ---- dealer disk, just inside the rail in front of the button
              Positioned(
                left: dealerPt.dx - seatD * 0.21,
                top: dealerPt.dy - seatD * 0.21,
                child: _DealerDisk(d: seatD * 0.42),
              ),
              // ---- actor halo: a sonar pulse behind the seat whose turn it is,
              // so the live actor is unmistakable. Sits under the badge.
              if (actor != null)
                for (var k = 0; k < n; k++)
                  if (seats[k] == actor)
                    Positioned(
                      left: seatPts[k].dx - seatD / 2,
                      top: seatPts[k].dy - seatD / 2,
                      child: _ActorHalo(diameter: seatD, color: _teal),
                    ),
              // ---- seats, centred on the rail band
              for (var k = 0; k < n; k++)
                Positioned(
                  left: seatPts[k].dx - seatD / 2,
                  top: seatPts[k].dy - seatD / 2,
                  child: GestureDetector(
                    onTap: onSeatTap == null
                        ? null
                        : () => onSeatTap!(seats[k]),
                    child: _SeatBadge(
                      diameter: seatD,
                      player: engine.players[seats[k]]!,
                      label: positions[seats[k]] ?? '?',
                      isHero: heroSeat != null && seats[k] == heroSeat,
                      isActor: seats[k] == actor,
                    ),
                  ),
                ),
              // ---- villain shown cards on the felt in front of each revealed
              // seat (MTT showdown). Small; the hero's hand is shown separately.
              for (final cl in cardLayers)
                Align(
                  alignment:
                      Alignment((cl.pt.dx - cx) / cx, (cl.pt.dy - cy) / cy),
                  child: Opacity(
                    opacity: 0.82,
                    child: _HoleCards(cards: cl.cards, cardW: seatD * 0.42),
                  ),
                ),
              // ---- hero's four hole cards: a big, fixed display low-centre on
              // the felt — the focal point of capture. Pinned to centre so it
              // never overlaps the radial bet chips (which hug the seats), and
              // sized ~3x the old in-front-of-seat cards for at-a-glance reading.
              if (heroSeat != null && heroCards.isNotEmpty)
                Align(
                  alignment: const Alignment(0, 0.46),
                  child: _HoleCards(cards: heroCards, cardW: seatD * 1.5),
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

/// A small stack of poker chips + the amount, that slides out from the seat
/// (and re-plays whenever the seat's commitment changes) so each preflop
/// action is highly visible during capture and replay.
class _BetChips extends StatelessWidget {
  final int seat;
  final int amount;
  final double dirX, dirY; // unit vector from centre toward the seat
  const _BetChips({
    required this.seat,
    required this.amount,
    required this.dirX,
    required this.dirY,
  });

  static const _palette = [
    Color(0xFFE6E6E6),
    Color(0xFFD24B4A),
    Color(0xFF2E8B57),
    Color(0xFF3A7BD5),
    Color(0xFF26262A),
  ];

  @override
  Widget build(BuildContext context) {
    final bb = tableBigBlind == 0 ? 1 : tableBigBlind;
    final count = (amount / bb).round().clamp(1, 5);
    return TweenAnimationBuilder<double>(
      // A new key per (seat, amount) restarts the slide-in on every change.
      key: ValueKey('bc-$seat-$amount'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200), // snappier, matches solver
      curve: Curves.easeOutCubic,
      builder: (ctx, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(dirX * 24 * (1 - t), dirY * 24 * (1 - t)),
          child: child,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stack(count),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xE6121009),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: SeatRing._goldMid, width: 1),
            ),
            child: Text(fmtAmt(amount),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: SeatRing._goldLt)),
          ),
        ],
      ),
    );
  }

  Widget _stack(int count) {
    const step = 5.0;
    return SizedBox(
      width: 22,
      height: 9 + step * (count - 1),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
                bottom: i * step, child: _chip(_palette[i % _palette.length])),
        ],
      ),
    );
  }

  Widget _chip(Color c) => Container(
        width: 22,
        height: 9,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(4.5),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.82), width: 1),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 1.5, offset: Offset(0, 1)),
          ],
        ),
      );
}

/// A looping "sonar" pulse drawn behind the live actor's seat: two emerald
/// rings expand outward from the badge and fade, staggered so the pulse reads
/// as continuous. The badge itself stays a fixed size.
class _ActorHalo extends StatefulWidget {
  final double diameter;
  final Color color;
  const _ActorHalo({required this.diameter, required this.color});

  @override
  State<_ActorHalo> createState() => _ActorHaloState();
}

class _ActorHaloState extends State<_ActorHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) => SizedBox(
          width: d,
          height: d,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            // two rings half a cycle apart for a continuous ripple
            children: [
              for (final phase in const [0.0, 0.5])
                _ring((_c.value + phase) % 1.0, d),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(double t, double d) {
    final scale = 1.0 + t * 0.95; // grows out to ~1.95x the badge
    final opacity = (1.0 - t) * 0.5; // brightest at the badge edge, fades out
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.color, width: 2.4),
          ),
        ),
      ),
    );
  }
}

/// The hero's four hole cards as a compact row of card faces, laid on the felt
/// in front of the hero seat. Dark faces + 4-colour pips so they pop on green.
class _HoleCards extends StatelessWidget {
  final List<String> cards;
  final double cardW;
  const _HoleCards({required this.cards, required this.cardW});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in cards)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.1),
              width: cardW,
              height: cardW * 1.42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xF21A1E1B),
                borderRadius: BorderRadius.circular(cardW * 0.2),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.28), width: 0.6),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 2.5,
                      offset: Offset(0, 1)),
                ],
              ),
              child: Text(
                '${c[0]}${suitGlyph(c[1])}',
                style: TextStyle(
                    fontSize: cardW * 0.6,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: suitColor(c[1])),
              ),
            ),
        ],
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
