/// Whole-device backup + CSV export. Pure Dart (no Flutter, no DB) so the
/// format is unit-testable; `HandStore.exportAll` / `importBackup` do the I/O.
///
/// Browser storage is per-origin and per-device — a cleared cache or a domain
/// move loses everything — so a downloadable backup is the safety net until
/// there's cloud sync. The canonical hand JSON rides along verbatim (it's the
/// source of truth); the hands-table columns are re-derived on import.
library;

import 'dart:convert';

import '../models/hand_session.dart';
import '../models/session.dart';
import 'split.dart';

const backupFormat = 'plo-show-backup';

/// 2: tracker sessions and hand sessions kept apart. 1 (before 2026-10-06):
/// one combined `sessions` list — split on restore (see `split.dart`).
const backupVersion = 2;

Map<String, dynamic> buildBackup({
  required List<Session> trackerSessions,
  required List<HandSession> handSessions,
  required List<Map<String, dynamic>> hands,
  DateTime? now,
}) =>
    {
      'format': backupFormat,
      'version': backupVersion,
      'exported_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'tracker_sessions': [for (final s in trackerSessions) s.toRow()],
      'hand_sessions': [for (final s in handSessions) s.toRow()],
      'hands': hands,
    };

class BackupData {
  final List<Session> trackerSessions;
  final List<HandSession> handSessions;
  final List<Map<String, dynamic>> hands;
  final DateTime? exportedAt;
  const BackupData({
    required this.trackerSessions,
    required this.handSessions,
    required this.hands,
    this.exportedAt,
  });
}

class ImportSummary {
  final int trackerAdded, trackerSkipped;
  final int handSessionsAdded, handSessionsSkipped;
  final int handsAdded, handsSkipped;
  const ImportSummary({
    required this.trackerAdded,
    required this.trackerSkipped,
    required this.handSessionsAdded,
    required this.handSessionsSkipped,
    required this.handsAdded,
    required this.handsSkipped,
  });

  int get skipped => trackerSkipped + handSessionsSkipped + handsSkipped;
}

List<Map<String, dynamic>> _rows(Object? raw, String what) {
  if (raw is! List) throw FormatException('Backup is missing its $what.');
  try {
    return [for (final r in raw) Map<String, dynamic>.from(r as Map)];
  } catch (_) {
    throw FormatException('Backup contains an unreadable $what entry.');
  }
}

T _parse<T>(T Function() f, String what) {
  try {
    return f();
  } catch (_) {
    throw FormatException('Backup contains an unreadable $what.');
  }
}

/// Parse and validate a backup file. Throws [FormatException] with a
/// user-presentable message on anything that isn't a readable backup — the
/// import is all-or-nothing, so validation happens before any write.
BackupData parseBackup(String text) {
  final Object? doc;
  try {
    doc = jsonDecode(text);
  } on FormatException {
    throw const FormatException('Not a PLO Show backup (not JSON).');
  }
  if (doc is! Map<String, dynamic> || doc['format'] != backupFormat) {
    throw const FormatException('Not a PLO Show backup file.');
  }
  final version = doc['version'];
  if (version is! int || version > backupVersion) {
    throw const FormatException(
        'This backup is from a newer version of the app — update first.');
  }

  final hands = <Map<String, dynamic>>[];
  for (final h in _rows(doc['hands'], 'hands')) {
    if (h['hand_id'] is! String ||
        h['captured_at'] is! String ||
        DateTime.tryParse(h['captured_at'] as String) == null ||
        (h['session'] as Map?)?['session_id'] is! String) {
      throw const FormatException('Backup contains an unreadable hand.');
    }
    hands.add(h);
  }
  final handSessionIds = {
    for (final h in hands) h['session']['session_id'] as String
  };

  final List<Session> tracker;
  final List<HandSession> handSessions;
  if (version == 1) {
    final rows = _rows(doc['sessions'], 'sessions');
    final split = _parse(
        () => splitLegacySessions(rows, withHands: handSessionIds), 'session');
    tracker = split.tracker;
    handSessions = split.handLogs;
  } else {
    tracker = [
      for (final r in _rows(doc['tracker_sessions'], 'tracker sessions'))
        _parse(() => Session.fromRow(r), 'tracker session')
    ];
    handSessions = [
      for (final r in _rows(doc['hand_sessions'], 'hand sessions'))
        _parse(() => HandSession.fromRow(r), 'hand session')
    ];
  }

  final known = {for (final s in handSessions) s.id};
  if (!handSessionIds.every(known.contains)) {
    throw const FormatException(
        'Backup contains a hand whose session is missing.');
  }
  return BackupData(
    trackerSessions: tracker,
    handSessions: handSessions,
    hands: hands,
    exportedAt: DateTime.tryParse(doc['exported_at'] as String? ?? ''),
  );
}

// ------------------------------------------------------------------- CSV

const _csvHeader = [
  'date', 'start', 'end', 'hours', 'type', 'game', 'stakes', 'venue', //
  'buy_in', 'cash_out', 'net', 'finish', 'entrants', 'notes',
];

/// One row per session, oldest first, for spreadsheets. Money in dollars;
/// unresolved results are left blank rather than zero.
String sessionsCsv(Iterable<Session> sessions) {
  final rows = [_csvHeader.join(',')];
  final sorted = sessions.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  for (final s in sorted) {
    rows.add([
      _date(s.createdAt),
      _time(s.createdAt),
      s.endedAt == null ? '' : _time(s.endedAt!),
      s.endedAt == null ? '' : s.hours().toStringAsFixed(2),
      s.gameType,
      s.game,
      _cell(s.stakesLabel),
      _cell(s.venue),
      _dollars(s.buyIn),
      _dollars(s.cashOut),
      _dollars(s.net),
      s.mttFinish?.toString() ?? '',
      s.mttEntrants?.toString() ?? '',
      _cell(s.notes),
    ].join(','));
  }
  return '${rows.join('\n')}\n';
}

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
String _dollars(int? cents) =>
    cents == null ? '' : (cents / 100).toStringAsFixed(2);

/// Quote free text; neutralise a leading formula character so a venue like
/// "=HYPERLINK(...)" is shown as text, not evaluated, by spreadsheet apps.
String _cell(String v) {
  var t = v;
  if (t.isNotEmpty && '=+-@'.contains(t[0])) t = "'$t";
  if (t.contains(RegExp(r'[",\n\r]'))) t = '"${t.replaceAll('"', '""')}"';
  return t;
}
