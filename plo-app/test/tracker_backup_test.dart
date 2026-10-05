import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/db/hand_store.dart';
import 'package:plo_capture/models/session.dart';
import 'package:plo_capture/tracker/backup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Session session(String id,
        {DateTime? ended, int? buyIn, int? cashOut, String venue = 'Lodge'}) =>
    Session(
      id: id,
      createdAt: DateTime(2026, 10, 1, 19),
      gameType: 'cash',
      smallBlind: 200,
      bigBlind: 500,
      venue: venue,
      maxSeats: 8,
      endedAt: ended,
      buyIn: buyIn,
      cashOut: cashOut,
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

/// A store on its own temp file. (`inMemoryDatabasePath` is a single shared
/// instance in sqflite, so stores built on it would see each other's rows.)
Future<HandStore> freshStore() async {
  final dir = await Directory.systemTemp.createTemp('plo_store');
  addTearDown(() => dir.delete(recursive: true));
  return HandStore.atPath('${dir.path}/t.db');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('backup format', () {
    test('round-trips sessions and hands', () {
      final s = session('a',
          ended: DateTime(2026, 10, 1, 23), buyIn: 100000, cashOut: 152500);
      final doc = buildBackup(sessions: [s], hands: [hand('h1', 'a')]);
      final back = parseBackup(jsonEncode(doc));
      expect(back.sessions.single.toRow(), s.toRow());
      expect(back.hands.single['hand_id'], 'h1');
      expect(back.exportedAt, isNotNull);
    });

    test('rejects things that are not a backup', () {
      expect(() => parseBackup('nope'), throwsFormatException);
      expect(() => parseBackup('{"format":"other"}'), throwsFormatException);
      expect(
          () => parseBackup(jsonEncode(
              {'format': backupFormat, 'version': 99, 'sessions': [], 'hands': []})),
          throwsFormatException);
      final orphan = buildBackup(sessions: [], hands: [hand('h1', 'gone')]);
      expect(() => parseBackup(jsonEncode(orphan)), throwsFormatException);
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
    test('migrates a v3 database without losing sessions', () async {
      final dir = await Directory.systemTemp.createTemp('plo_store');
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
      await old.insert('sessions', {
        'id': 'old',
        'created_at': DateTime(2026, 6, 1).millisecondsSinceEpoch,
        'game_type': 'cash',
        'sb': 200,
        'bb': 500,
        'venue': 'WSOP',
        'max_seats': 8,
        'ended_at': DateTime(2026, 6, 2).millisecondsSinceEpoch,
      });
      await old.close();

      final store = HandStore.atPath(path);
      final s = (await store.listSessions()).single.session;
      expect(s.id, 'old');
      expect(s.game, 'plo4');
      expect(s.buyIn, isNull);
      expect(s.hasResult, isFalse);
      await store.updateSession(s.copyWith(buyIn: () => 50000, cashOut: () => 90000));
      expect((await store.getSession('old'))!.net, 40000);
      await dir.delete(recursive: true);
    });

    test('logging a finished session keeps the current one active', () async {
      final store = await freshStore();
      await store.createSession(session('live'));
      await store.createSession(session('past',
          ended: DateTime(2026, 9, 1), buyIn: 1, cashOut: 2));
      expect((await store.currentSession())!.session.id, 'live');
      await store.createSession(session('next'));
      expect((await store.getSession('live'))!.isActive, isFalse);
    });

    test('endSession records the cash-out', () async {
      final store = await freshStore();
      await store.createSession(session('x', buyIn: 100000));
      await store.endSession('x', cashOut: 125000);
      final s = (await store.getSession('x'))!;
      expect(s.isActive, isFalse);
      expect(s.net, 25000);
    });

    test('export → import into a fresh store, then re-import is a no-op',
        () async {
      final src = await freshStore();
      await src.createSession(session('a',
          ended: DateTime(2026, 10, 1, 23), buyIn: 100000, cashOut: 50000));
      await src.insertHand(hand('h1', 'a', heroNet: -2000));
      await src.insertHand(hand('h2', 'a', heroNet: 3000));
      final text = jsonEncode(await src.exportAll());

      final dst = await freshStore();
      final first = await dst.importBackup(parseBackup(text));
      expect(first.sessionsAdded, 1);
      expect(first.handsAdded, 2);
      final rows = await dst.handsForSession('a');
      expect(rows.map((r) => r['hero_net']).toSet(), {-2000, 3000});
      expect(rows.first['pot'], 4000); // columns re-derived from the JSON

      final again = await dst.importBackup(parseBackup(text));
      expect(again.sessionsAdded, 0);
      expect(again.sessionsSkipped, 1);
      expect(again.handsSkipped, 2);
    });
  });
}
