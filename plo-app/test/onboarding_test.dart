import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/onboarding_guide.dart';

void main() {
  // Renders the first-run walkthrough and steps through it, asserting each step
  // shows and the controls advance/close. Guards against build/overflow errors
  // (the dialog is the only place a brand-new user is onboarded).
  testWidgets('first-run guide renders and steps through start to finish',
      (tester) async {
    // A phone-ish surface so any RenderFlex overflow would throw.
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Show it through a real dialog route so the close button can pop.
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    showDialog<void>(context: ctx, builder: (_) => buildFirstRunGuide());
    await tester.pumpAndSettle();

    // Step 1 of 6.
    expect(find.text('Log a hand in ~15 seconds'), findsOneWidget);
    expect(find.text('Back'), findsNothing); // no Back on the first step

    // Walk forward to the last step.
    for (final title in const [
      '1 · Set up the hand',
      '2 · Replay the action in order',
      '3 · Claim your seat — the one trick',
      '4 · Play the hand out',
      '5 · Save it',
    ]) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }

    // The two non-obvious mechanics are spelled out somewhere in the flow.
    expect(find.text('Next'), findsNothing); // last step swaps Next -> Start logging
    expect(find.text('Start logging'), findsOneWidget);

    // Back walks the steps in reverse.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('5 · Save it'), findsNothing);
    expect(find.text('4 · Play the hand out'), findsOneWidget);

    // The final button dismisses the dialog.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start logging'));
    await tester.pumpAndSettle();
    expect(find.text('Start logging'), findsNothing);
  });
}
