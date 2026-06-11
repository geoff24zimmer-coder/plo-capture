import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../plo_engine.dart';
import '../hand_recorder.dart';
import '../util.dart';
import '../models/session.dart';
import '../db/hand_store.dart';
import '../widgets/seat_ring.dart';
import '../widgets/action_bar.dart';
import '../widgets/card_picker.dart';

enum _Phase { setup, seats, acting, result }

enum _StraddleChoice { none, utg, button }

class CaptureScreen extends StatefulWidget {
  final Session session;
  const CaptureScreen({super.key, required this.session});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  static String _asDollars(int cents) =>
      cents % 100 == 0 ? '${cents ~/ 100}' : (cents / 100).toStringAsFixed(2);

  bool get _isMtt => widget.session.isMtt;

  // ---- setup state (prefilled from the session; MTT amounts are chips)
  late final _sbCtrl = TextEditingController(
      text: _isMtt ? '100' : _asDollars(widget.session.smallBlind));
  late final _bbCtrl = TextEditingController(
      text: _isMtt ? '200' : _asDollars(widget.session.bigBlind));
  late final _stackCtrl = TextEditingController(
      text: _isMtt
          ? '20000'
          : _asDollars(widget.session.bigBlind * 100)); // 100bb default
  late final _anteCtrl = TextEditingController(text: _isMtt ? '200' : '0');
  final _levelCtrl = TextEditingController(text: '1');
  final _playersCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    chipMode = _isMtt;
  }
  late int _nPlayers = widget.session.maxSeats;
  int _buttonSeat = 1; // chosen by tapping the ring on the seat-select step
  static const int _heroSeat = 1; // hero is always "you", anchored bottom
  _StraddleChoice _straddle = _StraddleChoice.none;
  bool _markedForReview = false;

  // ---- live hand state
  _Phase _phase = _Phase.setup;
  HandConfig? _cfg;
  HandEngine? _engine;
  Map<int, String> _positions = {};
  List<String> _heroCards = [];
  int? _winnerSeat; // only set when the hand is won preflop by folds
  DateTime? _dealTime;
  final List<({int seat, ActionType type, int? amount})> _applied = [];

  // ------------------------------------------------------------- helpers

  /// Cash: dollars text -> cents. MTT: chips text -> chips.
  int _amount(TextEditingController c, int fallback) => _isMtt
      ? (int.tryParse(c.text) ?? fallback)
      : ((double.tryParse(c.text) ?? fallback) * 100).round();

  List<int> _seatsAfter(int seat, List<int> seats) {
    final i = seats.indexOf(seat);
    return [...seats.sublist(i + 1), ...seats.sublist(0, i)];
  }

  // ------------------------------------------------------------- actions

  /// Build the hand config from the current form + chosen button. Used both to
  /// render the live seat-select preview and to start the hand on deal.
  HandConfig _buildConfig() {
    final sb = _amount(_sbCtrl, _isMtt ? 100 : 2);
    final bb = _amount(_bbCtrl, _isMtt ? 200 : 5);
    final stack = _amount(_stackCtrl, _isMtt ? 20000 : 500);
    final ante = _isMtt ? _amount(_anteCtrl, 0) : 0;
    final seats = List.generate(_nPlayers, (i) => i + 1);
    final after = _seatsAfter(_buttonSeat, seats);
    final sbSeat = _nPlayers == 2 ? _buttonSeat : after[0];
    final bbSeat = _nPlayers == 2 ? after[0] : after[1];

    final forced = <ForcedBet>[
      ForcedBet(sbSeat, PostType.sb, sb),
      ForcedBet(bbSeat, PostType.bb, bb),
      if (ante > 0) ForcedBet(bbSeat, PostType.ante, ante, isLive: false),
      // UTG straddle needs a real UTG seat distinct from SB/BB, i.e. >= 4
      // players; at 3-handed the button IS UTG, so this would index past
      // `after` (length n-1). Button straddle covers the 3-handed case.
      if (_straddle == _StraddleChoice.utg && _nPlayers > 3)
        ForcedBet(after[2], PostType.straddleUtg, bb * 2),
      if (_straddle == _StraddleChoice.button && _nPlayers > 2)
        ForcedBet(_buttonSeat, PostType.straddleButton, bb * 2),
    ];

    return HandConfig(
      initialStacks: {for (final s in seats) s: stack},
      buttonSeat: _buttonSeat,
      smallBlind: sb,
      bigBlind: bb,
      forcedBets: forced,
      // A button straddle always plays SB-first (SB opens, straddler acts last).
      // That's the only house rule in these games, so it's not a user choice.
      straddleRule: StraddleActionRule.sbFirst,
      heroSeat: _heroSeat,
      gameType: widget.session.gameType,
      mttLevel: _isMtt
          ? MttLevel(
              levelNumber: int.tryParse(_levelCtrl.text) ?? 1,
              sb: sb,
              bb: bb,
              ante: ante,
            )
          : null,
      playersRemaining: _isMtt ? int.tryParse(_playersCtrl.text) : null,
    );
  }

  /// Move from the form to the visual seat-select step.
  void _continueToSeats() {
    if (_buttonSeat > _nPlayers) _buttonSeat = 1;
    setState(() {
      tableBigBlind = _amount(_bbCtrl, _isMtt ? 200 : 5);
      _phase = _Phase.seats;
    });
  }

  /// Seat-select model: the hero is fixed at the bottom and the user states
  /// THEIR OWN position. Positions are a pure rotation of the button, so we
  /// realise a hero position by moving the button under the hood — the dealer
  /// puck hops around the ring while "you" stay put.

  /// Step the hero's position one notch (BTN→SB→BB→… for dir=+1).
  void _cycleHero(int dir) {
    final seats = List.generate(_nPlayers, (i) => i + 1);
    final bi = seats.indexOf(_buttonSeat);
    final nbi = ((bi - dir) % _nPlayers + _nPlayers) % _nPlayers;
    HapticFeedback.selectionClick();
    setState(() => _buttonSeat = seats[nbi]);
  }

  /// Adopt the tapped seat's current position as the hero's — "I'm sitting in
  /// that spot." Tapping your own (bottom) seat is a no-op.
  void _sitAt(int tappedSeat) {
    final seats = List.generate(_nPlayers, (i) => i + 1);
    final heroIdx = seats.indexOf(_heroSeat);
    final tappedIdx = seats.indexOf(tappedSeat);
    final btnIdx = seats.indexOf(_buttonSeat);
    final n = _nPlayers;
    final newBtnIdx = ((heroIdx - tappedIdx + btnIdx) % n + n) % n;
    if (newBtnIdx == btnIdx) return;
    HapticFeedback.selectionClick();
    setState(() => _buttonSeat = seats[newBtnIdx]);
  }

  Future<void> _deal() async {
    final cfg = _buildConfig();
    final cards = await pickCards(context,
        count: 4, excluded: {}, title: 'Hero cards');
    if (cards == null) return;
    final seats = List.generate(_nPlayers, (i) => i + 1);
    setState(() {
      tableBigBlind = cfg.bigBlind; // for BB display + SPR on the table
      _cfg = cfg;
      _engine = cfg.buildEngine();
      _positions = positionNames(seats, _buttonSeat);
      _heroCards = cards;
      _winnerSeat = null;
      _markedForReview = false;
      _applied.clear();
      _dealTime = DateTime.now();
      _phase = _Phase.acting;
    });
  }

  Future<void> _onAction(ActionType type, {int? amount}) async {
    final e = _engine!;
    final seat = e.whoseTurn();
    if (seat == null) return;
    try {
      e.apply(seat, type, amount: amount);
      _applied.add((seat: seat, type: type, amount: amount));
      HapticFeedback.lightImpact();
    } on EngineException catch (ex) {
      _toast(ex.message);
      return;
    }
    setState(() {});
    _checkPreflopOver();
  }

  /// Preflop-only capture: end the hand the moment the preflop round closes —
  /// either it's decided here (everyone folds, or an all-in runs it out) or the
  /// betting would move to a flop. No board, no showdown is captured.
  /// A winner is recorded only when the hand is won outright by folds.
  void _checkPreflopOver() {
    final e = _engine!;
    final preflopOver =
        e.status != HandStatus.acting || e.street != Street.preflop;
    if (!preflopOver) return;
    setState(() {
      _phase = _Phase.result;
      _winnerSeat =
          e.status == HandStatus.wonByFold ? e.activeSeats.first : null;
    });
  }

  /// Deterministic undo: rebuild the engine and replay all but the last
  /// action. Cheap (a hand is <50 events) and impossible to desync.
  void _undo() {
    if (_applied.isEmpty) return;
    _applied.removeLast();
    final e = _cfg!.buildEngine();
    for (final a in _applied) {
      e.apply(a.seat, a.type, amount: a.amount);
    }
    setState(() {
      _engine = e;
      _winnerSeat = null;
      // Removing one action always reopens preflop action.
      _phase = _Phase.acting;
    });
  }

  Map<String, dynamic> _buildJson({bool complete = true}) => buildHandJson(
        engine: _engine!,
        cfg: _cfg!,
        positions: _positions,
        heroCards: _heroCards,
        flop: const [], // preflop-only: no board captured
        turnCard: null,
        riverCard: null,
        winnerSeat: _winnerSeat,
        sessionId: widget.session.id,
        markedForReview: _markedForReview,
        complete: complete,
        captureSeconds: _dealTime == null
            ? null
            : DateTime.now().difference(_dealTime!).inMilliseconds / 1000.0,
      );

  Future<void> _saveHand() async {
    await HandStore.instance.insertHand(_buildJson());
    if (!mounted) return;
    _toast('Hand saved');
    setState(() => _phase = _Phase.setup); // ready for the next one
  }

  /// True while the hand is live AND the action has reached the hero — either
  /// it's the hero's turn now, or the hero has already acted. Lets the user
  /// bank a decision spot without playing the orbit out behind them.
  bool get _canSaveSpot {
    final e = _engine;
    if (e == null || e.status != HandStatus.acting) return false;
    final hero = _cfg!.heroSeat;
    return e.whoseTurn() == hero || _applied.any((a) => a.seat == hero);
  }

  /// Save the hand as-is, mid-action. Partial info is first-class: no winner,
  /// just the action up to this point and the hero's spot.
  Future<void> _saveSpot() async {
    await HandStore.instance.insertHand(_buildJson(complete: false));
    if (!mounted) return;
    _toast('Spot saved');
    setState(() => _phase = _Phase.setup);
  }

  /// Copy the record JSON to the clipboard. `complete: false` copies a decision
  /// spot (meta.complete=false) — the record Monker Killer's IMPORT HAND review
  /// flow wants. A spot has no hero action, which the review importer handles
  /// (the population export would refuse it as noHeroAction).
  void _copyJson({bool complete = true}) {
    final pretty =
        const JsonEncoder.withIndent('  ').convert(_buildJson(complete: complete));
    Clipboard.setData(ClipboardData(text: pretty));
    _toast(complete
        ? 'JSON copied to clipboard'
        : 'Spot JSON copied — paste into a .plohand.json for Import Hand');
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _phase == _Phase.seats
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _phase = _Phase.setup),
              )
            : null,
        title: Text(switch (_phase) {
          _Phase.setup => 'New hand',
          _Phase.seats => 'Where are you sitting?',
          _ => '${widget.session.stakesLabel} · ${_nPlayers}-max',
        }),
        actions: [
          if (_phase == _Phase.acting || _phase == _Phase.result) ...[
            TextButton(
              onPressed: () => setState(() => tableUnit =
                  tableUnit == TableUnit.money ? TableUnit.bb : TableUnit.money),
              child: Text(tableUnitLabel,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Undo last action',
              icon: const Icon(Icons.undo),
              onPressed: _applied.isEmpty ? null : _undo,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.setup => _buildSetup(),
          _Phase.seats => _buildSeatSelect(),
          _ => _buildTable(),
        },
      ),
    );
  }

  Widget _buildSetup() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _sbCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: _isMtt ? 'SB (chips)' : 'SB \$'))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: _bbCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: _isMtt ? 'BB (chips)' : 'BB \$'))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: _stackCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: _isMtt ? 'Stacks (chips)' : 'Stacks \$'))),
        ]),
        if (_isMtt) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _levelCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Level'))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: _anteCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'BB ante'))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: _playersCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Players left'))),
          ]),
        ],
        const SizedBox(height: 16),
        Text('Players: $_nPlayers'),
        Slider(
          min: 2,
          max: 10,
          divisions: 8,
          value: _nPlayers.toDouble(),
          label: '$_nPlayers',
          onChanged: (v) => setState(() {
            _nPlayers = v.round();
            if (_buttonSeat > _nPlayers) _buttonSeat = 1;
            // UTG straddle is meaningless below 4-handed; drop a stale pick.
            if (_nPlayers < 4 && _straddle == _StraddleChoice.utg) {
              _straddle = _StraddleChoice.none;
            }
          }),
        ),
        const SizedBox(height: 16),
        if (!_isMtt)
        Wrap(spacing: 8, children: [
          for (final (c, label) in [
            (_StraddleChoice.none, 'No straddle'),
            (_StraddleChoice.utg, 'UTG straddle'),
            (_StraddleChoice.button, 'Button straddle'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _straddle == c,
              onSelected: (_) => setState(() => _straddle = c),
            ),
        ]),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _continueToSeats,
          child: const Text('Continue', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  /// Visual seat selection: tap the seat with the dealer button; the hero
  /// (always you, anchored at the bottom) picks up the derived position.
  Widget _buildSeatSelect() {
    final seats = List.generate(_nPlayers, (i) => i + 1);
    final cfg = _buildConfig();
    final positions = positionNames(seats, _buttonSeat);
    final heroPos = positions[_heroSeat] ?? '?';
    return Column(
      children: [
        Expanded(
          child: SeatRing(
            engine: cfg.buildEngine(),
            heroSeat: _heroSeat,
            positions: positions,
            selecting: true,
            onSeatTap: _sitAt,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tap the seat you’re in, or step with the arrows',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.6))),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _posChevron(Icons.chevron_left, () => _cycleHero(-1)),
                  const SizedBox(width: 14),
                  Container(
                    constraints: const BoxConstraints(minWidth: 138),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFC9A536), width: 1.4),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('YOU’RE IN',
                            style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700,
                                color: Colors.white54)),
                        Text(heroPos,
                            style: const TextStyle(
                                fontSize: 26,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFF0C75A))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _posChevron(Icons.chevron_right, () => _cycleHero(1)),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _deal,
                  child:
                      const Text('Deal hand', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Round tappable chevron for the position stepper.
  Widget _posChevron(IconData icon, VoidCallback onTap) => Material(
        color: const Color(0xFF1E2421),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 28, color: const Color(0xFFF0C75A)),
          ),
        ),
      );

  Widget _buildTable() {
    final e = _engine!;
    return Column(
      children: [
        Expanded(
          child: SeatRing(
              engine: e, heroSeat: _cfg!.heroSeat, positions: _positions),
        ),
        const SizedBox(height: 6),
        _heroCardsRow(),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _phase == _Phase.result
              ? _resultPanel()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_canSaveSpot) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saveSpot,
                          icon: const Icon(Icons.bookmark_add_outlined,
                              size: 18),
                          label: Text(
                              _engine!.whoseTurn() == _cfg!.heroSeat
                                  ? 'Save spot — your decision'
                                  : 'Save spot here'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF0C75A),
                            side: const BorderSide(color: Color(0xFFC9A536)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      // Export this decision spot for review (Monker Killer
                      // IMPORT HAND). Copies the raw complete:false record; the
                      // review importer treats the hero's action as optional.
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => _copyJson(complete: false),
                          icon: const Icon(Icons.content_copy, size: 16),
                          label: const Text('Copy spot JSON (for Import Hand)'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _actionPanel(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _actionPanel() {
    final e = _engine!;
    if (e.whoseTurn() == null) return const SizedBox.shrink();
    return ActionBar(
      la: e.legalActions(),
      onAction: _onAction,
      isMtt: _isMtt,
      currentBet: e.currentBet,
    );
  }

  Widget _resultPanel() {
    final e = _engine!;
    final wonByFold = e.status == HandStatus.wonByFold;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            wonByFold
                ? '${_positions[_winnerSeat]} wins ${money(e.pot)} uncontested'
                : 'Preflop captured · pot ${money(e.pot)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Flag for review'),
              avatar: const Icon(Icons.flag, size: 16),
              selected: _markedForReview,
              onSelected: (v) => setState(() => _markedForReview = v),
            ),
            const Spacer(),
            TextButton(onPressed: _copyJson, child: const Text('Copy JSON')),
          ],
        ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _saveHand,
          child: const Text('Save hand'),
        ),
      ],
    );
  }

  Widget _heroCardsRow() => SizedBox(height: 40, child: _cardStrip(_heroCards, size: 18));

  Widget _cardStrip(List<String> cards, {required double size}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final c in cards)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.5),
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
    );
  }

  @override
  void dispose() {
    _sbCtrl.dispose();
    _bbCtrl.dispose();
    _stackCtrl.dispose();
    _anteCtrl.dispose();
    _levelCtrl.dispose();
    _playersCtrl.dispose();
    super.dispose();
  }
}
