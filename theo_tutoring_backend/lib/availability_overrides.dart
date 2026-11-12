import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/db_row.dart';

/// The tutor's one-off date changes (tutavailabilityoverride) from [from]
/// through [through], oldest first.
Future<List<AvailabilityOverride>> loadAvailabilityOverrides(
  MySQLConnection conn,
  int tutorId, {
  required BookingDate from,
  required BookingDate through,
}) async {
  final result = await conn.execute(
    '''
      SELECT DATE_FORMAT(`Date`, '%Y-%m-%d') AS OverrideDate,
        CAST(StartTime AS CHAR) AS StartTime,
        CAST(EndTime AS CHAR) AS EndTime
      FROM tutavailabilityoverride
      WHERE TutorID = :tutorId AND `Date` BETWEEN :fromDate AND :throughDate
      ORDER BY `Date`, StartTime
      ''',
    {'tutorId': tutorId, 'fromDate': from.iso, 'throughDate': through.iso},
  );

  final byDate = <String, List<AvailabilityOverride>>{};
  for (final row in result.rows) {
    final override = _parseOverride(
      row.reqStr('OverrideDate'),
      row.str('StartTime'),
      row.str('EndTime'),
    );
    (byDate[override.date.iso] ??= []).add(override);
  }

  final normalized = <AvailabilityOverride>[];
  for (final overrides in byDate.values) {
    final closures = overrides.where((o) => o.isDayOff).toList();
    if (closures.isNotEmpty) {
      if (closures.length != overrides.length) {
        throw const FormatException(
          'A full-day closure cannot coexist with custom override times.',
        );
      }
      normalized.add(closures.first);
      continue;
    }

    final windows =
        overrides
            .map((o) => (start: o.startMinutes!, end: o.endMinutes!))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    var start = windows.first.start;
    var end = windows.first.end;
    for (final window in windows.skip(1)) {
      if (window.start <= end) {
        if (window.end > end) end = window.end;
      } else {
        normalized.add(
          AvailabilityOverride(
            date: overrides.first.date,
            startMinutes: start,
            endMinutes: end,
          ),
        );
        start = window.start;
        end = window.end;
      }
    }
    normalized.add(
      AvailabilityOverride(
        date: overrides.first.date,
        startMinutes: start,
        endMinutes: end,
      ),
    );
  }
  return normalized;
}

AvailabilityOverride _parseOverride(String date, String? start, String? end) {
  if ((start == null) != (end == null)) {
    throw const FormatException(
      'Override times must both be null or both set.',
    );
  }
  final startMinutes = start == null ? null : parseClockTime(start);
  final endMinutes = end == null ? null : parseClockTime(end);
  if (startMinutes != null &&
      endMinutes != null &&
      startMinutes >= endMinutes) {
    throw const FormatException('Override end time must be after start time.');
  }
  return AvailabilityOverride(
    date: BookingDate.parse(date),
    startMinutes: startMinutes,
    endMinutes: endMinutes,
  );
}
