import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/equity/allin_ev.dart';
import 'package:plo_capture/hand_loader.dart';
import 'package:plo_capture/hand_recorder.dart';
import 'package:plo_capture/models/session.dart';
import 'package:plo_capture/plo_engine.dart';
import 'package:plo_capture/screens/session_list_screen.dart';
import 'package:plo_capture/widgets/ledger_calendar.dart';
import 'package:plo_capture/widgets/session_editor.dart';
import 'package:plo_capture/widgets/tracker_stats_view.dart';

var _n = 0;
Session cash(DateTime start, double hours, int? buyIn, int? cashOut,
        {String venue = 'Lodge', int bb = 5}) =>
    Session(
      id: 't${_n++}',
      createdAt: start,
      gameType: 'cash',
      smallBlind: 200,
      bigBlind: bb * 100,
      venue: venue,
      maxSeats: 8,
      endedAt: start.add(Duration(minutes: (hours * 60).round())),
      buyIn: buyIn == null ? null : buyIn * 100,
      cashOut: cashOut == null ? null : cashOut * 100,
    );

Session mtt(DateTime start, int buyIn, int cashOut) => Session(
      id: 'm${_n++}',
      createdAt: start,
      gameType: 'mtt',
      smallBlind: 0,
      bigBlind: 0,
      venue: 'Series',
      maxSeats: 8,
      endedAt: start.add(const Duration(hours: 7)),
      buyIn: buyIn * 100,
      cashOut: cashOut * 100,
    );

/// This month's sessions so the calendar (which opens on today) shows them.
List<Session> sample() {
  final now = DateTime.now();
  DateTime day(int d, int h) => DateTime(now.year, now.month, d, h);
  return [
    cash(day(1, 19), 5, 1000, 2240),
    cash(day(2, 20), 3.5, 1500, 310, venue: 'Texas Card House'),
    cash(day(3, 18), 6, 1000, 1000, bb: 10),
    cash(day(4, 19), 4, 1000, null), // unresolved
    mtt(day(2, 11), 1100, 0),
    mtt(day(3, 11), 600, 4200),
  ];
}

/// The page's own vertical list (the stats tab also has a horizontal chip row).
final page = find.byType(Scrollable).first;

Future<void> pump(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(500, 717);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: Scaffold(body: child),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('calendar shows HRS / +/- and the month ledger', (t) async {
    await pump(t,
        LedgerCalendar(sessions: sample(), onOpen: (_) async {}));
    expect(find.text('MONTH LEDGER'), findsOneWidget);
    expect(find.text('+1.2k'), findsOneWidget); // day 1: +$1,240
    expect(find.text('5h'), findsOneWidget);
    // Day 2 combines the cash loss (−1,190) and the MTT bust (−1,100).
    expect(find.text('-2.3k'), findsOneWidget);
    await t.scrollUntilVisible(find.text('RUNNING TOTAL'), 100, scrollable: page);
    expect(find.text('DAYS PLAYED'), findsOneWidget);
    // The unresolved day is flagged, not counted.
    await t.scrollUntilVisible(find.textContaining('no result yet'), 100,
        scrollable: page);
  });

  testWidgets('calendar day opens its sessions', (t) async {
    Session? opened;
    await pump(t, LedgerCalendar(
        sessions: sample(), onOpen: (s) async => opened = s));
    await t.tap(find.text('+1.2k'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Lodge').last);
    await t.pumpAndSettle();
    expect(opened?.cashOut, 224000);
  });

  testWidgets('cash stats render without overflow, incl. chart drag',
      (t) async {
    await pump(t, TrackerStatsView(sessions: sample()));
    expect(find.text('WIN RATE'), findsOneWidget);
    expect(find.text('+\$50'), findsOneWidget); // net: 1240 − 1190 + 0
    await t.scrollUntilVisible(find.text('RUNNING TOTAL'), 200, scrollable: page);
    await t.drag(find.byType(CustomPaint).last, const Offset(-80, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('session'), findsWidgets);
    await t.scrollUntilVisible(find.text('BY STAKES'), 200, scrollable: page);
    expect(find.text('PER HR'), findsWidgets);
    // One unresolved cash session called out.
    await t.scrollUntilVisible(find.textContaining('no result yet'), 200, scrollable: page);
  });

  testWidgets('tournament stats: ROI and ITM', (t) async {
    await pump(t, TrackerStatsView(sessions: sample()));
    await t.tap(find.text('Tournaments'));
    await t.pumpAndSettle();
    expect(find.text('ROI'), findsOneWidget);
    expect(find.text('147%'), findsOneWidget); // (4200 − 1700) / 1700
    expect(find.text('50%'), findsOneWidget); // 1 of 2 cashed
  });

  testWidgets('empty states', (t) async {
    await pump(t, const TrackerStatsView(sessions: []));
    expect(find.textContaining('No cash sessions'), findsOneWidget);
  });

  testWidgets('session list shows results, never captured-hand sums',
      (t) async {
    final ss = sample();
    await pump(
        t,
        SessionListView(
          rows: [
            for (final s in ss) (session: s, handCount: 3, handsNet: 99999)
          ],
          onOpen: (_) async {},
          onChanged: () {},
        ));
    expect(find.text('+\$1,240'), findsOneWidget);
    expect(find.text('ADD RESULT'), findsOneWidget);
    expect(find.textContaining('999'), findsNothing);
  });

  testWidgets('editor logs a past session with a result', (t) async {
    Session? out;
    await pump(
        t,
        Builder(
            builder: (ctx) => TextButton(
                onPressed: () async => out = await editSession(ctx),
                child: const Text('go'))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Venue'), 'Lodge');
    await t.enterText(
        find.widgetWithText(TextField, 'Total buy-in (incl. rebuys)'), '1,000');
    await t.enterText(find.widgetWithText(TextField, 'Cash-out'), '1450');
    await t.pumpAndSettle();
    expect(find.text('+\$450'), findsOneWidget); // live net preview
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(out!.venue, 'Lodge');
    expect(out!.net, 45000);
    expect(out!.hasResult, isTrue);
    expect(out!.hours(), closeTo(4, 1e-9));
  });

  testWidgets('all-in luck card from captured cash all-ins', (t) async {
    // Hero's 75% turn jam (EV +5,150) that lost 10,000.
    const cfg = HandConfig(
      initialStacks: {1: 10000, 2: 10000, 3: 10000, 4: 10000},
      buttonSeat: 1,
      smallBlind: 200,
      bigBlind: 500,
      forcedBets: [
        ForcedBet(2, PostType.sb, 200),
        ForcedBet(3, PostType.bb, 500),
      ],
      straddleRule: StraddleActionRule.sbFirst,
      heroSeat: 1,
    );
    final e = cfg.buildEngine();
    for (final (s, a, amt) in [
      (4, ActionType.fold, null),
      (1, ActionType.call, null),
      (2, ActionType.fold, null),
      (3, ActionType.check, null),
      (3, ActionType.check, null),
      (1, ActionType.check, null),
      (3, ActionType.bet, 1200),
      (1, ActionType.raise, 4800),
      (3, ActionType.raise, 9500),
      (1, ActionType.call, null),
    ]) {
      e.apply(s, a, amount: amt);
    }
    final ev = computeAllInEv(loadHand(buildHandJson(
      engine: e,
      cfg: cfg,
      positions: const {1: 'BTN', 2: 'SB', 3: 'BB', 4: 'UTG'},
      heroCards: const ['Qh', 'Jh', '3s', '4d'],
      flop: const ['Ah', 'Kh', '7h'],
      turnCard: '2c',
      riverCard: 'Ad',
      potWinners: const [
        [3]
      ],
      shownCards: const {
        3: ['7s', '7d', '9c', '8c']
      },
    )));
    await pump(
        t,
        TrackerStatsView(
          sessions: sample(),
          allIns: [
            (at: DateTime.now(), cash: true, ev: ev),
            (at: DateTime.now(), cash: false, ev: ev), // MTT: not counted
          ],
        ));
    await t.scrollUntilVisible(find.text('ALL-IN LUCK'), 200, scrollable: page);
    await t.scrollUntilVisible(find.textContaining('below expectation'), 100,
        scrollable: page);
    expect(find.text('+\$51.50'), findsOneWidget); // expected
    expect(find.text('-\$100'), findsOneWidget); // actual
    expect(find.text('You ran \$151.50 below expectation in these spots.'),
        findsOneWidget);
  });
}
