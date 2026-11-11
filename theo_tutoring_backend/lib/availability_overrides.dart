import 'dart:io';

import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';

/// MySQL "table doesn't exist": migration 007 has not been run yet.
const _missingTable = 1146;

/// The tutor's one-off date changes (TutAvailabilityOverride) from [from]
/// through [through], oldest first.
///
/// Until migration 007 runs there are none, so every date keeps its usual
/// weekly hours and booking keeps working.
Future<List<AvailabilityOverride>> loadAvailabilityOverrides(
  MySQLConnection conn,
  int tutorId, {
  required BookingDate from,
  required BookingDate through,
}) async {
  final IResultSet result;
  try {
    result = await conn.execute(
      '''
      SELECT DATE_FORMAT(`Date`, '%Y-%m-%d') AS OverrideDate,
        TIME_FORMAT(StartTime, '%H:%i') AS StartTime,
        TIME_FORMAT(EndTime, '%H:%i') AS EndTime
      FROM TutAvailabilityOverride
      WHERE TutorID = :tutorId AND `Date` BETWEEN :fromDate AND :throughDate
      ORDER BY `Date`, StartTime
      ''',
      {'tutorId': tutorId, 'fromDate': from.iso, 'throughDate': through.iso},
    );
  } on MySQLServerException catch (e) {
    if (e.errorCode != _missingTable) rethrow;
    stderr.writeln(
      'TutAvailabilityOverride is missing: run migration 007 to enable '
      'date changes to tutor availability.',
    );
    return const [];
  }

  return [
    for (final row in result.rows)
      AvailabilityOverride(
        date: BookingDate.parse(row.reqStr('OverrideDate')),
        startMinutes: _minutesOrNull(row.str('StartTime')),
        endMinutes: _minutesOrNull(row.str('EndTime')),
      ),
  ];
}

int? _minutesOrNull(String? time) => time == null ? null : parseClockTime(time);
