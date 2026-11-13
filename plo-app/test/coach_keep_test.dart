// Kept AI coach reviews (ai-hand-reviewer D36): the store, and the coach's own hand list.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/db/hand_store.dart';
import 'package:plo_capture/models/hand_session.dart';
import 'package:plo_capture/screens/coach_hands_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

HandSession handSession(String id) => HandSession(
      id: id,
      createdAt: DateTime(2026, 11, 13, 19),
      gameType: 'cash',
      smallBlind: 200,
      bigBlind: 500,
      venue: 'Lodge',
      maxSeats: 8,
    );

Map<String, dynamic> hand(String id, String sessionId,
        {String at = '2026-11-13T20:00:00.000', bool heroActs = true}) =>
    {
      'schema_version': '1.0',
      'hand_id': id,
      'captured_at': at,
      'session': {
        'session_id': sessionId,
        'game_type': 'cash',
        'stakes': {'sb': 200, 'bb': 500},
      },
      'hero': {
        'seat': 1,
        'cards': ['9d', '9c', '8d', '8c']
      },
      'players': [
        {'seat': 1, 'position': 'UTG'},
      ],
      'actions': [
        if (heroActs) {'street': 'preflop', 'seat': 1, 'action': 'raise'},
      ],
      'results': {'hero_net': null, 'pots': []},
      'meta': {'complete': true, 'marked_for_review': false},
    };

const review = {
  'decisions': [
    {
      'street': 'preflop',
      'action_ref': 'your open',
      'label': 'Close',
      'verdict': 'v',
      'why': 'w',
      'next_time': 'n'
    },
  ],
  'assumptions': <String>[],
};

Future<HandStore> freshStore() async {
  final dir = await Directory.systemTemp.createTemp('plo_store');
  addTearDown(() => dir.delete(recursive: true));
  return HandStore.atPath('${dir.path}/t.db');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('HandStore keeps coach reviews', () {
    test('saved, read back, and marked on the hand lists', () async {
      final s = await freshStore();
      await s.createHandSession(handSession('s1'));
      await s.insertHand(hand('h1', 's1'));
      await s.insertHand(hand('h2', 's1', at: '2026-11-13T21:00:00.000'));
      expect(await s.coachReview('h1'), isNull);

      await s.saveCoachReview('h1', review, at: DateTime(2026, 11, 13, 22));
      final kept = await s.coachReview('h1');
      expect(kept?.at, DateTime(2026, 11, 13, 22));
      expect(kept?.review, review);

      final listed = {
        for (final r in await s.handsForSession('s1'))
          r['hand_id']: r['reviewed']
      };
      expect(listed, {'h1': 1, 'h2': 0});
      final recent = await s.recentHands();
      expect(recent.map((r) => r['hand_id']), ['h2', 'h1']); // newest first
      expect(recent.map((r) => r['reviewed']), [0, 1]);
    });

    test('a newer review of the same hand replaces the old one', () async {
      final s = await freshStore();
      await s.createHandSession(handSession('s1'));
      await s.insertHand(hand('h1', 's1'));
      await s.saveCoachReview('h1', review);
      await s.saveCoachReview('h1', {
        ...review,
        'assumptions': ['newer']
      });
      expect((await s.coachReview('h1'))?.review['assumptions'], ['newer']);
    });

    test('deleting a hand or its session deletes its review', () async {
      final s = await freshStore();
      await s.createHandSession(handSession('s1'));
      await s.insertHand(hand('h1', 's1'));
      await s.insertHand(hand('h2', 's1'));
      await s.saveCoachReview('h1', review);
      await s.saveCoachReview('h2', review);
      await s.deleteHand('h1');
      expect(await s.coachReview('h1'), isNull);
      await s.deleteHandSession('s1');
      expect(await s.coachReview('h2'), isNull);
    });

    test('a v6 database upgrades with its hands intact', () async {
      final dir = await Directory.systemTemp.createTemp('plo_store');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/v6.db';
      final old = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 6,
            onCreate: (d, v) async {
              await d.execute(
                  'CREATE TABLE sessions (id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, '
                  'game_type TEXT NOT NULL, sb INTEGER NOT NULL, bb INTEGER NOT NULL, venue TEXT NOT NULL, '
                  "max_seats INTEGER NOT NULL, ended_at INTEGER, game TEXT NOT NULL DEFAULT 'plo4')");
              await d.execute(
                  'CREATE TABLE hands (hand_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, '
                  'captured_at INTEGER NOT NULL, hero_net INTEGER, pot INTEGER, marked INTEGER NOT NULL DEFAULT 0, '
                  'is_spot INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL)');
            },
          ));
      await old.insert('hands', {
        'hand_id': 'h1',
        'session_id': 's1',
        'captured_at': 1,
        'json': jsonEncode(hand('h1', 's1'))
      });
      await old.close();

      final s = HandStore.atPath(path);
      expect((await s.handsForSession('s1')).single['reviewed'], 0);
      await s.saveCoachReview('h1', review);
      expect((await s.handsForSession('s1')).single['reviewed'], 1);
    });
  });

  group('CoachHandsScreen', () {
    Map<String, dynamic> row(String id,
            {int reviewed = 0, bool heroActs = true, int at = 0}) =>
        {
          'hand_id': id,
          'captured_at': DateTime(2026, 11, 13, 20, at).millisecondsSinceEpoch,
          'json': jsonEncode(hand(id, 's1', heroActs: heroActs)),
          'reviewed': reviewed,
        };
    bool heroActed(Map<String, dynamic> h) => (h['actions'] as List).isNotEmpty;

    Future<void> pump(WidgetTester t, List<Map<String, dynamic>> rows,
        {List<String>? opened}) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: CoachHandsScreen(
          load: () async => rows,
          canReview: heroActed,
          reviewScreen: (h) {
            opened?.add(h['hand_id'] as String);
            return const Scaffold(body: Text('the review'));
          },
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets(
        'lists only hands the coach can review, marks the reviewed ones, and opens one in a tap',
        (t) async {
      final opened = <String>[];
      await pump(
          t, [row('h1', reviewed: 1), row('h2'), row('h3', heroActs: false)],
          opened: opened);
      expect(find.textContaining('UTG'),
          findsNWidgets(2)); // h3 has nothing to review
      expect(find.text('Reviewed'), findsOneWidget);
      expect(
          find.textContaining('Nov 13 · 8:00pm · \$2/\$5'), findsNWidgets(2));
      await t.tap(find.textContaining('UTG').last);
      await t.pumpAndSettle();
      expect(opened, ['h2']);
      expect(find.text('the review'), findsOneWidget);
    });

    testWidgets('with nothing to review, says how to get a hand there',
        (t) async {
      await pump(t, [row('h3', heroActs: false)]);
      expect(
          find.textContaining('No hands for the coach yet.'), findsOneWidget);
    });

    testWidgets('rows are big enough to tap and read', (t) async {
      await pump(t, [row('h1')]);
      final card = find
          .ancestor(
              of: find.textContaining('UTG'), matching: find.byType(InkWell))
          .first;
      expect(t.getSize(card).height, greaterThanOrEqualTo(72));
      expect(t.widget<Text>(find.textContaining('UTG')).style?.fontSize,
          greaterThanOrEqualTo(20));
    });
  });
}
