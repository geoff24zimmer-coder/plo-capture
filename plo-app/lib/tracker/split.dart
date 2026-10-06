/// Splitting pre-2026-10-06 data into the two separate stores. Pure Dart, so
/// the rules are unit-tested and shared by the database migration and by
/// restoring an old (version 1) backup.
///
/// Back then one session record carried both a sitting's logged hands and its
/// tracker result. Now the session tracker (results) and hand logging are
/// separate and never intermingle, so each old record goes where its data is:
///
/// - Its result — buy-in, cash-out, notes, MTT finish, or a non-PLO4 game —
///   becomes a tracker session (same id, times, stakes and venue).
/// - If it has hands (or is a live or result-less PLO4 record, so hands may
///   follow) it stays a hand session; hands keep pointing at it by id.
/// - A record that was only ever a result (logged in the tracker, no hands) is
///   not kept as an empty hand session.
library;

import '../models/hand_session.dart';
import '../models/session.dart';

({List<Session> tracker, List<HandSession> handLogs}) splitLegacySessions(
  Iterable<Map<String, dynamic>> rows, {
  required Set<String> withHands,
}) {
  final tracker = <Session>[];
  final handLogs = <HandSession>[];
  for (final r in rows) {
    final s = Session.fromRow(r);
    final hasResult = s.buyIn != null ||
        s.cashOut != null ||
        s.notes.isNotEmpty ||
        s.mttFinish != null ||
        s.mttEntrants != null ||
        s.game != 'plo4';
    if (hasResult) tracker.add(s);
    // Anything with hands stays (never orphan a hand); otherwise a live or
    // result-less PLO4 record is still a hand session.
    final keepHands = withHands.contains(s.id) ||
        (s.game == 'plo4' && (s.isActive || !hasResult));
    if (keepHands) handLogs.add(HandSession.fromRow(r));
  }
  return (tracker: tracker, handLogs: handLogs);
}
