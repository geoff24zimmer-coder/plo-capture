/// PLO Live Engine — action-order state machine + pot-limit math.
///
/// Pure logic, no Flutter dependencies. The capture UI sits on top of this:
/// it asks `whoseTurn()` / `legalActions()` to render buttons, and calls
/// `apply()` on each tap. The same engine validates imported hands and
/// powers the replayer.
///
/// All amounts are integers in the smallest currency unit (cents) or chips.
/// Raise amounts are always RAISE-TO (total street commitment), never increments.
library plo_engine;

enum Street { preflop, flop, turn, river }

enum ActionType { fold, check, call, bet, raise }

enum PostType {
  sb,
  bb,
  ante,
  straddleUtg,
  straddleUtg2,
  straddleButton,
  straddleMississippi,
  deadBlind,
  missedBlind,
}

/// House rule for preflop action order under a button/Mississippi straddle.
/// Texas rooms vary: most open the action UTG with the straddler acting last;
/// some open with the small blind.
enum StraddleActionRule { utgFirstStraddlerLast, sbFirst }

enum HandStatus { acting, wonByFold, showdown }

class ForcedBet {
  final int seat;
  final PostType type;
  final int amount;
  final bool isLive;
  const ForcedBet(this.seat, this.type, this.amount, {this.isLive = true});

  bool get isStraddle =>
      type == PostType.straddleUtg ||
      type == PostType.straddleUtg2 ||
      type == PostType.straddleButton ||
      type == PostType.straddleMississippi;

  bool get isButtonStyle =>
      type == PostType.straddleButton || type == PostType.straddleMississippi;
}

class PlayerState {
  final int seat;
  int stack; // chips behind
  int streetCommit = 0;
  int totalCommit = 0;
  bool folded = false;
  PlayerState(this.seat, this.stack);
  bool get isAllIn => !folded && stack == 0 && totalCommit > 0;
  bool get canAct => !folded && stack > 0;
}

/// One-tap sizing presets, expressed as legal raise-to / bet-to totals,
/// already clamped to [min, max] and the actor's stack.
class BetSizing {
  final int half;
  final int threeQuarter;
  final int pot;
  const BetSizing(this.half, this.threeQuarter, this.pot);
}

class LegalActions {
  final int seat;
  final int toCall; // incremental chips needed to call (stack-capped)
  final bool canCheck;
  final bool canCall;
  final bool canBetOrRaise; // false when a short all-in failed to reopen action
  final int? minRaiseTo;
  final int? maxRaiseTo; // pot-limit max, stack-capped
  final BetSizing? sizing;
  const LegalActions({
    required this.seat,
    required this.toCall,
    required this.canCheck,
    required this.canCall,
    required this.canBetOrRaise,
    this.minRaiseTo,
    this.maxRaiseTo,
    this.sizing,
  });
}

/// Immutable log entry — maps 1:1 onto the `actions[]` array of the
/// canonical hand history schema.
class AppliedAction {
  final int idx;
  final Street street;
  final int seat;
  final ActionType action;
  final int? amount; // raise-to total; null for fold/check
  final int potBefore;
  final int amountToCall;
  final bool isAllIn;
  const AppliedAction({
    required this.idx,
    required this.street,
    required this.seat,
    required this.action,
    required this.amount,
    required this.potBefore,
    required this.amountToCall,
    required this.isAllIn,
  });
}

class EngineException implements Exception {
  final String message;
  EngineException(this.message);
  @override
  String toString() => 'EngineException: $message';
}

class HandEngine {
  final int buttonSeat;
  final int bigBlind;
  final StraddleActionRule straddleRule;

  final Map<int, PlayerState> players = {};
  final List<int> _seatOrder = []; // occupied seats, clockwise
  final List<AppliedAction> log = [];

  Street street = Street.preflop;
  HandStatus status = HandStatus.acting;
  int pot = 0; // running total of ALL chips committed (all streets)
  int currentBet = 0; // highest street commitment this street
  int _lastRaiseSize = 0; // increment of last full bet/raise
  final List<int> _queue = []; // seats pending action, in order
  final List<int> _ring = []; // this street's action ORDER — persists through
  // raises, which matters under a button straddle: after a raise, action
  // continues around the MODIFIED ring (… SB, BB, straddler last), not the
  // physical clockwise seating.
  final Set<int> _actedSinceFullRaise = {};
  final Set<int> _raiseBlocked = {}; // seats facing a short all-in they can't re-raise

  HandEngine({
    required List<PlayerState> seatedPlayers,
    required this.buttonSeat,
    required this.bigBlind,
    required List<ForcedBet> forcedBets,
    this.straddleRule = StraddleActionRule.utgFirstStraddlerLast,
  }) {
    final sorted = [...seatedPlayers]..sort((a, b) => a.seat.compareTo(b.seat));
    for (final p in sorted) {
      players[p.seat] = p;
      _seatOrder.add(p.seat);
    }
    if (players.length < 2) throw EngineException('Need at least 2 players');
    if (!players.containsKey(buttonSeat)) {
      throw EngineException('Button seat $buttonSeat is not occupied');
    }
    _postForcedBets(forcedBets);
    _buildPreflopQueue(forcedBets);
  }

  // ---------------------------------------------------------------- setup

  void _postForcedBets(List<ForcedBet> bets) {
    for (final fb in bets) {
      final p = players[fb.seat];
      if (p == null) throw EngineException('Forced bet from empty seat ${fb.seat}');
      final amt = fb.amount < p.stack ? fb.amount : p.stack;
      p.stack -= amt;
      p.totalCommit += amt;
      pot += amt;
      // Dead money (BB ante, dead blinds) is in the pot and the player's
      // total, but is NOT a street commitment: it must never count toward the
      // facing bet, or the poster can't check/call their live blind. (Inv. 6)
      if (fb.isLive) {
        p.streetCommit += amt;
        if (fb.type != PostType.ante && p.streetCommit > currentBet) {
          currentBet = p.streetCommit;
        }
      }
    }
    // Min raise increment over blinds/straddles equals the largest live post:
    // over a $10 straddle the minimum raise is TO $20; over a $5 BB, TO $10.
    _lastRaiseSize = currentBet > 0 ? currentBet : bigBlind;
  }

  /// Occupied seats clockwise, starting AFTER [seat], full orbit back to it.
  List<int> _seatsAfter(int seat) {
    final i = _seatOrder.indexOf(seat);
    if (i < 0) throw EngineException('Seat $seat not occupied');
    return [
      ..._seatOrder.sublist(i + 1),
      ..._seatOrder.sublist(0, i + 1),
    ];
  }

  void _buildPreflopQueue(List<ForcedBet> bets) {
    final bbSeat = bets
        .firstWhere((b) => b.type == PostType.bb,
            orElse: () => throw EngineException('No big blind posted'))
        .seat;

    final straddles = bets.where((b) => b.isStraddle).toList();
    ForcedBet? buttonStraddle;
    for (final s in straddles) {
      if (s.isButtonStyle) {
        buttonStraddle = s;
        break;
      }
    }

    List<int> order;
    if (players.length == 2) {
      // Heads-up: button is SB and acts first preflop.
      order = [buttonSeat, bbSeat];
    } else if (buttonStraddle != null) {
      switch (straddleRule) {
        case StraddleActionRule.utgFirstStraddlerLast:
          order = _seatsAfter(bbSeat)
            ..remove(buttonStraddle.seat)
            ..add(buttonStraddle.seat);
          break;
        case StraddleActionRule.sbFirst:
          order = _seatsAfter(buttonStraddle.seat)
            ..remove(buttonStraddle.seat)
            ..add(buttonStraddle.seat);
          break;
      }
    } else if (straddles.isNotEmpty) {
      // UTG / double straddles: action opens after the last straddler,
      // who naturally holds the option last (full orbit).
      straddles.sort((a, b) =>
          _seatsAfter(bbSeat).indexOf(a.seat) -
          _seatsAfter(bbSeat).indexOf(b.seat));
      order = _seatsAfter(straddles.last.seat);
    } else {
      order = _seatsAfter(bbSeat); // UTG first ... BB last (option)
    }

    _ring
      ..clear()
      ..addAll(order);
    _queue
      ..clear()
      ..addAll(order.where((s) => players[s]!.canAct));
  }

  /// Seats after [seat] in the current street's action ring, excluding it.
  List<int> _ringAfter(int seat) {
    final i = _ring.indexOf(seat);
    return [..._ring.sublist(i + 1), ..._ring.sublist(0, i)];
  }

  // ------------------------------------------------------------- queries

  int? whoseTurn() =>
      status == HandStatus.acting && _queue.isNotEmpty ? _queue.first : null;

  List<int> get activeSeats =>
      _seatOrder.where((s) => !players[s]!.folded).toList();

  /// Pot-limit math, the one formula that must never be wrong:
  ///   toCallInc     = currentBet - actorStreetCommit
  ///   potAfterCall  = pot + toCallInc
  ///   maxRaiseTo    = currentBet + potAfterCall      (stack-capped)
  LegalActions legalActions() {
    final seat = whoseTurn();
    if (seat == null) throw EngineException('No action pending');
    final p = players[seat]!;

    final toCallInc = currentBet - p.streetCommit;
    final cappedCall = toCallInc < p.stack ? toCallInc : p.stack;
    final potAfterCall = pot + toCallInc;
    final allInTo = p.streetCommit + p.stack;

    final canRaise = !_raiseBlocked.contains(seat) && allInTo > currentBet;
    int? minTo, maxTo;
    BetSizing? sizing;
    if (canRaise) {
      maxTo = currentBet + potAfterCall;
      if (maxTo > allInTo) maxTo = allInTo;
      minTo = currentBet + _lastRaiseSize;
      if (minTo > maxTo) minTo = maxTo; // short all-in is always allowed
      int frac(num f) {
        var t = currentBet + (f * potAfterCall).round();
        if (t < minTo!) t = minTo;
        if (t > maxTo!) t = maxTo;
        return t;
      }

      sizing = BetSizing(frac(0.5), frac(0.75), frac(1.0));
    }

    return LegalActions(
      seat: seat,
      toCall: cappedCall,
      canCheck: toCallInc == 0,
      canCall: toCallInc > 0 && p.stack > 0,
      canBetOrRaise: canRaise,
      minRaiseTo: minTo,
      maxRaiseTo: maxTo,
      sizing: sizing,
    );
  }

  // -------------------------------------------------------------- apply

  AppliedAction apply(int seat, ActionType action, {int? amount}) {
    if (status != HandStatus.acting) throw EngineException('Hand is over');
    if (whoseTurn() != seat) {
      throw EngineException('Out of turn: action is on seat ${whoseTurn()}');
    }
    final p = players[seat]!;
    final la = legalActions();
    final potBefore = pot;
    final toCallBefore = la.toCall;
    var isAllIn = false;
    int? recordedAmount;

    switch (action) {
      case ActionType.fold:
        p.folded = true;
        _queue.removeAt(0);
        break;

      case ActionType.check:
        if (!la.canCheck) throw EngineException('Cannot check facing a bet');
        _queue.removeAt(0);
        break;

      case ActionType.call:
        if (!la.canCall) throw EngineException('Nothing to call');
        _commit(p, la.toCall);
        isAllIn = p.stack == 0;
        recordedAmount = p.streetCommit;
        _queue.removeAt(0);
        break;

      case ActionType.bet:
      case ActionType.raise:
        if (!la.canBetOrRaise) {
          throw EngineException('Raising is not reopened for seat $seat');
        }
        final to = amount;
        if (to == null) throw EngineException('Bet/raise requires an amount');
        if (to > la.maxRaiseTo!) {
          throw EngineException(
              'Exceeds pot limit: max raise-to is ${la.maxRaiseTo}');
        }
        final allInTo = p.streetCommit + p.stack;
        if (to < la.minRaiseTo! && to != allInTo) {
          throw EngineException(
              'Below minimum raise-to of ${la.minRaiseTo} (and not all-in)');
        }
        final oldBet = currentBet;
        _commit(p, to - p.streetCommit);
        currentBet = to;
        isAllIn = p.stack == 0;
        recordedAmount = to;

        final increment = to - oldBet;
        final fullRaise = increment >= _lastRaiseSize;
        if (fullRaise) {
          _lastRaiseSize = increment;
          _raiseBlocked.clear();
        } else {
          // Short all-in: players who already acted may call/fold only.
          _raiseBlocked.addAll(_actedSinceFullRaise);
        }
        _rebuildQueueAfterAggression(seat, fullRaise);
        break;
    }

    _actedSinceFullRaise.add(seat);
    final entry = AppliedAction(
      idx: log.length,
      street: street,
      seat: seat,
      action: action,
      amount: recordedAmount,
      potBefore: potBefore,
      amountToCall: toCallBefore,
      isAllIn: isAllIn,
    );
    log.add(entry);

    _settle();
    return entry;
  }

  void _commit(PlayerState p, int amt) {
    if (amt > p.stack) throw EngineException('Commit exceeds stack');
    p.stack -= amt;
    p.streetCommit += amt;
    p.totalCommit += amt;
    pot += amt;
  }

  void _rebuildQueueAfterAggression(int aggressor, bool fullRaise) {
    _queue
      ..clear()
      ..addAll(_ringAfter(aggressor).where((s) => players[s]!.canAct));
    if (fullRaise) {
      _actedSinceFullRaise
        ..clear()
        ..add(aggressor);
    }
  }

  void _settle() {
    final live = activeSeats;
    if (live.length == 1) {
      status = HandStatus.wonByFold;
      _queue.clear();
      return;
    }
    if (_queue.isNotEmpty) return;

    // Street complete.
    if (street == Street.river) {
      status = HandStatus.showdown;
      return;
    }
    _nextStreet();
  }

  void _nextStreet() {
    street = Street.values[street.index + 1];
    currentBet = 0;
    _lastRaiseSize = bigBlind; // min bet postflop = one big blind
    _actedSinceFullRaise.clear();
    _raiseBlocked.clear();
    for (final p in players.values) {
      p.streetCommit = 0;
    }
    _ring
      ..clear()
      ..addAll(_seatsAfter(buttonSeat));
    final actors = _ring.where((s) => players[s]!.canAct).toList();
    _queue
      ..clear()
      ..addAll(actors.length >= 2 ? actors : const <int>[]);
    if (_queue.isEmpty) {
      // Everyone all-in (or one live player vs all-ins): run it out.
      if (street == Street.river) {
        status = HandStatus.showdown;
      } else {
        _nextStreet();
      }
    }
  }
}
