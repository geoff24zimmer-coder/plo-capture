import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/session.dart';

/// Offline-first storage. The full canonical hand JSON is the source of
/// truth (schema v1.0, solver-ready as-is); a few columns are duplicated
/// for fast list queries. Cloud sync later just ships these JSON blobs.
class HandStore {
  HandStore._();
  static final HandStore instance = HandStore._();
  Database? _db;

  Future<Database> get db async {
    // On web the ffi factory uses the name as an IndexedDB key; getDatabasesPath
    // is unsupported there, so pass a bare filename. Native needs a real path.
    final path = kIsWeb
        ? 'plo_capture.db'
        : p.join(await getDatabasesPath(), 'plo_capture.db');
    _db ??= await openDatabase(
      path,
      version: 2,
      onUpgrade: (d, oldV, newV) async {
        // v2: tag decision spots (hands saved mid-action) for the hand list.
        if (oldV < 2) {
          await d.execute(
              'ALTER TABLE hands ADD COLUMN is_spot INTEGER NOT NULL DEFAULT 0');
        }
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            game_type TEXT NOT NULL,
            sb INTEGER NOT NULL,
            bb INTEGER NOT NULL,
            venue TEXT NOT NULL,
            max_seats INTEGER NOT NULL
          )
        ''');
        await d.execute('''
          CREATE TABLE hands (
            hand_id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES sessions(id),
            captured_at INTEGER NOT NULL,
            hero_net INTEGER,
            pot INTEGER,
            marked INTEGER NOT NULL DEFAULT 0,
            is_spot INTEGER NOT NULL DEFAULT 0,
            json TEXT NOT NULL
          )
        ''');
        await d.execute(
            'CREATE INDEX idx_hands_session ON hands(session_id, captured_at)');
      },
    );
    return _db!;
  }

  // ------------------------------------------------------------ sessions

  Future<void> createSession(Session s) async =>
      (await db).insert('sessions', s.toRow());

  /// Delete a session and all of its hands. SQLite foreign keys aren't
  /// enforced here, so cascade explicitly; one transaction keeps it atomic.
  Future<void> deleteSession(String id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('hands', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Sessions newest-first, each with hand count and running hero net.
  Future<List<({Session session, int handCount, int net})>>
      listSessions() async {
    final rows = await (await db).rawQuery('''
      SELECT s.*, COUNT(h.hand_id) AS cnt, COALESCE(SUM(h.hero_net), 0) AS net
      FROM sessions s
      LEFT JOIN hands h ON h.session_id = s.id
      GROUP BY s.id
      ORDER BY s.created_at DESC
    ''');
    return [
      for (final r in rows)
        (
          session: Session.fromRow(r),
          handCount: (r['cnt'] as int?) ?? 0,
          net: (r['net'] as int?) ?? 0,
        )
    ];
  }

  // --------------------------------------------------------------- hands

  Future<void> insertHand(Map<String, dynamic> handJson) async {
    final results = handJson['results'] as Map<String, dynamic>? ?? {};
    final pots = results['pots'] as List<dynamic>? ?? [];
    await (await db).insert('hands', {
      'hand_id': handJson['hand_id'],
      'session_id': handJson['session']['session_id'],
      'captured_at':
          DateTime.parse(handJson['captured_at'] as String).millisecondsSinceEpoch,
      'hero_net': results['hero_net'],
      'pot': pots.isNotEmpty ? pots.first['amount'] : null,
      'marked':
          (handJson['meta']?['marked_for_review'] as bool? ?? false) ? 1 : 0,
      // The JSON is authoritative; this column just mirrors it for list queries.
      'is_spot': (handJson['meta']?['complete'] == false) ? 1 : 0,
      'json': jsonEncode(handJson),
    });
  }

  Future<List<Map<String, dynamic>>> handsForSession(String sessionId) async {
    return (await db).query(
      'hands',
      columns: [
        'hand_id', 'captured_at', 'hero_net', 'pot', 'marked', 'is_spot'
      ],
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'captured_at DESC',
    );
  }

  /// Every hand's full canonical JSON for a session — used by the solver export.
  Future<List<Map<String, dynamic>>> handJsonsForSession(
      String sessionId) async {
    final rows = await (await db).query('hands',
        columns: ['json'], where: 'session_id = ?', whereArgs: [sessionId]);
    return [
      for (final r in rows)
        jsonDecode(r['json'] as String) as Map<String, dynamic>
    ];
  }

  Future<Map<String, dynamic>> getHand(String handId) async {
    final rows = await (await db)
        .query('hands', columns: ['json'], where: 'hand_id = ?', whereArgs: [handId]);
    return jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  Future<void> deleteHand(String handId) async =>
      (await db).delete('hands', where: 'hand_id = ?', whereArgs: [handId]);
}
