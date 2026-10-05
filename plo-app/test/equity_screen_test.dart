import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/screens/equity_screen.dart';

Future<void> pump(WidgetTester t,
    {double width = 360, double height = 740}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: const EquityScreen(),
  ));
  await t.pumpAndSettle();
}

/// Pick cards in the open full-screen picker by their face text ("A♠").
Future<void> pick(WidgetTester t, List<String> faces) async {
  for (final f in faces) {
    await t.tap(find.text(f).last);
    await t.pump(const Duration(milliseconds: 50));
  }
  // The picker closes itself 200ms after the last card.
  await t.pump(const Duration(milliseconds: 300));
  await t.pumpAndSettle();
}

double shownEquity(WidgetTester t, int index) {
  final texts = t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .where((s) => RegExp(r'^\d+\.\d%$').hasMatch(s))
      .toList();
  return double.parse(texts[index].replaceAll('%', ''));
}

void main() {
  testWidgets('heads-up preflop converges to the published 69.1%', (t) async {
    await pump(t);
    await t.tap(find.text('Any').first);
    await t.pumpAndSettle();
    await pick(t, ['A♠', 'A♥', 'K♠', 'K♥']);
    await t.tap(find.text('Any').first);
    await t.pumpAndSettle();
    await pick(t, ['K♦', 'K♣', 'Q♦', 'Q♣']);
    expect(find.textContaining('Simulated · 100,000 deals'), findsOneWidget);
    expect(shownEquity(t, 0), inInclusiveRange(68.6, 69.6));
    expect(shownEquity(t, 1), inInclusiveRange(30.4, 31.4));

    // A flop switches to exact enumeration.
    await t.tap(find.text('Flop'));
    await t.pumpAndSettle();
    await pick(t, ['2♣', '7♦', 'J♥']);
    expect(find.textContaining('Exact · 820 of 820 runouts'), findsOneWidget);
  });

  testWidgets('PLO5 with six players fits a 360px phone', (t) async {
    // Tall so all six rows are built; width is what's under test.
    await pump(t, height: 1400);
    await t.tap(find.text('PLO5'));
    await t.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('Add player'));
      await t.pumpAndSettle();
    }
    expect(find.text('P6'), findsOneWidget);
    expect(find.text('Add player'), findsNothing); // capped at six
    await t.tap(find.text('Any').first);
    await t.pumpAndSettle();
    await pick(t, ['A♠', 'A♥', 'K♠', 'K♥', 'Q♠']);
    // Six equities that sum to ~100.
    final total = [for (var i = 0; i < 6; i++) shownEquity(t, i)]
        .reduce((a, b) => a + b);
    expect(total, closeTo(100, 0.6));
    expect(t.takeException(), isNull);
  });

  testWidgets('a full board names each made hand', (t) async {
    await pump(t, width: 500);
    await t.tap(find.text('Any').first);
    await t.pumpAndSettle();
    await pick(t, ['Q♥', 'J♥', '3♠', '4♦']);
    await t.tap(find.text('Any').first);
    await t.pumpAndSettle();
    await pick(t, ['7♠', '7♦', '9♣', '8♣']);
    await t.tap(find.text('Flop'));
    await t.pumpAndSettle();
    await pick(t, ['A♥', 'K♥', '7♥']);
    await t.tap(find.text('Turn'));
    await t.pumpAndSettle();
    await pick(t, ['2♣']);
    // The hand-countable spot from the engine tests: 30/40 vs 10/40.
    expect(shownEquity(t, 0), 75.0);
    await t.tap(find.text('River'));
    await t.pumpAndSettle();
    await pick(t, ['A♣']); // pairs the board: the set fills up
    expect(find.textContaining('Flush'), findsOneWidget);
    expect(find.textContaining('Full house'), findsOneWidget);
    expect(shownEquity(t, 1), 100.0);
  });
}
