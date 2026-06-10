// Population-read export for the Monker Killer CSV bridge.
//
// Turns captured preflop hands into per-node fold/call/pot FREQUENCY tables
// that the solver side ingests via `monker_csv::load_monker_spot`. This is the
// fully-specified path from HANDOFF_import.md (§4/§5a/§6/§7). The *native*
// Monker `.rng`/`.tree` path is deferred — its node-path + `(KA)A2` formats
// aren't owned/verified yet (see §9 of the handoff).
//
// Authoritative rules mirrored here:
//  - Snap by ACTION TYPE not amount: open(1)/3bet(2)/4bet(3)/5bet-cap(4) (§4).
//  - The node = state right before the hero's first voluntary decision (§4).
//  - Refuse, don't fake: limps (no-limp trees), a 5th raise past the cap, and
//    hands outside the 100bb stack / straddle-ratio bands (§4/§7).
//  - Normalize to straddle-corrected bb; carry observed N per node (§7).
//  - Emit PHYSICAL 8-char hands (e.g. `AhAs3s2s`); the solver side does the
//    physical→canonical combo-weighted aggregation (§6).
//
// Pure Dart, no Flutter / no IO: returns a [SolverBundle] of in-memory file
// strings so the UI layer owns zipping + download, and tests stay trivial.

import '../hand_loader.dart';
import '../plo_engine.dart';

/// Why a captured hand could not be placed on a clean tree node.
enum RefusalReason {
  limp, // a voluntary call with no prior raise — our trees are no-limp
  raiseCapExceeded, // a 5th raise, past the get-in cap (level 4)
  offBandStack, // effective depth outside the accepted 100bb band
  offBandStraddle, // straddle ratio outside the accepted 2x band
  noHeroAction, // hand ended before the hero made a voluntary decision
  illegalReplay, // actions don't replay legally (corrupt/foreign capture)
}

/// Fidelity of a placed hand against the canonical 100bb / 2x-straddle target.
enum BandTier { faithful, accept }

/// The three discrete actions a node CSV is split into.
enum NodeAction { fold, call, pot }

/// One step of the preflop line leading to the node (position + snapped class).
class LineEntry {
  final String pos; // UTG, MP, CO, BTN, SB, BB, …
  final String action; // fold | call | open | 3bet | 4bet | 5bet
  const LineEntry(this.pos, this.action);
  Map<String, dynamic> toJson() => {'pos': pos, 'action': action};
  String get short => switch (action) {
        'fold' => 'F',
        'call' => 'C',
        'open' => 'O',
        '3bet' => '3B',
        '4bet' => '4B',
        '5bet' => '5B',
        _ => '?',
      };
}

/// A single hand's placement outcome — either accepted onto a node or refused.
class _Outcome {
  final RefusalReason? refusal;
  final String? nodeKey;
  final String regime;
  final List<LineEntry> line;
  final String heroPos;
  final NodeAction heroAction;
  final String heroHand; // physical 8-char key
  final BandTier tier;
  final double depthBb;
  final double? straddleRatio;
  const _Outcome.refused(this.refusal)
      : nodeKey = null,
        regime = '',
        line = const [],
        heroPos = '',
        heroAction = NodeAction.fold,
        heroHand = '',
        tier = BandTier.accept,
        depthBb = 0,
        straddleRatio = null;
  const _Outcome.accepted({
    required this.nodeKey,
    required this.regime,
    required this.line,
    required this.heroPos,
    required this.heroAction,
    required this.heroHand,
    required this.tier,
    required this.depthBb,
    required this.straddleRatio,
  }) : refusal = null;
}

/// The export result: in-memory file paths→contents plus the parsed manifest.
class SolverBundle {
  final Map<String, String> files; // relative path → file contents
  final Map<String, dynamic> manifest; // also serialized into files
  final Map<RefusalReason, int> refusals;
  final int totalHands;
  final int acceptedHands;
  const SolverBundle({
    required this.files,
    required this.manifest,
    required this.refusals,
    required this.totalHands,
    required this.acceptedHands,
  });
}

const _rankOrder = '23456789TJQKA';
const _suitOrder = 'hcds';

/// Build the population bundle from raw canonical hand-history JSON blobs.
SolverBundle exportPopulation(
  List<Map<String, dynamic>> handJsons, {
  required String capturedThrough,
}) {
  final outcomes = <_Outcome>[];
  final refusals = {for (final r in RefusalReason.values) r: 0};

  for (final j in handJsons) {
    final o = _placeHand(j);
    if (o.refusal != null) {
      refusals[o.refusal!] = refusals[o.refusal!]! + 1;
    } else {
      outcomes.add(o);
    }
  }

  // Aggregate accepted hands: node → physical hand → action counts.
  final nodes = <String, _NodeAgg>{};
  for (final o in outcomes) {
    final agg = nodes.putIfAbsent(
        o.nodeKey!,
        () => _NodeAgg(
            regime: o.regime,
            heroPos: o.heroPos,
            line: o.line,
            tier: o.tier));
    agg.add(o.heroHand, o.heroAction);
    // A node is only as faithful as its least-faithful contributing hand.
    if (o.tier == BandTier.accept) agg.tier = BandTier.accept;
    if (o.straddleRatio != null) agg.straddleRatios.add(o.straddleRatio!);
    agg.depths.add(o.depthBb);
  }

  final files = <String, String>{};
  final manifestNodes = <Map<String, dynamic>>[];
  final sortedKeys = nodes.keys.toList()..sort();
  for (final key in sortedKeys) {
    final agg = nodes[key]!;
    final dir = 'nodes/$key';
    for (final action in NodeAction.values) {
      files['$dir/${action.name}.csv'] = agg.csvFor(action);
    }
    manifestNodes.add(agg.manifestEntry(key, dir, capturedThrough));
  }

  final manifest = <String, dynamic>{
    'schema': 'plo-show-population/v0',
    'generated_for': 'monker-killer-csv-bridge',
    'captured_through': capturedThrough,
    'total_hands': handJsons.length,
    'accepted_hands': outcomes.length,
    'refusals': {
      for (final e in refusals.entries)
        if (e.value > 0) e.key.name: e.value
    },
    'node_count': sortedKeys.length,
    'nodes': manifestNodes,
  };
  files['manifest.json'] = _prettyJson(manifest);

  return SolverBundle(
    files: files,
    manifest: manifest,
    refusals: refusals,
    totalHands: handJsons.length,
    acceptedHands: outcomes.length,
  );
}

/// Replay one hand to its node and classify it, or return a refusal.
_Outcome _placeHand(Map<String, dynamic> j) {
  final LoadedHand lh;
  try {
    lh = loadHand(j);
  } catch (_) {
    return const _Outcome.refused(RefusalReason.illegalReplay);
  }
  final cfg = lh.cfg;
  final heroSeat = cfg.heroSeat;
  final bb = cfg.bigBlind;
  if (bb <= 0) return const _Outcome.refused(RefusalReason.illegalReplay);

  // Regime + straddle ratio from the forced bets.
  String regime = 'nostr';
  double? straddleRatio;
  for (final fb in cfg.forcedBets) {
    if (fb.type == PostType.straddleButton ||
        fb.type == PostType.straddleMississippi) {
      regime = 'bstr';
      straddleRatio = fb.amount / bb;
    } else if (fb.type == PostType.straddleUtg ||
        fb.type == PostType.straddleUtg2) {
      regime = 'ustr';
      straddleRatio = fb.amount / bb;
    }
  }

  // Walk actions through the real engine until the hero's first voluntary act.
  final e = cfg.buildEngine();
  final line = <LineEntry>[];
  var raiseCount = 0;
  int? heroIdx;

  for (var i = 0; i < lh.actions.length; i++) {
    final a = lh.actions[i];
    if (a.seat == heroSeat) {
      heroIdx = i;
      break;
    }
    final pos = lh.positions[a.seat] ?? 'S${a.seat}';
    switch (a.type) {
      case ActionType.fold:
        line.add(LineEntry(pos, 'fold'));
        break;
      case ActionType.check:
      case ActionType.call:
        if (raiseCount == 0) {
          return const _Outcome.refused(RefusalReason.limp);
        }
        line.add(LineEntry(pos, 'call'));
        break;
      case ActionType.bet:
      case ActionType.raise:
        raiseCount++;
        if (raiseCount > 4) {
          return const _Outcome.refused(RefusalReason.raiseCapExceeded);
        }
        line.add(LineEntry(pos, _levelName(raiseCount)));
        break;
    }
    try {
      e.apply(a.seat, a.type, amount: a.amount);
    } catch (_) {
      return const _Outcome.refused(RefusalReason.illegalReplay);
    }
  }

  if (heroIdx == null) {
    return const _Outcome.refused(RefusalReason.noHeroAction);
  }

  // Hero's action at the node, snapped to {fold, call, pot}.
  final heroA = lh.actions[heroIdx];
  final NodeAction heroAction;
  switch (heroA.type) {
    case ActionType.fold:
      heroAction = NodeAction.fold;
      break;
    case ActionType.check:
      heroAction = NodeAction.call;
      break;
    case ActionType.call:
      if (raiseCount == 0) {
        return const _Outcome.refused(RefusalReason.limp); // hero open-limps
      }
      heroAction = NodeAction.call;
      break;
    case ActionType.bet:
    case ActionType.raise:
      if (raiseCount + 1 > 4) {
        return const _Outcome.refused(RefusalReason.raiseCapExceeded);
      }
      heroAction = NodeAction.pot;
      break;
  }

  // Effective depth = min(hero, LARGEST still-in villain), on STARTING stacks,
  // straddle-corrected to bb (§7). Fold status is read at the node; a lone
  // short villain must not sink an otherwise-deep spot, so we take the largest
  // villain still in, not the smallest. Hero's stack is exact; villains' are
  // approximate, so the band-defining stack is "approx" only when a villain binds.
  final stacks = cfg.initialStacks;
  final heroStack = stacks[heroSeat] ?? e.players[heroSeat]!.stack;
  var maxVillain = -1;
  for (final p in e.players.values) {
    if (p.seat == heroSeat || p.folded) continue;
    final s = stacks[p.seat] ?? p.stack;
    if (s > maxVillain) maxVillain = s;
  }
  final int effStack;
  final bool effIsApprox;
  if (maxVillain < 0 || heroStack <= maxVillain) {
    effStack = heroStack; // hero binds (or nobody left) → exact
    effIsApprox = false;
  } else {
    effStack = maxVillain; // largest villain binds → approximate
    effIsApprox = true;
  }
  final correction = straddleRatio != null ? 2.0 / straddleRatio : 1.0;
  final depthBb = effStack / bb * correction;

  final tier = _bandCheck(depthBb, straddleRatio, effIsApprox);
  if (tier == null) {
    // Distinguish the two refusal flavours for the report.
    return _Outcome.refused(straddleRatio != null &&
            (straddleRatio < 1.75 || straddleRatio > 2.25)
        ? RefusalReason.offBandStraddle
        : RefusalReason.offBandStack);
  }

  final heroPos = lh.positions[heroSeat] ?? 'S$heroSeat';
  return _Outcome.accepted(
    nodeKey: _nodeKey(regime, line),
    regime: regime,
    line: line,
    heroPos: heroPos,
    heroAction: heroAction,
    heroHand: _physicalKey(lh.heroCards),
    tier: tier,
    depthBb: depthBb,
    straddleRatio: straddleRatio,
  );
}

String _levelName(int level) => switch (level) {
      1 => 'open',
      2 => '3bet',
      3 => '4bet',
      4 => '5bet',
      _ => 'open',
    };

/// Stack + straddle-ratio bands from §7. Returns the tier, or null to refuse.
BandTier? _bandCheck(double depthBb, double? ratio, bool approx) {
  // ±10% tightening of the refuse edges when the band-defining stack is approx.
  final lo = approx ? 60.0 * 1.1 : 60.0;
  final hi = approx ? 140.0 * 0.9 : 140.0;
  if (depthBb < lo || depthBb > hi) return null;
  if (ratio != null && (ratio < 1.75 || ratio > 2.25)) return null;

  final stackFaithful = depthBb >= 85.0 && depthBb <= 115.0;
  final strFaithful = ratio == null || (ratio >= 1.90 && ratio <= 2.10);
  return (stackFaithful && strFaithful) ? BandTier.faithful : BandTier.accept;
}

/// Filesystem-safe, stable node id: `{regime}__{pos.short_…}` (or `__root`).
String _nodeKey(String regime, List<LineEntry> line) {
  if (line.isEmpty) return '${regime}__root';
  return '${regime}__${line.map((l) => '${l.pos}.${l.short}').join('_')}';
}

/// Canonical physical hand string, e.g. `AhAs3s2s` (rank-desc, suit h<c<d<s).
String _physicalKey(List<String> cards) {
  final parsed = cards.map((c) {
    final r = c.length >= 3 ? c.substring(0, c.length - 1) : c[0];
    final s = c[c.length - 1].toLowerCase();
    final rank = r == '10' ? 'T' : r.toUpperCase();
    return (rank: rank, suit: s);
  }).toList();
  parsed.sort((a, b) {
    final rc = _rankOrder.indexOf(b.rank) - _rankOrder.indexOf(a.rank);
    if (rc != 0) return rc;
    return _suitOrder.indexOf(a.suit) - _suitOrder.indexOf(b.suit);
  });
  return parsed.map((c) => '${c.rank}${c.suit}').join();
}

/// Per-node aggregation of observed hero hands → action frequencies.
class _NodeAgg {
  final String regime;
  final String heroPos;
  final List<LineEntry> line;
  BandTier tier;
  final Map<String, Map<NodeAction, int>> counts = {}; // hand → action → n
  final List<double> depths = [];
  final List<double> straddleRatios = [];

  _NodeAgg(
      {required this.regime,
      required this.heroPos,
      required this.line,
      required this.tier});

  void add(String hand, NodeAction action) {
    final m = counts.putIfAbsent(hand, () => {});
    m[action] = (m[action] ?? 0) + 1;
  }

  int get nHands =>
      counts.values.fold(0, (s, m) => s + m.values.fold(0, (a, b) => a + b));

  String csvFor(NodeAction action) {
    final rows = <String>['HAND,FREQ,EV'];
    final hands = counts.keys.toList()..sort();
    for (final h in hands) {
      final m = counts[h]!;
      final total = m.values.fold(0, (a, b) => a + b);
      final n = m[action] ?? 0;
      if (n == 0) continue;
      final freq = n / total;
      rows.add('$h,${_freq(freq)},0');
    }
    return '${rows.join('\n')}\n';
  }

  Map<String, dynamic> manifestEntry(
      String key, String dir, String capturedThrough) {
    return {
      'node_id': key,
      'dir': dir,
      'regime': regime,
      'hero_pos': heroPos,
      'action_line': line.map((l) => l.toJson()).toList(),
      'n_hands': nHands,
      'depth_band': tier.name,
      'depth_bb_mean': depths.isEmpty
          ? null
          : double.parse(
              (depths.reduce((a, b) => a + b) / depths.length)
                  .toStringAsFixed(1)),
      'straddle_ratio': straddleRatios.isEmpty
          ? null
          : double.parse(
              (straddleRatios.reduce((a, b) => a + b) / straddleRatios.length)
                  .toStringAsFixed(2)),
      'source': 'population_observed',
      'captured_through': capturedThrough,
    };
  }
}

/// Trim a frequency to 4 dp without a trailing `.0` noise tail.
String _freq(double f) {
  if (f == 1.0) return '1.0';
  if (f == 0.0) return '0.0';
  var s = f.toStringAsFixed(4);
  s = s.replaceAll(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s += '0';
  return s;
}

String _prettyJson(Object? o, [String indent = '']) {
  final next = '$indent  ';
  if (o is Map) {
    if (o.isEmpty) return '{}';
    final entries = o.entries
        .map((e) => '$next${_jsonStr(e.key.toString())}: '
            '${_prettyJson(e.value, next)}')
        .join(',\n');
    return '{\n$entries\n$indent}';
  }
  if (o is List) {
    if (o.isEmpty) return '[]';
    final items = o.map((e) => '$next${_prettyJson(e, next)}').join(',\n');
    return '[\n$items\n$indent]';
  }
  if (o is String) return _jsonStr(o);
  if (o == null) return 'null';
  return o.toString();
}

String _jsonStr(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
