import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../hand_loader.dart';
import '../plo_engine.dart';
import '../util.dart';
import '../widgets/seat_ring.dart';
import '../widgets/card_picker.dart' show suitColor, suitGlyph;

/// Step through a stored hand action-by-action. Each step rebuilds the
/// engine from the start — every frame is a node in the hand's game tree,
/// guaranteed consistent with capture because it's the same state machine.
class ReplayerScreen extends StatefulWidget {
  final String handId;
  const ReplayerScreen({super.key, required this.handId});
  @override
  State<ReplayerScreen> createState() => _ReplayerScreenState();
}

class _ReplayerScreenState extends State<ReplayerScreen> {
  LoadedHand? _hand;
  HandEngine? _engine;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    HandStore.instance.getHand(widget.handId).then((json) {
      final loaded = loadHand(json);
      chipMode = json['session']?['game_type'] == 'mtt';
      setState(() {
        _hand = loaded;
        _step = 0;
        _engine = loaded.engineAtStep(0);
      });
    });
  }

  void _goTo(int step) {
    final h = _hand!;
    final s = step.clamp(0, h.actions.length);
    setState(() {
      _step = s;
      _engine = h.engineAtStep(s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = _hand;
    final e = _engine;
    if (h == null || e == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final reached =
        e.status == HandStatus.showdown ? 3 : e.street.index;
    final shownBoard = <String>[
      if (reached >= 1) ...h.flop,
      if (reached >= 2 && h.turnCard != null) h.turnCard!,
      if (reached >= 3 && h.riverCard != null) h.riverCard!,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Replay')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SeatRing(
                  engine: e,
                  heroSeat: h.cfg.heroSeat,
                  positions: h.positions),
            ),
            _cardStrip(shownBoard, height: 34, size: 15),
            const SizedBox(height: 4),
            _cardStrip(h.heroCards, height: 40, size: 18),
            const SizedBox(height: 6),
            SizedBox(
              height: 24,
              child: Text(
                _caption(h, e),
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withValues(alpha: 0.75)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  IconButton(
                      onPressed: _step == 0 ? null : () => _goTo(0),
                      icon: const Icon(Icons.first_page)),
                  IconButton(
                      onPressed: _step == 0 ? null : () => _goTo(_step - 1),
                      icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: h.actions.length.toDouble(),
                      divisions:
                          h.actions.isEmpty ? 1 : h.actions.length,
                      value: _step.toDouble(),
                      label: '$_step',
                      onChanged: (v) => _goTo(v.round()),
                    ),
                  ),
                  IconButton(
                      onPressed: _step >= h.actions.length
                          ? null
                          : () => _goTo(_step + 1),
                      icon: const Icon(Icons.chevron_right)),
                  IconButton(
                      onPressed: _step >= h.actions.length
                          ? null
                          : () => _goTo(h.actions.length),
                      icon: const Icon(Icons.last_page)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _caption(LoadedHand h, HandEngine e) {
    if (_step == 0) return 'Cards are dealt';
    final a = e.log.last;
    final pos = h.positions[a.seat] ?? 'Seat ${a.seat}';
    final desc = switch (a.action) {
      ActionType.fold => '$pos folds',
      ActionType.check => '$pos checks',
      ActionType.call => '$pos calls ${money(a.amountToCall)}',
      ActionType.bet => '$pos bets ${money(a.amount!)}',
      ActionType.raise => '$pos raises to ${money(a.amount!)}',
    };
    final allIn = a.isAllIn ? ' (all-in)' : '';
    if (_step == h.actions.length && h.winnerSeat != null) {
      final w = h.positions[h.winnerSeat] ?? 'Seat ${h.winnerSeat}';
      return '$desc$allIn — $w wins ${money(e.pot)}';
    }
    return '$desc$allIn';
  }

  Widget _cardStrip(List<String> cards,
      {required double height, required double size}) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final c in cards)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18), width: 0.5),
              ),
              child: Text(
                '${c[0]}${suitGlyph(c[1])}',
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w600,
                    color: suitColor(c[1])),
              ),
            ),
        ],
      ),
    );
  }
}
