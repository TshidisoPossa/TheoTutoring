import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';

// ---------------------------------------------------------------------------
// FIXED SESSION RATE
// Tutors do not set their own prices: the administrator sets one rate for
// every session, stored in PlatformSettings.TutoringRate (the single settings
// row, SettingsID = 1). Every page that shows or charges the rate reads it
// through this file, so they always agree.
// ---------------------------------------------------------------------------

/// A scalar subquery for the current rate, for use inside other SELECTs,
/// e.g. `SELECT ..., $currentSessionRateSubquery AS HourlyRate FROM ...`.
/// Gives NULL when no rate has been set yet.
const currentSessionRateSubquery =
    '(SELECT ps.TutoringRate FROM platformsettings ps '
    'WHERE ps.SettingsID = 1)';

/// The current rate exactly as MySQL returns it, e.g. "250.00",
/// or null when no rate has been set yet.
Future<String?> getCurrentSessionRate(MySQLConnection connection) async {
  final result = await connection.execute(
    'SELECT $currentSessionRateSubquery AS Amount',
  );
  if (result.rows.isEmpty) return null;
  return result.rows.first.str('Amount');
}
