/// All-in EV for captured hands: what hero's result "should" have been, given
/// the equity when the money went in, versus what the board actually gave.
/// Pure Dart. Built on the engine replay (deterministic, like undo/replayer)
/// and the equity engine; side pots are scored pot by pot.
///
/// Partial information stays partial: if a contesting villain's cards weren't
/// recorded, there's no EV — we say so rather than guess.
library;

import 'dart:math' as math;

import '../hand_loader.dart';
import '../plo_engine.dart';
import 'equity.dart';
import 'evaluator.dart';

enum AllInStatus {
  /// EV computed.
  ok,

  /// No all-in before the river, or the hand didn't reach showdown.
  notAllIn,

  /// Hero folded or wasn't in the pot at the end.
  heroNotInPot,

  /// A contesting villain's hole cards (or the board at the all-in) weren't
  /// recorded.
  missingCards,
}

class AllInEv {
  final AllInStatus status;

  /// Street the last action happened on (money all in), when [status] is ok.
  final Street? street;

  /// Number of actions in the hand (the replay step where it's all in).
  final int step;

  /// Main-pot equity per contesting seat, 0..1.
  final Map<int, double> equity;

  /// Hero's expected net from the all-in point, smallest unit.
  final int? heroEv;

  /// Hero's recorded net (results.hero_net), when known.
  final int? heroActual;
  final bool exact;

  const AllInEv._(this.status,
      {this.street,
      this.step = 0,
      this.equity = const {},
      this.heroEv,
      this.heroActual,
      this.exact = false});

  const AllInEv.none(AllInStatus status) : this._(status);

  bool get ok => status == AllInStatus.ok;

  /// Actual − expected: positive = ran above EV.
  int? get luck =>
      heroEv == null || heroActual == null ? null : heroActual! - heroEv!;
}

/// Monte Carlo deals for a preflop all-in (±~0.7% on a single hand at 95% —
/// fine for a per-hand readout, and the noise averages out across hands).
const allInSamples = 20000;

AllInEv computeAllInEv(LoadedHand h, {int samples = allInSamples}) {
  final e = h.engineAtStep(h.actions.length);
  if (e.status != HandStatus.showdown || e.log.isEmpty) {
    return const AllInEv.none(AllInStatus.notAllIn);
  }
  final street = e.log.last.street;
  if (street == Street.river) return const AllInEv.none(AllInStatus.notAllIn);

  final hero = h.cfg.heroSeat;
  final live = e.activeSeats;
  if (!live.contains(hero)) return const AllInEv.none(AllInStatus.heroNotInPot);

  final cards = <int, List<int>>{};
  try {
    for (final s in live) {
      final raw = s == hero ? h.heroCards : h.shownCards[s];
      if (raw == null || raw.length != 4) {
        return const AllInEv.none(AllInStatus.missingCards);
      }
      cards[s] = raw.map(parseCard).toList();
    }
  } on FormatException {
    return const AllInEv.none(AllInStatus.missingCards);
  }
  final board = <String>[
    if (street.index >= Street.flop.index) ...h.flop,
    if (street.index >= Street.turn.index && h.turnCard != null) h.turnCard!,
  ];
  if (board.length != (street == Street.preflop ? 0 : street.index + 2)) {
    return const AllInEv.none(AllInStatus.missingCards);
  }
  final boardInts = board.map(parseCard).toList();

  // Deterministic per hand, so the number doesn't wobble between views.
  final seed = (h.raw['hand_id'] as String? ?? '').hashCode;
  final rng = math.Random(seed);

  final breakdown = e.computePots();
  final rake = (h.raw['results'] as Map?)?['rake'] as int? ?? 0;
  var expected = 0.0;
  var mainEquity = <int, double>{};
  var exact = true;
  for (var i = 0; i < breakdown.pots.length; i++) {
    final pot = breakdown.pots[i];
    final amount = i == 0 ? pot.amount - rake : pot.amount;
    final contest = pot.eligible;
    Map<int, double> eq;
    if (contest.length == 1) {
      eq = {contest.single: 1.0};
    } else {
      final r = EquityCalc(
        hands: [for (final s in contest) cards[s]!],
        board: boardInts,
        // Other live players' cards are out of the deck for this pot too.
        dead: [
          for (final s in live)
            if (!contest.contains(s)) ...cards[s]!
        ],
        holeSize: 4,
        rng: rng,
      ).runAll(samples: samples);
      exact = exact && r.exact;
      eq = {for (var k = 0; k < contest.length; k++) contest[k]: r.equity[k]};
    }
    if (i == 0) mainEquity = eq;
    expected += (eq[hero] ?? 0) * amount;
  }
  final returned =
      breakdown.returnedSeat == hero ? breakdown.returnedAmount : 0;
  final heroEv =
      expected.round() + returned - e.players[hero]!.totalCommit;

  return AllInEv._(
    AllInStatus.ok,
    street: street,
    step: h.actions.length,
    equity: mainEquity,
    heroEv: heroEv,
    heroActual: (h.raw['results'] as Map?)?['hero_net'] as int?,
    exact: exact,
  );
}

/// One captured hand's all-in, tagged for tracker filtering.
typedef CapturedAllIn = ({DateTime at, bool cash, AllInEv ev});

/// Totals across many hands: how hero's all-ins ran versus their EV.
class AllInSummary {
  int hands = 0; // all-ins with an EV and a recorded result
  int expected = 0;
  int actual = 0;
  int missingCards = 0; // all-ins we couldn't score (villain cards unknown)
  int get luck => actual - expected;

  AllInSummary.of(Iterable<AllInEv> evs) {
    for (final ev in evs) {
      if (ev.status == AllInStatus.missingCards) missingCards++;
      if (!ev.ok || ev.heroActual == null) continue;
      hands++;
      expected += ev.heroEv!;
      actual += ev.heroActual!;
    }
  }
}
