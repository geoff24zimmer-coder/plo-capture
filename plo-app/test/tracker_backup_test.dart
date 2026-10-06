import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/db/hand_store.dart';
import 'package:plo_capture/models/hand_session.dart';
import 'package:plo_capture/models/session.dart';
import 'package:plo_capture/tracker/backup.dart';
import 'package:plo_capture/tracker/split.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Session session(String id,
        {DateTime? ended,
        int? buyIn,
        int? cashOut,
        String venue = 'Lodge',
        String game = 'plo4'}) =>
    Session(
      id: id,
      createdAt: DateTime(2026, 10, 1, 19),
      gameType: 'cash',
      smallBlind: 200,
      bigBlind: 500,
      venue: venue,
      maxSeats: 8,
      endedAt: ended,
      game: game,
      buyIn: buyIn,
      cashOut: cashOut,
    );

HandSession handSession(String id, {DateTime? ended}) => HandSession(
      id: id,
      createdAt: DateTime(2026, 10, 1, 19),
      gameType: 'cash',
      smallBlind: 200,
      bigBlind: 500,
      venue: 'Lodge',
      maxSeats: 8,
      endedAt: ended,
    );

Map<String, dynamic> hand(String id, String sessionId, {int? heroNet}) => {
      'schema_version': '1.0',
      'hand_id': id,
      'captured_at': '2026-10-01T20:00:00.000',
      'session': {'session_id': sessionId},
      'results': {
        'hero_net': heroNet,
        'pots': [
          {'amount': 4000}
        ],
      },
      'meta': {'complete': true, 'marked_for_review': false},
    };

final ended = DateTime(2026, 10, 1, 23);

/// A store on its own temp file. (`inMemoryDatabasePath` is a single shared
/// instance in sqflite, so stores built on it would see each other's rows.)
Future<HandStore> freshStore() async {
  final dir = await Directory.systemTemp.createTemp('plo_store');
  addTearDown(() => dir.delete(recursive: true));
  return HandStore.atPath('${dir.path}/t.db');
}

/// The combined pre-split (v4) layout: one sessions table with the tracker
/// columns, holding both hand sessions and results.
Future<String> v4Database(
    List<Session> sessions, List<Map<String, dynamic>> hands) async {
  final dir = await Directory.systemTemp.createTemp('plo_store');
  addTearDown(() => dir.delete(recursive: true));
  final path = '${dir.path}/v4.db';
  final old = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (d, v) async {
          await d.execute('CREATE TABLE sessions (id TEXT PRIMARY KEY, '
              'created_at INTEGER NOT NULL, game_type TEXT NOT NULL, '
              'sb INTEGER NOT NULL, bb INTEGER NOT NULL, venue TEXT NOT NULL, '
              'max_seats INTEGER NOT NULL, ended_at INTEGER, '
              "game TEXT NOT NULL DEFAULT 'plo4', buy_in INTEGER, "
              "cash_out INTEGER, notes TEXT NOT NULL DEFAULT '', "
              'mtt_finish INTEGER, mtt_entrants INTEGER)');
          await d.execute('CREATE TABLE hands (hand_id TEXT PRIMARY KEY, '
              'session_id TEXT NOT NULL, captured_at INTEGER NOT NULL, '
              'hero_net INTEGER, pot INTEGER, marked INTEGER NOT NULL DEFAULT 0, '
              'is_spot INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL)');
        },
      ));
  for (final s in sessions) {
    await old.insert('sessions', s.toRow());
  }
  for (final h in hands) {
    await old.insert('hands', {
      'hand_id': h['hand_id'],
      'session_id': h['session']['session_id'],
      'captured_at': 0,
      'hero_net': h['results']['hero_net'],
      'json': jsonEncode(h),
    });
  }
  await old.close();
  return path;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('splitting combined (pre-2026-10-06) sessions', () {
    final rows = [
      // Played with hands logged AND a result → both, same id.
      session('both', ended: ended, buyIn: 100000, cashOut: 152500),
      // Logged in the tracker, no hands → tracker only.
      session('result', ended: ended, buyIn: 50000, cashOut: 0),
      // Hands only, never given a result → hand log only.
      session('hands', ended: ended),
      // PLO5 results → tracker only.
      session('plo5', ended: ended, buyIn: 1000, cashOut: 2000, game: 'plo5'),
      // At the table right now, bought in, no hands yet → both.
      session('live', buyIn: 100000),
    ].map((s) => s.toRow());

    final split = splitLegacySessions(rows, withHands: {'both', 'hands'});

    test('results go to the tracker', () {
      expect(split.tracker.map((s) => s.id),
          ['both', 'result', 'plo5', 'live']);
      final both = split.tracker.first;
      expect(both.net, 52500);
      expect(both.createdAt, DateTime(2026, 10, 1, 19));
    });

    test('hand sessions keep their id (hands still point at them)', () {
      expect(split.handLogs.map((s) => s.id), ['both', 'hands', 'live']);
      expect(split.handLogs.last.isActive, isTrue);
    });

    test('a session with hands is never dropped, whatever its game', () {
      final odd = splitLegacySessions(
          [session('x', ended: ended, buyIn: 1, game: 'other').toRow()],
          withHands: {'x'});
      expect(odd.handLogs.single.id, 'x');
    });
  });

  group('backup format', () {
    test('round-trips tracker sessions, hand sessions and hands', () {
      final t = session('t', ended: ended, buyIn: 100000, cashOut: 152500);
      final h = handSession('h', ended: ended);
      final doc = buildBackup(
          trackerSessions: [t], handSessions: [h], hands: [hand('h1', 'h')]);
      final back = parseBackup(jsonEncode(doc));
      expect(back.trackerSessions.single.toRow(), t.toRow());
      expect(back.handSessions.single.toRow(), h.toRow());
      expect(back.hands.single['hand_id'], 'h1');
      expect(back.exportedAt, isNotNull);
    });

    test('a version 1 (combined) backup is split on restore', () {
      final v1 = {
        'format': backupFormat,
        'version': 1,
        'exported_at': '2026-10-01T00:00:00Z',
        'sessions': [
          session('a', ended: ended, buyIn: 100000, cashOut: 50000).toRow(),
          session('b', ended: ended, buyIn: 1, cashOut: 2).toRow(),
          session('c', ended: ended).toRow(),
        ],
        'hands': [hand('h1', 'a'), hand('h2', 'c')],
      };
      final back = parseBackup(jsonEncode(v1));
      expect(back.trackerSessions.map((s) => s.id), ['a', 'b']);
      expect(back.handSessions.map((s) => s.id), ['a', 'c']);
      expect(back.hands, hasLength(2));
    });

    test('rejects things that are not a backup', () {
      expect(() => parseBackup('nope'), throwsFormatException);
      expect(() => parseBackup('{"format":"other"}'), throwsFormatException);
      expect(
          () => parseBackup(jsonEncode({
                'format': backupFormat,
                'version': 99,
                'tracker_sessions': [],
                'hand_sessions': [],
                'hands': []
              })),
          throwsFormatException);
      final orphan = buildBackup(
          trackerSessions: [], handSessions: [], hands: [hand('h1', 'gone')]);
      expect(() => parseBackup(jsonEncode(orphan)), throwsFormatException);
      // A hand can't hang off a tracker session — they're separate worlds.
      final crossed = buildBackup(
          trackerSessions: [session('t', ended: ended)],
          handSessions: [],
          hands: [hand('h1', 't')]);
      expect(() => parseBackup(jsonEncode(crossed)), throwsFormatException);
    });

    test('CSV: blank unresolved results, quoted text, no formula injection', () {
      final csv = sessionsCsv([
        session('b',
            ended: DateTime(2026, 10, 1, 23, 30),
            buyIn: 100000,
            cashOut: 40000,
            venue: 'Lodge, Austin'),
        session('c', ended: DateTime(2026, 10, 1, 21), venue: '=1+1'),
      ]);
      final lines = csv.trim().split('\n');
      expect(lines[0], startsWith('date,start,end,hours'));
      expect(lines[1],
          '2026-10-01,19:00,23:30,4.50,cash,plo4,\$2/\$5 PLO,"Lodge, Austin",1000.00,400.00,-600.00,,,');
      expect(lines[2], contains(",'=1+1,,,,,,"));
    });
  });

  group('HandStore', () {
    test('migrates a v3 database: hand sessions kept, tracker empty', () async {
      final dir = await Directory.systemTemp.createTemp('plo_store');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/v3.db';
      final old = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (d, v) async {
              await d.execute('CREATE TABLE sessions (id TEXT PRIMARY KEY, '
                  'created_at INTEGER NOT NULL, game_type TEXT NOT NULL, '
                  'sb INTEGER NOT NULL, bb INTEGER NOT NULL, venue TEXT NOT NULL, '
                  'max_seats INTEGER NOT NULL, ended_at INTEGER)');
              await d.execute('CREATE TABLE hands (hand_id TEXT PRIMARY KEY, '
                  'session_id TEXT NOT NULL, captured_at INTEGER NOT NULL, '
                  'hero_net INTEGER, pot INTEGER, marked INTEGER NOT NULL DEFAULT 0, '
                  'is_spot INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL)');
            },
          ));
      await old.insert('sessions',
          handSession('old', ended: ended).toRow()..remove('game'));
      await old.close();

      final store = HandStore.atPath(path);
      expect((await store.listHandSessions()).single.session.id, 'old');
      expect(await store.listTrackerSessions(), isEmpty);
    });

    test('migrates a combined v4 database into the two stores', () async {
      final path = await v4Database([
        session('both', ended: ended, buyIn: 100000, cashOut: 152500),
        session('result', ended: ended, buyIn: 50000, cashOut: 0),
        session('hands', ended: ended),
      ], [
        hand('h1', 'both', heroNet: 900),
        hand('h2', 'hands'),
      ]);

      final store = HandStore.atPath(path);
      final tracker = await store.listTrackerSessions();
      expect(tracker.map((s) => s.id).toSet(), {'both', 'result'});
      expect(tracker.firstWhere((s) => s.id == 'both').net, 52500);

      final logs = await store.listHandSessions();
      expect({for (final r in logs) r.session.id: r.handCount},
          {'both': 1, 'hands': 1});
      expect((await store.handsForSession('both')).single['hero_net'], 900);

      // Nothing money-related is left on the hand side.
      final raw = await (await store.db).query('sessions');
      expect(raw.every((r) => r['buy_in'] == null && r['cash_out'] == null),
          isTrue);
    });

    test('a PLO5 hand session keeps its game through store and backup',
        () async {
      final store = await freshStore();
      final five = HandSession(
        id: 'p5',
        createdAt: DateTime(2026, 10, 6, 19),
        gameType: 'cash',
        smallBlind: 500,
        bigBlind: 1000,
        venue: 'Lodge',
        maxSeats: 8,
        game: 'plo5',
      );
      await store.createHandSession(five);
      final got = (await store.listHandSessions()).single.session;
      expect(got.game, 'plo5');
      expect(got.holeSize, 5);
      expect(got.stakesLabel, '\$5/\$10 PLO5');

      final back = parseBackup(jsonEncode(await store.exportAll()));
      expect(back.handSessions.single.game, 'plo5');
    });

    test('a v5 database gains the hand-session game column', () async {
      final dir = await Directory.systemTemp.createTemp('plo_store');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/v5.db';
      final old = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 5,
            onCreate: (d, v) async {
              await d.execute('CREATE TABLE sessions (id TEXT PRIMARY KEY, '
                  'created_at INTEGER NOT NULL, game_type TEXT NOT NULL, '
                  'sb INTEGER NOT NULL, bb INTEGER NOT NULL, venue TEXT NOT NULL, '
                  'max_seats INTEGER NOT NULL, ended_at INTEGER)');
              await d.execute('CREATE TABLE tracker_sessions (id TEXT PRIMARY KEY, '
                  'created_at INTEGER NOT NULL, game_type TEXT NOT NULL, '
                  'sb INTEGER NOT NULL, bb INTEGER NOT NULL, venue TEXT NOT NULL, '
                  'max_seats INTEGER NOT NULL, ended_at INTEGER, '
                  "game TEXT NOT NULL DEFAULT 'plo4', buy_in INTEGER, "
                  "cash_out INTEGER, notes TEXT NOT NULL DEFAULT '', "
                  'mtt_finish INTEGER, mtt_entrants INTEGER)');
              await d.execute('CREATE TABLE hands (hand_id TEXT PRIMARY KEY, '
                  'session_id TEXT NOT NULL, captured_at INTEGER NOT NULL, '
                  'hero_net INTEGER, pot INTEGER, marked INTEGER NOT NULL DEFAULT 0, '
                  'is_spot INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL)');
            },
          ));
      await old.insert('sessions', {
        'id': 'v5',
        'created_at': 0,
        'game_type': 'cash',
        'sb': 200,
        'bb': 500,
        'venue': 'Lodge',
        'max_seats': 8,
      });
      await old.close();

      final store = HandStore.atPath(path);
      expect((await store.listHandSessions()).single.session.game, 'plo4');
      await store.createHandSession(handSession('new'));
    });

    test('a hand session can be edited in place', () async {
      final store = await freshStore();
      await store.createHandSession(handSession('e', ended: ended));
      final s = (await store.listHandSessions()).single.session;
      await store.updateHandSession(HandSession(
        id: s.id,
        createdAt: s.createdAt,
        gameType: s.gameType,
        smallBlind: 500,
        bigBlind: 1000,
        venue: 'Texas Card House',
        maxSeats: 9,
        endedAt: s.endedAt,
      ));
      final got = (await store.listHandSessions()).single.session;
      expect(got.venue, 'Texas Card House');
      expect(got.stakesLabel, '\$5/\$10 PLO');
      expect(got.maxSeats, 9);
    });

    test('hand sessions: a new one ends the current; end clears it', () async {
      final store = await freshStore();
      await store.createHandSession(handSession('one'));
      expect((await store.currentHandSession())!.session.id, 'one');
      await store.createHandSession(handSession('two'));
      expect((await store.currentHandSession())!.session.id, 'two');
      await store.endHandSession('two');
      expect(await store.currentHandSession(), isNull);
      expect(await store.listHandSessions(), hasLength(2));
    });

    test('tracker: logging a past session leaves the live one live', () async {
      final store = await freshStore();
      await store.createTrackerSession(session('live', buyIn: 100000));
      await store.createTrackerSession(
          session('past', ended: DateTime(2026, 9, 1), buyIn: 1, cashOut: 2));
      var all = await store.listTrackerSessions();
      expect(all.firstWhere((s) => s.id == 'live').isActive, isTrue);

      await store.createTrackerSession(session('next'));
      all = await store.listTrackerSessions();
      expect(all.firstWhere((s) => s.id == 'live').isActive, isFalse);
      expect(all.where((s) => s.isActive).single.id, 'next');
    });

    test('the two stores never see each other', () async {
      final store = await freshStore();
      await store.createTrackerSession(
          session('t', ended: ended, buyIn: 1, cashOut: 2));
      await store.createHandSession(handSession('h'));
      expect((await store.listTrackerSessions()).single.id, 't');
      expect((await store.listHandSessions()).single.session.id, 'h');
      await store.deleteTrackerSession('t');
      expect((await store.listHandSessions()).single.session.id, 'h');
    });

    test('export → import into a fresh store, then re-import is a no-op',
        () async {
      final src = await freshStore();
      await src.createTrackerSession(
          session('t', ended: ended, buyIn: 100000, cashOut: 50000));
      await src.createHandSession(handSession('a'));
      await src.insertHand(hand('h1', 'a', heroNet: -2000));
      await src.insertHand(hand('h2', 'a', heroNet: 3000));
      final text = jsonEncode(await src.exportAll());

      final dst = await freshStore();
      final first = await dst.importBackup(parseBackup(text));
      expect(first.trackerAdded, 1);
      expect(first.handSessionsAdded, 1);
      expect(first.handsAdded, 2);
      final rows = await dst.handsForSession('a');
      expect(rows.map((r) => r['hero_net']).toSet(), {-2000, 3000});
      expect(rows.first['pot'], 4000); // columns re-derived from the JSON
      expect((await dst.listTrackerSessions()).single.net, -50000);

      final again = await dst.importBackup(parseBackup(text));
      expect(again.trackerAdded + again.handSessionsAdded + again.handsAdded,
          0);
      expect(again.skipped, 4);
    });
  });
}
