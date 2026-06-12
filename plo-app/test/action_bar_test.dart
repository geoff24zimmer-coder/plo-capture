import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/plo_engine.dart';
import 'package:plo_capture/util.dart';
import 'package:plo_capture/widgets/action_bar.dart';

/// 3-handed MTT at 100/200: button raises to 600, SB folds, BB calls → flop.
/// Postflop the BB is first to act, facing no bet.
HandEngine mttToFlop() {
  final e = HandEngine(
    seatedPlayers: [
      PlayerState(1, 50000),
      PlayerState(2, 50000),
      PlayerState(3, 50000),
    ],
    buttonSeat: 1,
    bigBlind: 200,
    forcedBets: const [
      ForcedBet(2, PostType.sb, 100),
      ForcedBet(3, PostType.bb, 200),
    ],
  );
  e.apply(1, ActionType.raise, amount: 600);
  e.apply(2, ActionType.fold);
  e.apply(3, ActionType.call, amount: 600);
  return e;
}

Widget _host(LegalActions la, int currentBet,
        void Function(ActionType, {int? amount}) onAction) =>
    MaterialApp(
      home: Scaffold(
        body: ActionBar(
            la: la, onAction: onAction, isMtt: true, currentBet: currentBet),
      ),
    );

void main() {
  setUp(() {
    chipMode = true; // MTT chips
    tableBigBlind = 200;
    tableUnit = TableUnit.money;
  });

  testWidgets('MTT postflop bet menu offers 2bb / 2.5bb / 3bb + Pot',
      (tester) async {
    final e = mttToFlop();
    expect(e.street, Street.flop);
    final la = e.legalActions();
    expect(la.canCheck, isTrue); // facing no bet → it's a bet, not a raise

    int? capturedAmount;
    ActionType? capturedType;
    await tester.pumpWidget(_host(la, e.currentBet, (t, {int? amount}) {
      capturedType = t;
      capturedAmount = amount;
    }));

    expect(find.text('2bb'), findsOneWidget);
    expect(find.text('2.5bb'), findsOneWidget);
    expect(find.text('3bb'), findsOneWidget);
    expect(find.text('POT'), findsOneWidget);

    await tester.tap(find.text('2.5bb'));
    expect(capturedType, ActionType.bet);
    expect(capturedAmount, 500); // 2.5 × 200bb
  });

  testWidgets('MTT raise menu still sizes off the bet faced (2x / 2.5x / 3x)',
      (tester) async {
    final e = mttToFlop();
    e.apply(3, ActionType.check); // BB checks
    e.apply(1, ActionType.bet, amount: 400); // button bets 400 → BB faces a bet
    final la = e.legalActions();
    expect(la.canCheck, isFalse); // facing a bet → it's a raise

    await tester.pumpWidget(_host(la, e.currentBet, (t, {amount}) {}));
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('2.5x'), findsOneWidget);
    expect(find.text('3x'), findsOneWidget);
    expect(find.text('2bb'), findsNothing); // bb sizing is bet-only
  });
}
