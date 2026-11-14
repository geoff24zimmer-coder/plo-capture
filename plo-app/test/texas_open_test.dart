// Texas $1/$3 with a straddle (ai-hand-reviewer D38). Geoff: "Texas allows for 5x opens ... first person in could
// raise to 30 off the 6 dollar straddle". The first raise before the flop can be up to 5 straddles; after it, raises
// are pot-limit again. Other games are unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/hand_loader.dart';
import 'package:plo_capture/hand_recorder.dart';
import 'package:plo_capture/plo_engine.dart';
import 'package:plo_capture/widgets/action_bar.dart';

/// 5-handed cash. Seats: 1=BTN, 2=SB, 3=BB, 4=UTG (straddles), 5=UTG+1 (first to act).
HandConfig cfg(
        {int sb = 100,
        int bb = 300,
        bool straddle = true,
        String gameType = 'cash',
        int stack = 100000}) =>
    HandConfig(
      initialStacks: {1: stack, 2: stack, 3: stack, 4: stack, 5: stack},
      buttonSeat: 1,
      smallBlind: sb,
      bigBlind: bb,
      forcedBets: [
        ForcedBet(2, PostType.sb, sb),
        ForcedBet(3, PostType.bb, bb),
        if (straddle) ForcedBet(4, PostType.straddleUtg, bb * 2),
      ],
      straddleRule: StraddleActionRule.sbFirst,
      heroSeat: 5,
      gameType: gameType,
      mttLevel: gameType == 'mtt'
          ? MttLevel(levelNumber: 1, sb: sb, bb: bb, ante: 0)
          : null,
    );

void main() {
  group('the engine', () {
    test(r'first in off the $6 straddle, the most is $30 (the pot allows $22)',
        () {
      final e = cfg().buildEngine();
      final la = e.legalActions();
      expect(la.maxRaiseTo, 3000);
      expect(la.texasOpen, isTrue);
      expect(la.sizing!.pot, 2200,
          reason: 'the POT button is still a pot-sized raise');
      e.apply(5, ActionType.raise, amount: 3000);
      expect(e.currentBet, 3000);
    });

    test(r'more than $30 is refused', () {
      final e = cfg().buildEngine();
      expect(() => e.apply(5, ActionType.raise, amount: 3100),
          throwsA(isA<EngineException>()));
    });

    test('after a limp, the first raise can still be 5 straddles', () {
      final e = cfg().buildEngine();
      e.apply(5, ActionType.call);
      final la = e.legalActions(); // the button: pot after calling allows $28
      expect(la.maxRaiseTo, 3000);
      expect(la.texasOpen, isTrue);
    });

    test(
        r'after the open, re-raises are pot-limit again ($100 over a $30 open)',
        () {
      final e = cfg().buildEngine();
      e.apply(5, ActionType.raise, amount: 3000);
      final la = e.legalActions(); // the button
      expect(la.maxRaiseTo, 10000);
      expect(la.texasOpen, isFalse);
    });

    test('a short stack caps it at all-in', () {
      final e = cfg(stack: 2500).buildEngine();
      expect(e.legalActions().maxRaiseTo, 2500);
    });

    test(
        r'other games stay pot-limit: $1/$3 with no straddle, $2/$5 with a straddle, tournaments',
        () {
      expect(
          cfg(straddle: false).buildEngine().legalActions().maxRaiseTo, 1000);
      expect(
          cfg(straddle: false).buildEngine().legalActions().texasOpen, isFalse);
      expect(
          cfg(sb: 200, bb: 500).buildEngine().legalActions().maxRaiseTo, 3700);
      expect(
          cfg(gameType: 'mtt').buildEngine().legalActions().maxRaiseTo, 2200);
    });

    test(r'a saved hand with a $30 open loads and replays', () {
      final c = cfg();
      final e = c.buildEngine();
      e.apply(5, ActionType.raise, amount: 3000);
      for (final s in [1, 2, 3, 4]) {
        e.apply(s, ActionType.fold);
      }
      final json = buildHandJson(
        engine: e,
        cfg: c,
        positions: const {1: 'BTN', 2: 'SB', 3: 'BB', 4: 'UTG', 5: 'UTG1'},
        heroCards: const ['As', 'Ks', 'Qh', 'Jh'],
        flop: const [],
        complete: false,
      );
      final loaded = loadHand(json);
      final replay = loaded.cfg.buildEngine();
      for (final a in loaded.actions) {
        replay.apply(a.seat, a.type, amount: a.amount);
      }
      expect(replay.log.first.amount, 3000);
    });
  });

  group('the raise buttons', () {
    Future<int?> tapFive(WidgetTester tester, HandEngine e) async {
      int? got;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ActionBar(
            la: e.legalActions(),
            isMtt: false,
            currentBet: e.currentBet,
            onAction: (a, {amount}) => got = amount,
          ),
        ),
      ));
      if (find.text('5×').evaluate().isEmpty) return null;
      await tester.tap(find.text('5×'));
      return got;
    }

    testWidgets(r'a 5× button opens to $30 in one tap', (tester) async {
      expect(await tapFive(tester, cfg().buildEngine()), 3000);
      expect(find.text(r'$30'), findsOneWidget);
    });

    testWidgets('no 5× button in other games', (tester) async {
      expect(
          await tapFive(tester, cfg(sb: 200, bb: 500).buildEngine()), isNull);
    });
  });
}
