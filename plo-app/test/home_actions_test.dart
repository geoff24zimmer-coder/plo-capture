import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/widgets/home_actions.dart';

void main() {
  testWidgets('"Log played hands" sub-menu returns cash or tournament',
      (t) async {
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final picked = <String?>[];
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Column(children: [
            HomeAction(
              title: 'Log played hands',
              subtitle: 'Capture a hand in 15 seconds',
              icon: Icons.style_outlined,
              accent: homeEmerald,
              onTap: () async => picked.add(await pickGameType(ctx)),
            ),
          ]),
        ),
      ),
    ));
    await t.tap(find.text('Log played hands'));
    await t.pumpAndSettle();
    expect(find.text('What are you playing?'), findsOneWidget);
    await t.tap(find.text('Tournament'));
    await t.pumpAndSettle();
    await t.tap(find.text('Log played hands'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cash game'));
    await t.pumpAndSettle();
    expect(picked, ['mtt', 'cash']);
    expect(t.takeException(), isNull);
  });
}
