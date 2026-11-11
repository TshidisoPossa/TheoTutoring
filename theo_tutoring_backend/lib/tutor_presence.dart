import 'package:mysql_dart/mysql_dart.dart';

// ---------------------------------------------------------------------------
// TUTOR PRESENCE ("Available Now" on the student's Tutor Profile)
// The tutor app pings POST /TutorLandingpage/presence every minute while it
// is open, and every tutor request refreshes TutorProfile.LastActiveAtUtc
// too. Signing out clears it, so the tutor goes offline straight away.
// ---------------------------------------------------------------------------

/// How long after their last ping a tutor still counts as available.
/// Three missed one-minute pings means the app was closed.
const tutorOnlineWindowMinutes = 3;

/// SQL that is 1 when the tutor [alias] is available now, else 0.
String tutorAvailableNowSql(String alias) =>
    '($alias.LastActiveAtUtc IS NOT NULL AND $alias.LastActiveAtUtc >= '
    'UTC_TIMESTAMP(6) - INTERVAL $tutorOnlineWindowMinutes MINUTE)';

/// Records that the tutor is using the app right now.
Future<void> markTutorActive(MySQLConnection connection, int tutorId) async {
  await connection.execute(
    'UPDATE TutorProfile SET LastActiveAtUtc = UTC_TIMESTAMP(6) '
    'WHERE TutorID = :tutorId',
    {'tutorId': tutorId},
  );
}

/// Marks the tutor offline (they signed out).
Future<void> markTutorOffline(MySQLConnection connection, int tutorId) async {
  await connection.execute(
    'UPDATE TutorProfile SET LastActiveAtUtc = NULL WHERE TutorID = :tutorId',
    {'tutorId': tutorId},
  );
}
