/// A live session: one sitting at one game. Hands belong to sessions.
class Session {
  final String id;
  final DateTime createdAt;
  final String gameType; // cash | mtt
  final int smallBlind; // cents
  final int bigBlind; // cents
  final String venue;
  final int maxSeats;

  const Session({
    required this.id,
    required this.createdAt,
    required this.gameType,
    required this.smallBlind,
    required this.bigBlind,
    required this.venue,
    required this.maxSeats,
  });

  bool get isMtt => gameType == 'mtt';

  String get stakesLabel =>
      isMtt ? 'MTT PLO' : '\$${smallBlind ~/ 100}/\$${bigBlind ~/ 100} PLO';

  Map<String, dynamic> toRow() => {
        'id': id,
        'created_at': createdAt.millisecondsSinceEpoch,
        'game_type': gameType,
        'sb': smallBlind,
        'bb': bigBlind,
        'venue': venue,
        'max_seats': maxSeats,
      };

  static Session fromRow(Map<String, dynamic> r) => Session(
        id: r['id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        gameType: r['game_type'] as String,
        smallBlind: r['sb'] as int,
        bigBlind: r['bb'] as int,
        venue: r['venue'] as String,
        maxSeats: r['max_seats'] as int,
      );
}
