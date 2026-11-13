// Player types (ai-hand-reviewer D35): long-press a seat, tap Station / Nit / Maniac / Reg, and the type shows under
// the seat and is saved as that seat's tags for the AI coach.

import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/hand_recorder.dart';
import 'package:plo_capture/models/player_type.dart';
import 'package:plo_capture/plo_engine.dart';

/// 2/5 cash, 4-handed. Seats: 1=BTN, 2=SB, 3=BB, 4=UTG.
HandConfig cfg4({int hero = 1}) => HandConfig(
      initialStacks: const {1: 100000, 2: 100000, 3: 100000, 4: 100000},
      buttonSeat: 1,
      smallBlind: 200,
      bigBlind: 500,
      forcedBets: const [
        ForcedBet(2, PostType.sb, 200),
        ForcedBet(3, PostType.bb, 500),
      ],
      straddleRule: StraddleActionRule.sbFirst,
      heroSeat: hero,
    );

Map<String, dynamic> playerAt(Map<String, dynamic> json, int seat) =>
    (json['players'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['seat'] == seat);

void main() {
  group('saved with the hand', () {
    Map<String, dynamic> build(Map<int, PlayerType> types) {
      final cfg = cfg4();
      final e = cfg.buildEngine();
      e.apply(4, ActionType.raise, amount: 1700);
      e.apply(1, ActionType.call);
      return buildHandJson(
        engine: e,
        cfg: cfg,
        positions: const {1: 'BTN', 2: 'SB', 3: 'BB', 4: 'UTG'},
        heroCards: const ['As', 'Ks', 'Qh', 'Jh'],
        flop: const [],
        playerTypes: types,
        complete: false,
      );
    }

    test("a typed seat gets its tag; untyped seats get none", () {
      final json = build({4: PlayerType.station, 3: PlayerType.nit});
      expect(playerAt(json, 4)['tags'], ['station']);
      expect(playerAt(json, 3)['tags'], ['nit']);
      expect(playerAt(json, 2).containsKey('tags'), isFalse);
    });

    test("the hero's own seat never gets a type", () {
      final json = build({1: PlayerType.maniac});
      expect(playerAt(json, 1).containsKey('tags'), isFalse);
    });

    test('a saved type reads back', () {
      expect(PlayerType.fromTags(['reg']), PlayerType.reg);
      expect(PlayerType.fromTags(['straddler']), isNull);
      expect(PlayerType.fromTags(null), isNull);
    });
  });
}
