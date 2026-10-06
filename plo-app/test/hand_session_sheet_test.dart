import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/models/hand_session.dart';
import 'package:plo_capture/widgets/hand_session_sheet.dart';

final played = HandSession(
  id: 'hs1',
  createdAt: DateTime(2026, 10, 1, 19),
  gameType: 'cash',
  smallBlind: 200,
  bigBlind: 500,
  venue: 'Lodge',
  maxSeats: 8,
  endedAt: DateTime(2026, 10, 2, 1),
);

/// Opens the sheet from a button and returns what it popped.
Future<HandSession? Function()> open(WidgetTester t,
    {HandSession? initial, bool lockGame = false}) async {
  t.view.physicalSize = const Size(500, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  HandSession? out;
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => out = await handSessionSheet(ctx,
              gameType: 'cash', initial: initial, lockGame: lockGame),
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
  return () => out;
}

void main() {
  testWidgets('new session: PLO5 and stakes, starts now, no money fields',
      (t) async {
    final out = await open(t);
    expect(find.text('New cash game'), findsOneWidget);
    expect(find.textContaining('Buy-in'), findsNothing);
    await t.tap(find.text('PLO5'));
    await t.enterText(find.widgetWithText(TextField, 'Venue'), 'Lodge');
    await t.enterText(find.widgetWithText(TextField, 'BB \$'), '10');
    await t.tap(find.text('Start cash game'));
    await t.pumpAndSettle();
    final s = out()!;
    expect(s.game, 'plo5');
    expect(s.venue, 'Lodge');
    expect(s.bigBlind, 1000);
    expect(s.isActive, isTrue);
  });

  testWidgets('edit keeps the id and times; changes venue and stakes',
      (t) async {
    final out = await open(t, initial: played);
    expect(find.text('Edit session'), findsOneWidget);
    expect(find.text('Start 7:00pm'), findsOneWidget);
    expect(find.text('End 1:00am'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Venue'), 'Texas Card House');
    await t.enterText(find.widgetWithText(TextField, 'SB \$'), '5');
    await t.enterText(find.widgetWithText(TextField, 'BB \$'), '10');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final s = out()!;
    expect(s.id, 'hs1');
    expect(s.venue, 'Texas Card House');
    expect(s.smallBlind, 500);
    expect(s.bigBlind, 1000);
    expect(s.createdAt, played.createdAt);
    expect(s.endedAt, played.endedAt);
  });

  testWidgets('PLO/PLO5 is locked once the session has hands', (t) async {
    final out = await open(t, initial: played, lockGame: true);
    expect(find.text('Fixed once hands are logged.'), findsOneWidget);
    await t.tap(find.text('PLO5'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(out()!.game, 'plo4');
  });
}
