import 'plo_engine.dart';

/// Tournament blind level in chips. Captured per hand because levels
/// change mid-session.
class MttLevel {
  final int levelNumber;
  final int sb;
  final int bb;
  final int ante; // BB ante amount; 0 = no ante
  const MttLevel({
    required this.levelNumber,
    required this.sb,
    required this.bb,
    this.ante = 0,
  });
}

/// Immutable description of how the hand started — used both to (re)build
/// engines (deterministic undo = replay all but the last action) and to
/// serialize the canonical hand history.
class HandConfig {
  final Map<int, int> initialStacks; // seat → starting stack (cents)
  final int buttonSeat;
  final int smallBlind;
  final int bigBlind;
  final List<ForcedBet> forcedBets;
  final StraddleActionRule straddleRule;
  final int heroSeat;
  final String gameType; // cash | mtt
  final MttLevel? mttLevel; // required when gameType == 'mtt'
  final int? playersRemaining;

  const HandConfig({
    required this.initialStacks,
    required this.buttonSeat,
    required this.smallBlind,
    required this.bigBlind,
    required this.forcedBets,
    required this.straddleRule,
    required this.heroSeat,
    this.gameType = 'cash',
    this.mttLevel,
    this.playersRemaining,
  });

  HandEngine buildEngine() => HandEngine(
        seatedPlayers: initialStacks.entries
            .map((e) => PlayerState(e.key, e.value))
            .toList(),
        buttonSeat: buttonSeat,
        bigBlind: bigBlind,
        forcedBets: forcedBets,
        straddleRule: straddleRule,
      );
}

String _postTypeName(PostType t) => switch (t) {
      PostType.sb => 'sb',
      PostType.bb => 'bb',
      PostType.ante => 'ante',
      PostType.straddleUtg => 'straddle_utg',
      PostType.straddleUtg2 => 'straddle_utg2',
      PostType.straddleButton => 'straddle_button',
      PostType.straddleMississippi => 'straddle_mississippi',
      PostType.deadBlind => 'dead_blind',
      PostType.missedBlind => 'missed_blind',
    };

/// Build a schema-compliant hand history map (plo-hand-history v1.0).
Map<String, dynamic> buildHandJson({
  required HandEngine engine,
  required HandConfig cfg,
  required Map<int, String> positions,
  required List<String> heroCards,
  required List<String> flop,
  String? turnCard,
  String? riverCard,
  int? winnerSeat,
  int? rake,
  String? sessionId,
  String? notes,
  double? captureSeconds,
  bool markedForReview = false,
}) {
  final won = winnerSeat != null ? engine.pot - (rake ?? 0) : null;
  final heroCommitted = engine.players[cfg.heroSeat]!.totalCommit;

  return {
    'schema_version': '1.0',
    'hand_id': 'hand-${DateTime.now().microsecondsSinceEpoch}',
    'captured_at': DateTime.now().toIso8601String(),
    'session': {
      'session_id': sessionId ?? 'session-local',
      'game_type': cfg.gameType,
      'variant': 'plo4',
      if (cfg.gameType == 'cash') 'currency': 'USD',
      if (cfg.gameType == 'cash')
        'stakes': {'sb': cfg.smallBlind, 'bb': cfg.bigBlind}
      else
        'mtt': {
          'level_number': cfg.mttLevel!.levelNumber,
          'level': {
            'sb': cfg.mttLevel!.sb,
            'bb': cfg.mttLevel!.bb,
            'ante': cfg.mttLevel!.ante,
            'ante_type': cfg.mttLevel!.ante > 0 ? 'bb_ante' : 'none',
          },
          if (cfg.playersRemaining != null)
            'players_remaining': cfg.playersRemaining,
        },
    },
    'table': {
      'max_seats': cfg.initialStacks.length,
      'button_seat': cfg.buttonSeat,
      'straddle_action_rule': switch (cfg.straddleRule) {
        StraddleActionRule.utgFirstStraddlerLast => 'utg_first_straddler_last',
        StraddleActionRule.sbFirst => 'sb_first',
      },
    },
    'players': [
      for (final e in cfg.initialStacks.entries)
        {
          'seat': e.key,
          'position': positions[e.key],
          'stack': {'amount': e.value, 'is_approx': e.key != cfg.heroSeat},
          if (e.key == cfg.heroSeat) 'is_hero': true,
        }
    ],
    'hero': {'seat': cfg.heroSeat, 'cards': heroCards},
    'forced_bets': [
      for (final fb in cfg.forcedBets)
        {
          'seat': fb.seat,
          'post_type': _postTypeName(fb.type),
          'amount': fb.amount,
          'is_live': fb.isLive,
        }
    ],
    'actions': [
      for (final a in engine.log)
        {
          'idx': a.idx,
          'street': a.street.name,
          'seat': a.seat,
          'action': a.action.name,
          'amount': a.amount,
          'pot_before': a.potBefore,
          'amount_to_call': a.amountToCall,
          if (a.isAllIn) 'is_all_in': true,
        }
    ],
    'board': {
      if (flop.isNotEmpty) 'flop': flop,
      if (turnCard != null) 'turn': turnCard,
      if (riverCard != null) 'river': riverCard,
    },
    'results': {
      if (winnerSeat != null)
        'pots': [
          {
            'pot_type': 'main',
            'amount': engine.pot,
            'winners': [
              {'seat': winnerSeat, 'amount_won': won, 'share_type': 'full'}
            ],
          }
        ],
      'rake': rake,
      if (winnerSeat != null)
        'hero_net':
            (winnerSeat == cfg.heroSeat ? won! : 0) - heroCommitted,
    },
    'meta': {
      'marked_for_review': markedForReview,
      if (notes != null) 'notes': notes,
      if (captureSeconds != null) 'capture_seconds': captureSeconds,
    },
  };
}
