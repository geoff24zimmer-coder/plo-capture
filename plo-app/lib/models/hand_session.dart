/// A hand-logging session: one sitting at one game whose hands were captured.
/// It holds only what the hands need — game type, stakes, venue, table size,
/// and when it ran. No money: results live in the session tracker ([Session]),
/// which is deliberately separate — logged hands never feed the tracker and the
/// tracker never reads hands.
class HandSession {
  final String id;
  final DateTime createdAt;
  final String gameType; // cash | mtt
  final int smallBlind; // cents (0 for MTT — levels are captured per hand)
  final int bigBlind; // cents
  final String venue;
  final int maxSeats;
  final DateTime? endedAt; // null = active; the resumable "current" session

  /// `plo4` | `plo5` — how many hole cards each player holds. The betting
  /// engine is the same pot-limit machine either way.
  final String game;

  const HandSession({
    required this.id,
    required this.createdAt,
    required this.gameType,
    required this.smallBlind,
    required this.bigBlind,
    required this.venue,
    required this.maxSeats,
    this.endedAt,
    this.game = 'plo4',
  });

  bool get isMtt => gameType == 'mtt';
  bool get isActive => endedAt == null;

  /// Time at the table. Active sessions count up to [now].
  Duration duration([DateTime? now]) {
    final end = endedAt ?? now ?? DateTime.now();
    final d = end.difference(createdAt);
    return d.isNegative ? Duration.zero : d;
  }

  bool get isPlo5 => game == 'plo5';

  /// Hole cards per player.
  int get holeSize => isPlo5 ? 5 : 4;

  String get gameLabel => isPlo5 ? 'PLO5' : 'PLO';

  String get stakesLabel => isMtt
      ? 'MTT $gameLabel'
      : '${_dollars(smallBlind)}/${_dollars(bigBlind)} $gameLabel';

  static String _dollars(int cents) => cents % 100 == 0
      ? '\$${cents ~/ 100}'
      : '\$${(cents / 100).toStringAsFixed(2)}';

  HandSession ended(DateTime at) => HandSession(
        id: id,
        createdAt: createdAt,
        gameType: gameType,
        smallBlind: smallBlind,
        bigBlind: bigBlind,
        venue: venue,
        maxSeats: maxSeats,
        endedAt: at,
        game: game,
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
      };

  /// Ignores any tracker columns on the row (pre-split databases and backups);
  /// anything but `plo5` is a PLO4 session (older rows have no game, or the
  /// tracker's).
  static HandSession fromRow(Map<String, dynamic> r) => HandSession(
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
        game: r['game'] == 'plo5' ? 'plo5' : 'plo4',
      );
}
