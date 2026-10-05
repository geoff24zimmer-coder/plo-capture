/// A live session: one sitting at one game. Hands belong to sessions, and the
/// session also carries the tracker result (buy-in / cash-out) that win rate is
/// computed from.
///
/// Win rate comes from [buyIn]/[cashOut] ONLY — never from summing captured
/// hands, which is a biased sample (players log the interesting hands). A
/// session without both is "unresolved" and stays out of the stats rather than
/// having a result invented for it.
///
/// Tracker money ([buyIn], [cashOut]) is ALWAYS real currency in cents, even for
/// MTTs — whose captured hands are denominated in tournament chips.
class Session {
  final String id;

  /// When the session started. Editable (sessions logged after the fact).
  final DateTime createdAt;
  final String gameType; // cash | mtt
  final int smallBlind; // cents
  final int bigBlind; // cents
  final String venue;
  final int maxSeats;
  final DateTime? endedAt; // null = active; this is the resumable "current" session

  /// Game played, for the tracker: `plo4` | `plo5` | `other`. Hand capture is
  /// 4-card only — a plo5/other session records results, not hands.
  final String game;

  /// Total money in, cents: buy-in plus every rebuy/add-on (MTT: buy-in + fee,
  /// re-entries included). Null = not entered.
  final int? buyIn;

  /// Total money out, cents (MTT: prize + bounties; 0 = busted). Null = not
  /// entered yet.
  final int? cashOut;
  final String notes;
  final int? mttFinish; // finishing place, if known
  final int? mttEntrants; // field size, if known

  const Session({
    required this.id,
    required this.createdAt,
    required this.gameType,
    required this.smallBlind,
    required this.bigBlind,
    required this.venue,
    required this.maxSeats,
    this.endedAt,
    this.game = 'plo4',
    this.buyIn,
    this.cashOut,
    this.notes = '',
    this.mttFinish,
    this.mttEntrants,
  });

  bool get isMtt => gameType == 'mtt';
  bool get isActive => endedAt == null;

  /// Hands can only be captured for 4-card PLO (the engine/schema are plo4-only).
  bool get canCaptureHands => game == 'plo4';

  /// Ended, with both buy-in and cash-out entered — counts toward win rate.
  bool get hasResult => !isActive && buyIn != null && cashOut != null;

  /// Net result in cents, or null when unresolved.
  int? get net => hasResult ? cashOut! - buyIn! : null;

  /// Time at the table. Active sessions count up to [now].
  Duration duration([DateTime? now]) {
    final end = endedAt ?? now ?? DateTime.now();
    final d = end.difference(createdAt);
    return d.isNegative ? Duration.zero : d;
  }

  double hours([DateTime? now]) => duration(now).inSeconds / 3600.0;

  /// Shorter than this and the clock didn't really run — typically a result
  /// entered straight after playing. Such a session counts toward net and
  /// win %, but its "hours" are unknown, not zero, so it stays out of every
  /// per-hour figure (a +\$492 over 40 seconds is not \$44,000/hr).
  static const minTimed = Duration(minutes: 5);

  /// Ended with real playing time recorded (see [minTimed]).
  bool get isTimed => !isActive && duration() >= minTimed;

  static const gameLabels = {'plo4': 'PLO', 'plo5': 'PLO5', 'other': 'Mixed'};

  String get gameLabel => gameLabels[game] ?? game.toUpperCase();

  String get stakesLabel => isMtt
      ? 'MTT $gameLabel'
      : '${_dollars(smallBlind)}/${_dollars(bigBlind)} $gameLabel';

  static String _dollars(int cents) => cents % 100 == 0
      ? '\$${cents ~/ 100}'
      : '\$${(cents / 100).toStringAsFixed(2)}';

  Session copyWith({
    DateTime? createdAt,
    String? gameType,
    int? smallBlind,
    int? bigBlind,
    String? venue,
    int? maxSeats,
    DateTime? Function()? endedAt,
    String? game,
    int? Function()? buyIn,
    int? Function()? cashOut,
    String? notes,
    int? Function()? mttFinish,
    int? Function()? mttEntrants,
  }) =>
      Session(
        id: id,
        createdAt: createdAt ?? this.createdAt,
        gameType: gameType ?? this.gameType,
        smallBlind: smallBlind ?? this.smallBlind,
        bigBlind: bigBlind ?? this.bigBlind,
        venue: venue ?? this.venue,
        maxSeats: maxSeats ?? this.maxSeats,
        endedAt: endedAt != null ? endedAt() : this.endedAt,
        game: game ?? this.game,
        buyIn: buyIn != null ? buyIn() : this.buyIn,
        cashOut: cashOut != null ? cashOut() : this.cashOut,
        notes: notes ?? this.notes,
        mttFinish: mttFinish != null ? mttFinish() : this.mttFinish,
        mttEntrants: mttEntrants != null ? mttEntrants() : this.mttEntrants,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'created_at': createdAt.millisecondsSinceEpoch,
        'game_type': gameType,
        'sb': smallBlind,
        'bb': bigBlind,
        'venue': venue,
        'max_seats': maxSeats,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'game': game,
        'buy_in': buyIn,
        'cash_out': cashOut,
        'notes': notes,
        'mtt_finish': mttFinish,
        'mtt_entrants': mttEntrants,
      };

  /// Tolerates rows missing the tracker columns (older backups).
  static Session fromRow(Map<String, dynamic> r) => Session(
        id: r['id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        gameType: r['game_type'] as String,
        smallBlind: r['sb'] as int,
        bigBlind: r['bb'] as int,
        venue: r['venue'] as String,
        maxSeats: r['max_seats'] as int,
        endedAt: r['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['ended_at'] as int),
        game: (r['game'] as String?) ?? 'plo4',
        buyIn: r['buy_in'] as int?,
        cashOut: r['cash_out'] as int?,
        notes: (r['notes'] as String?) ?? '',
        mttFinish: r['mtt_finish'] as int?,
        mttEntrants: r['mtt_entrants'] as int?,
      );
}
