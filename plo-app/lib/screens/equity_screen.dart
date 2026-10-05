import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../equity/equity.dart';
import '../equity/evaluator.dart';
import '../widgets/card_picker.dart';

const _gold = Color(0xFFF0C75A);
const _accent = Color(0xFF10B981);
const _maxPlayers = 6;

/// Monte Carlo deals per calculation (±~0.15% on a heads-up equity).
const _mcSamples = 100000;

const _categoryNames = {
  HandCategory.highCard: 'High card',
  HandCategory.pair: 'Pair',
  HandCategory.twoPair: 'Two pair',
  HandCategory.trips: 'Three of a kind',
  HandCategory.straight: 'Straight',
  HandCategory.flush: 'Flush',
  HandCategory.fullHouse: 'Full house',
  HandCategory.quads: 'Quads',
  HandCategory.straightFlush: 'Straight flush',
};

/// 4- and 5-card Omaha equity calculator. Recalculates on every change, in
/// short time slices so the UI never stalls: exact on the flop/turn/river,
/// simulated preflop or whenever a hand is left random.
class EquityScreen extends StatefulWidget {
  const EquityScreen({super.key});
  @override
  State<EquityScreen> createState() => _EquityScreenState();
}

class _EquityScreenState extends State<EquityScreen> {
  int _holeSize = 4;
  final List<List<String>> _hands = [[], []];
  List<String> _board = [];

  EquityResult? _result;
  String? _error;
  int _total = 0; // exact runouts, or the MC target
  int _gen = 0; // bumps on every input change; stale runs stop

  Set<String> get _used => {..._hands.expand((h) => h), ..._board};

  @override
  void dispose() {
    _gen++;
    super.dispose();
  }

  void _changed() {
    setState(() {});
    _recalculate();
  }

  Future<void> _recalculate() async {
    final gen = ++_gen;
    final EquityCalc calc;
    try {
      calc = EquityCalc(
        hands: [for (final h in _hands) h.map(parseCard).toList()],
        board: _board.map(parseCard).toList(),
        holeSize: _holeSize,
      );
    } on ArgumentError catch (e) {
      setState(() {
        _error = '${e.message}';
        _result = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _result = null;
      _total = calc.exact ? calc.total : _mcSamples;
    });
    final sw = Stopwatch();
    while (gen == _gen && calc.done < _total) {
      sw
        ..reset()
        ..start();
      // ~12ms of work, then yield a frame.
      while (sw.elapsedMilliseconds < 12 && calc.done < _total) {
        calc.run(math.min(256, _total - calc.done));
      }
      if (gen != _gen || !mounted) return;
      setState(() => _result = calc.result);
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _pickHand(int i) async {
    final picked = await pickCards(
      context,
      count: _holeSize,
      excluded: _used.difference(_hands[i].toSet()),
      title: 'Player ${i + 1}',
    );
    if (picked == null) return;
    _hands[i] = picked;
    _changed();
  }

  Future<void> _pickBoard() async {
    final n = _board.isEmpty ? 3 : (_board.length < 5 ? 1 : 0);
    if (n == 0) return;
    final picked = await pickCards(
      context,
      count: n,
      excluded: _used,
      title: n == 3 ? 'Flop' : (_board.length == 3 ? 'Turn' : 'River'),
    );
    if (picked == null) return;
    _board = [..._board, ...picked];
    _changed();
  }

  void _setGame(int size) {
    _holeSize = size;
    // Going 5→4 keeps the first four cards; 4→5 leaves the 5th random.
    for (var i = 0; i < _hands.length; i++) {
      if (_hands[i].length > size) _hands[i] = _hands[i].sublist(0, size);
    }
    _changed();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recalculate());
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equity'),
        actions: [
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.restart_alt),
            onPressed: () {
              for (var i = 0; i < _hands.length; i++) {
                _hands[i] = [];
              }
              _board = [];
              _changed();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('PLO')),
              ButtonSegment(value: 5, label: Text('PLO5')),
            ],
            selected: {_holeSize},
            onSelectionChanged: (v) => _setGame(v.first),
          ),
          const SizedBox(height: 14),
          _boardRow(),
          const SizedBox(height: 10),
          for (var i = 0; i < _hands.length; i++) _playerRow(i, r),
          if (_hands.length < _maxPlayers)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  _hands.add([]);
                  _changed();
                },
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add player'),
              ),
            ),
          const SizedBox(height: 6),
          _status(r),
        ],
      ),
    );
  }

  Widget _boardRow() {
    final full = _board.length == 5;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F3B2C).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFC9A536).withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const SizedBox(
          width: 52,
          child: Text('BOARD',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: _gold)),
        ),
        Expanded(
          child: InkWell(
            onTap: full ? null : _pickBoard,
            borderRadius: BorderRadius.circular(8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: i < _board.length
                        ? CardFace(_board[i], width: 40)
                        : _EmptySlot(
                            width: 40,
                            label: i == _board.length
                                ? (i == 0
                                    ? 'Flop'
                                    : (i == 3 ? 'Turn' : 'River'))
                                : ''),
                  ),
              ]),
            ),
          ),
        ),
        if (_board.isNotEmpty)
          IconButton(
            tooltip: 'Clear board',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              _board = [];
              _changed();
            },
          ),
      ]),
    );
  }

  Widget _playerRow(int i, EquityResult? r) {
    final hand = _hands[i];
    final eq = r == null || i >= r.equity.length ? null : r.equity[i];
    String? made;
    if (_board.length == 5 && hand.length == _holeSize) {
      made = _categoryNames[categoryOf(OmahaEvaluator.instance
          .best(hand.map(parseCard).toList(), _board.map(parseCard).toList()))];
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              SizedBox(
                width: 36,
                child: Text('P${i + 1}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _pickHand(i),
                  borderRadius: BorderRadius.circular(8),
                  // Scales the strip down on narrow phones (PLO5 is wide).
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(children: [
                      for (var k = 0; k < _holeSize; k++)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: k < hand.length
                              ? CardFace(hand[k], width: 34)
                              : _EmptySlot(
                                  width: 34,
                                  label: hand.isEmpty && k == 0 ? 'Any' : '?'),
                        ),
                    ]),
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  eq == null ? '—' : '${(eq * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Player ${i + 1}',
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) {
                  if (v == 'clear') _hands[i] = [];
                  if (v == 'remove') _hands.removeAt(i);
                  _changed();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'clear', child: Text('Random hand')),
                  if (_hands.length > 2)
                    const PopupMenuItem(
                        value: 'remove', child: Text('Remove player')),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: eq ?? 0,
                      minHeight: 6,
                      color: _accent,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  [
                    if (made != null) made,
                    if (r != null && i < r.win.length)
                      'win ${(r.win[i] * 100).toStringAsFixed(1)}%'
                          '${r.tie[i] > 0.0005 ? ' · tie ${(r.tie[i] * 100).toStringAsFixed(1)}%' : ''}',
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.55)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(EquityResult? r) {
    final muted =
        TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55));
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Color(0xFFE24B4A)));
    }
    if (r == null) return Text('Calculating…', style: muted);
    final running = r.trials < _total;
    final String what;
    if (r.exact) {
      what = 'Exact · ${_group(r.trials)} of ${_group(_total)} runouts';
    } else {
      final se = r.stdError.reduce((a, b) => a > b ? a : b);
      what = 'Simulated · ${_group(r.trials)} deals · ±'
          '${(1.96 * se * 100).toStringAsFixed(1)}%';
    }
    return Row(children: [
      if (running)
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      Expanded(child: Text(what, style: muted)),
    ]);
  }

  static String _group(int v) => v
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

class _EmptySlot extends StatelessWidget {
  final double width;
  final String label;
  const _EmptySlot({required this.width, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width * 1.42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.2),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          color: Colors.white.withValues(alpha: 0.03),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.45))),
          ),
        ),
      );
}
