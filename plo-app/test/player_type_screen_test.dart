// The player-type sheet on the real capture screen (ai-hand-reviewer D35). The capture screen uses browser-only code,
// so this runs in Chrome: flutter test --platform chrome test/player_type_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/models/hand_session.dart';
import 'package:plo_capture/screens/capture_screen.dart';

/// The table keeps a pulsing ring on whoever is to act, so it never fully settles: wait for dialogs to open and close.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('on the table', () {
    Future<void> startHand(WidgetTester t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: CaptureScreen(
          session: HandSession(
            id: 's1',
            createdAt: DateTime(2026, 11, 12),
            gameType: 'cash',
            smallBlind: 200,
            bigBlind: 500,
            venue: 'Test room',
            maxSeats: 8,
          ),
        ),
      ));
      await t.pumpAndSettle();
      // The first-run guide may open over the screen; close it if it did.
      while (find.byType(Dialog).evaluate().isNotEmpty) {
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        final close = find.byIcon(Icons.close);
        if (close.evaluate().isNotEmpty) {
          await t.tap(close.first);
          await t.pumpAndSettle();
        }
        break;
      }
      await t.tap(find.text('Start hand'));
      await settle(t);
    }

    testWidgets(
        'long-press a seat, one tap on a type: it shows under the seat; tap it again to clear',
        (t) async {
      await startHand(t);
      expect(find.text('STATION'), findsNothing);

      await t.longPress(find.text('CO'));
      await settle(t);
      expect(find.text('Player type'), findsOneWidget);
      expect(find.text('Calls too much'), findsOneWidget);
      final chip = find.byKey(const ValueKey('type-station'));
      expect(t.getSize(chip).height, greaterThanOrEqualTo(48)); // easy to hit
      await t.tap(chip);
      await settle(t);
      expect(find.text('Player type'), findsNothing); // one tap closed it
      expect(find.text('STATION'), findsOneWidget);

      await t.longPress(find.text('CO'));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('type-station')));
      await settle(t);
      expect(find.text('STATION'), findsNothing);
    });

    testWidgets('setting a type leaves the stack alone; Cancel changes nothing',
        (t) async {
      await startHand(t);
      await t.longPress(find.text('HJ'));
      await settle(t);
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(find.text('NIT'), findsNothing);

      await t.longPress(find.text('HJ'));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('type-nit')));
      await settle(t);
      expect(find.text('NIT'), findsOneWidget);
      expect(find.textContaining("doesn't fit"), findsNothing);
    });
  });
}
