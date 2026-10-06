import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/hand_session.dart';
import '../models/session.dart';
import '../tracker/backup.dart';
import '../tracker/split.dart';

/// Offline-first storage. The full canonical hand JSON is the source of
/// truth (schema v1.0, solver-ready as-is); a few columns are duplicated
/// for fast list queries. Cloud sync later just ships these JSON blobs.
///
/// Two separate worlds share the file but never each other's rows:
/// - hand logging — `sessions` (a [HandSession] per sitting) + `hands`;
/// - the session tracker — `tracker_sessions` ([Session] results).
/// Logged hands never feed the tracker, and the tracker never reads hands.
class HandStore {
  HandStore._() : _pathOverride = null;

  /// A store on an explicit path (tests use `inMemoryDatabasePath`).
  HandStore.atPath(String path) : _pathOverride = path;

  static final HandStore instance = HandStore._();
  final String? _pathOverride;
  Database? _db;

  static const _trackerColumns = '''
            game TEXT NOT NULL DEFAULT 'plo4',
            buy_in INTEGER,
            cash_out INTEGER,
            notes TEXT NOT NULL DEFAULT '',
            mtt_finish INTEGER,
            mtt_entrants INTEGER''';

  static const _trackerTable = '''
          CREATE TABLE tracker_sessions (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            game_type TEXT NOT NULL,
            sb INTEGER NOT NULL,
            bb INTEGER NOT NULL,
            venue TEXT NOT NULL,
            max_seats INTEGER NOT NULL,
            ended_at INTEGER,
$_trackerColumns
          )''';

  Future<Database> get db async {
    if (_db != null) return _db!;
    // On web the ffi factory uses the name as an IndexedDB key; getDatabasesPath
    // is unsupported there, so pass a bare filename. Native needs a real path.
    final path = _pathOverride ??
        (kIsWeb
            ? 'plo_capture.db'
            : p.join(await getDatabasesPath(), 'plo_capture.db'));
    _db = await openDatabase(
      path,
      version: 5,
      onUpgrade: (d, oldV, newV) async {
        // v2: tag decision spots (hands saved mid-action) for the hand list.
        if (oldV < 2) {
          await d.execute(
              'ALTER TABLE hands ADD COLUMN is_spot INTEGER NOT NULL DEFAULT 0');
        }
        // v3: sessions can be ended; null ended_at = the active session.
        if (oldV < 3) {
          await d.execute('ALTER TABLE sessions ADD COLUMN ended_at INTEGER');
        }
        // v4: session tracker — game played + buy-in/cash-out result.
        if (oldV < 4) {
          for (final col in _trackerColumns.split(',')) {
            await d.execute('ALTER TABLE sessions ADD COLUMN ${col.trim()}');
          }
        }
        // v5: the tracker and hand logging separate. Results move to their own
        // table; `sessions` keeps only hand sessions (see tracker/split.dart).
        if (oldV < 5) await _splitTracker(d);
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
            max_seats INTEGER NOT NULL,
            ended_at INTEGER
          )
        ''');
        await d.execute(_trackerTable);
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

  /// v4 → v5: copy every result into `tracker_sessions`, drop result-only
  /// rows from `sessions`, and clear the result columns left behind there
  /// (SQLite can't portably drop columns; nothing reads them any more).
  static Future<void> _splitTracker(Database d) async {
    await d.execute(_trackerTable);
    final rows = await d.query('sessions');
    final withHands = {
      for (final r in await d.rawQuery('SELECT DISTINCT session_id FROM hands'))
        r['session_id'] as String
    };
    final split = splitLegacySessions(rows, withHands: withHands);
    final keep = {for (final s in split.handLogs) s.id};
    final batch = d.batch();
    for (final s in split.tracker) {
      batch.insert('tracker_sessions', s.toRow());
    }
    for (final r in rows) {
      if (!keep.contains(r['id'])) {
        batch.delete('sessions', where: 'id = ?', whereArgs: [r['id']]);
      }
    }
    batch.rawUpdate("UPDATE sessions SET game = 'plo4', buy_in = NULL, "
        "cash_out = NULL, notes = '', mtt_finish = NULL, mtt_entrants = NULL");
    await batch.commit(noResult: true);
  }

  /// Open the database (which lazily loads the sqlite3 wasm + IndexedDB on web)
  /// ahead of time, so the first session-create / hand-save isn't blocked on
  /// that one-time init. Fire-and-forget from main(); errors are swallowed.
  Future<void> warmUp() async {
    try {
      await (await db).rawQuery('SELECT 1');
    } catch (_) {}
  }

  // ------------------------------------------------------- hand sessions

  Future<void> createHandSession(HandSession s) async {
    final d = await db;
    // Only one hand session is "current" at a time — starting a new one ends
    // any still-active ones (they stay in Past sessions).
    await d.update(
        'sessions', {'ended_at': DateTime.now().millisecondsSinceEpoch},
        where: 'ended_at IS NULL');
    await d.insert('sessions', s.toRow());
  }

  /// The resumable "current" hand session — the most recent one not ended —
  /// with its hand count. Null when there's none.
  Future<({HandSession session, int handCount})?> currentHandSession() async {
    final rows = await (await db).rawQuery('''
      SELECT s.*, COUNT(h.hand_id) AS cnt
      FROM sessions s
      LEFT JOIN hands h ON h.session_id = s.id
      WHERE s.ended_at IS NULL
      GROUP BY s.id
      ORDER BY s.created_at DESC
      LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    return (
      session: HandSession.fromRow(rows.first),
      handCount: (rows.first['cnt'] as int?) ?? 0,
    );
  }

  /// End a hand session so it's no longer the resumable current one.
  Future<void> endHandSession(String id) async => (await db).update(
        'sessions',
        {'ended_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Delete a hand session and all of its hands. SQLite foreign keys aren't
  /// enforced here, so cascade explicitly; one transaction keeps it atomic.
  Future<void> deleteHandSession(String id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('hands', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Hand sessions newest-first, each with its hand count.
  Future<List<({HandSession session, int handCount})>>
      listHandSessions() async {
    final rows = await (await db).rawQuery('''
      SELECT s.*, COUNT(h.hand_id) AS cnt
      FROM sessions s
      LEFT JOIN hands h ON h.session_id = s.id
      GROUP BY s.id
      ORDER BY s.created_at DESC
    ''');
    return [
      for (final r in rows)
        (session: HandSession.fromRow(r), handCount: (r['cnt'] as int?) ?? 0)
    ];
  }

  // ---------------------------------------------------- tracker sessions

  Future<void> createTrackerSession(Session s) async {
    final d = await db;
    // One live tracker session at a time — starting one ends any still-live
    // ones (unresolved). One logged after the fact leaves the live one alone.
    if (s.isActive) {
      await d.update('tracker_sessions',
          {'ended_at': DateTime.now().millisecondsSinceEpoch},
          where: 'ended_at IS NULL');
    }
    await d.insert('tracker_sessions', s.toRow());
  }

  /// Overwrite a tracker session (result entry, edits, add-ons, ending).
  Future<void> updateTrackerSession(Session s) async => (await db).update(
      'tracker_sessions', s.toRow(),
      where: 'id = ?', whereArgs: [s.id]);

  Future<void> deleteTrackerSession(String id) async => (await db)
      .delete('tracker_sessions', where: 'id = ?', whereArgs: [id]);

  /// Every tracker session, newest first.
  Future<List<Session>> listTrackerSessions() async => [
        for (final r in await (await db)
            .query('tracker_sessions', orderBy: 'created_at DESC'))
          Session.fromRow(r)
      ];

  // --------------------------------------------------------------- hands

  Future<void> insertHand(Map<String, dynamic> handJson) async =>
      (await db).insert('hands', _handRow(handJson));

  /// The hands-table row for a canonical hand JSON. The columns are derived
  /// from the JSON every time (never trusted from elsewhere — e.g. a backup).
  static Map<String, Object?> _handRow(Map<String, dynamic> handJson) {
    final results = handJson['results'] as Map<String, dynamic>? ?? {};
    final pots = results['pots'] as List<dynamic>? ?? [];
    return {
      'hand_id': handJson['hand_id'],
      'session_id': handJson['session']['session_id'],
      'captured_at':
          DateTime.parse(handJson['captured_at'] as String).millisecondsSinceEpoch,
      'hero_net': results['hero_net'],
      // Total across main + side pots (as played — uncalled excess excluded).
      'pot': pots.isNotEmpty
          ? pots.fold<int>(0, (a, p) => a + (p['amount'] as int? ?? 0))
          : null,
      'marked':
          (handJson['meta']?['marked_for_review'] as bool? ?? false) ? 1 : 0,
      // The JSON is authoritative; this column just mirrors it for list queries.
      'is_spot': (handJson['meta']?['complete'] == false) ? 1 : 0,
      'json': jsonEncode(handJson),
    };
  }

  Future<List<Map<String, dynamic>>> handsForSession(String sessionId) async {
    return (await db).query(
      'hands',
      columns: [
        'hand_id', 'captured_at', 'hero_net', 'pot', 'marked', 'is_spot', 'json'
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

  // -------------------------------------------------------------- backup

  /// Everything on this device as a backup document (see `tracker/backup.dart`).
  Future<Map<String, dynamic>> exportAll() async {
    final d = await db;
    final tracker = await d.query('tracker_sessions', orderBy: 'created_at');
    final sessions = await d.query('sessions', orderBy: 'created_at');
    final hands =
        await d.query('hands', columns: ['json'], orderBy: 'captured_at');
    return buildBackup(
      trackerSessions: [for (final r in tracker) Session.fromRow(r)],
      handSessions: [for (final r in sessions) HandSession.fromRow(r)],
      hands: [
        for (final r in hands)
          jsonDecode(r['json'] as String) as Map<String, dynamic>
      ],
    );
  }

  /// Merge a parsed backup in. Anything already on the device (same id) is
  /// kept as-is — restoring never overwrites local edits. One transaction, so a
  /// bad record leaves the store untouched.
  Future<ImportSummary> importBackup(BackupData b) async {
    final d = await db;
    var tAdded = 0, sAdded = 0, hAdded = 0;
    await d.transaction((txn) async {
      for (final s in b.trackerSessions) {
        final n = await txn.insert('tracker_sessions', s.toRow(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (n != 0) tAdded++;
      }
      for (final s in b.handSessions) {
        final n = await txn.insert('sessions', s.toRow(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (n != 0) sAdded++;
      }
      for (final h in b.hands) {
        final n = await txn.insert('hands', _handRow(h),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (n != 0) hAdded++;
      }
    });
    return ImportSummary(
      trackerAdded: tAdded,
      trackerSkipped: b.trackerSessions.length - tAdded,
      handSessionsAdded: sAdded,
      handSessionsSkipped: b.handSessions.length - sAdded,
      handsAdded: hAdded,
      handsSkipped: b.hands.length - hAdded,
    );
  }
}
