import 'plo_engine.dart';
import 'hand_recorder.dart';

/// A stored hand parsed back into engine-replayable form. The replayer
/// rebuilds the engine and applies the first k actions for any step k —
/// the same deterministic-replay trick that powers undo during capture.
class LoadedHand {
  final HandConfig cfg;
  final Map<int, String> positions;
  final List<String> heroCards;
  final List<({int seat, ActionType type, int? amount})> actions;
  final List<String> flop;
  final String? turnCard;
  final String? riverCard;
  final int? winnerSeat;
  final Map<int, List<String>> shownCards; // villain seat -> cards seen
  final Map<String, dynamic> raw;

  const LoadedHand({
    required this.cfg,
    required this.positions,
    required this.heroCards,
    required this.actions,
    required this.flop,
    required this.turnCard,
    required this.riverCard,
    required this.winnerSeat,
    required this.shownCards,
    required this.raw,
  });

  HandEngine engineAtStep(int k) {
    final e = cfg.buildEngine();
    for (var i = 0; i < k && i < actions.length; i++) {
      final a = actions[i];
      e.apply(a.seat, a.type, amount: a.amount);
    }
    return e;
  }
}

PostType _postType(String s) => switch (s) {
      'sb' => PostType.sb,
      'bb' => PostType.bb,
      'ante' => PostType.ante,
      'straddle_utg' => PostType.straddleUtg,
      'straddle_utg2' => PostType.straddleUtg2,
      'straddle_button' => PostType.straddleButton,
      'straddle_mississippi' => PostType.straddleMississippi,
      'dead_blind' => PostType.deadBlind,
      _ => PostType.missedBlind,
    };

LoadedHand loadHand(Map<String, dynamic> j) {
  final session = j['session'] as Map<String, dynamic>;
  final table = j['table'] as Map<String, dynamic>;
  final players = (j['players'] as List).cast<Map<String, dynamic>>();
  final hero = j['hero'] as Map<String, dynamic>;
  final stakes = session['stakes'] as Map<String, dynamic>? ?? {};

  final forced = [
    for (final f in (j['forced_bets'] as List).cast<Map<String, dynamic>>())
      ForcedBet(
        f['seat'] as int,
        _postType(f['post_type'] as String),
        f['amount'] as int,
        isLive: f['is_live'] as bool? ?? true,
      )
  ];

  final cfg = HandConfig(
    initialStacks: {
      for (final p in players)
        p['seat'] as int: (p['stack'] as Map<String, dynamic>)['amount'] as int
    },
    buttonSeat: table['button_seat'] as int,
    smallBlind: stakes['sb'] as int? ?? 0,
    bigBlind: stakes['bb'] as int? ??
        forced.firstWhere((f) => f.type == PostType.bb).amount,
    forcedBets: forced,
    straddleRule: table['straddle_action_rule'] == 'sb_first'
        ? StraddleActionRule.sbFirst
        : StraddleActionRule.utgFirstStraddlerLast,
    heroSeat: hero['seat'] as int,
  );

  final board = j['board'] as Map<String, dynamic>? ?? {};
  final showdown =
      (j['showdown'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final shown = <int, List<String>>{
    for (final s in showdown)
      if ((s['cards'] as List?)?.isNotEmpty ?? false)
        s['seat'] as int: (s['cards'] as List).cast<String>(),
  };
  final results = j['results'] as Map<String, dynamic>? ?? {};
  final pots = results['pots'] as List? ?? [];
  int? winner;
  if (pots.isNotEmpty) {
    final winners = (pots.first as Map<String, dynamic>)['winners'] as List?;
    if (winners != null && winners.isNotEmpty) {
      winner = (winners.first as Map<String, dynamic>)['seat'] as int?;
    }
  }

  return LoadedHand(
    cfg: cfg,
    positions: {
      for (final p in players)
        p['seat'] as int: p['position'] as String? ?? 'Seat ${p['seat']}'
    },
    heroCards: (hero['cards'] as List).cast<String>(),
    actions: [
      for (final a in (j['actions'] as List).cast<Map<String, dynamic>>())
        (
          seat: a['seat'] as int,
          type: ActionType.values.byName(a['action'] as String),
          amount: a['amount'] as int?,
        )
    ],
    flop: (board['flop'] as List?)?.cast<String>() ?? const [],
    turnCard: board['turn'] as String?,
    riverCard: board['river'] as String?,
    winnerSeat: winner,
    shownCards: shown,
    raw: j,
  );
}
