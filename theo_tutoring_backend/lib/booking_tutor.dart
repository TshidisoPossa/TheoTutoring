import 'package:mysql_client/mysql_client.dart'; // gives us the MySQLConnection type

// ---------------------------------------------------------------------------
// TUTOR BOOKING DETAILS PAGE: BACKEND
// Opened by the View button on the Schedule page. Shows the session, the
// student, and the recurring pattern when the student booked the same slot
// on the following weeks.
//
// Its Decline button does not cancel the session, it POSTPONES it:
//   the tutor picks a new date and time -> the booking moves there and its
//   status becomes 'Postponed' -> the student accepts or rejects the new time.
//   Accepting puts it back to 'Confirmed' (already paid) or 'Accepted'
//   (not paid yet, the student can now pay). Rejecting cancels it.
// ---------------------------------------------------------------------------

/// Statuses the tutor may postpone from.
const postponableStatuses = {'Pending', 'Confirmed'};

/// Statuses that hold a time slot in the tutor's diary.
const slotHoldingStatuses = ['Pending', 'Accepted', 'Confirmed', 'Postponed'];

// Statuses that count towards a recurring series.
const _seriesStatuses = {'Pending', 'Accepted', 'Confirmed'};

/// Bookings must start at least this long from now (documentation 4.5).
const minimumLeadTime = Duration(hours: 3);

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Thrown when a booking cannot be postponed. Turned into a JSON error.
class PostponeException implements Exception {
  /// Creates the exception.
  const PostponeException(this.statusCode, this.message);

  /// HTTP status to send back.
  final int statusCode;

  /// Message the app shows the tutor.
  final String message;

  @override
  String toString() => 'PostponeException($statusCode): $message';
}

/// The new date and time the tutor picked.
class PostponeSlot {
  /// Creates a slot. [start] and [end] are minutes after midnight.
  const PostponeSlot({
    required this.date,
    required this.start,
    required this.end,
  });

  /// "2026-10-31"
  final String date;

  /// Start, in minutes after midnight (16:00 -> 960).
  final int start;

  /// End, in minutes after midnight.
  final int end;

  /// "16:00:00", the format MySQL TIME columns take.
  String get startTime => '${hhmm(start)}:00';

  /// "17:00:00"
  String get endTime => '${hhmm(end)}:00';
}

/// What the booking looked like before it was postponed.
typedef PostponedBooking = ({
  String previousStatus,
  String previousDate,
  String previousStartTime,
  String previousEndTime,
  String subject,
  String? studentFirebaseUid,
});

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _timePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// Reads { "date": "2026-10-31", "startTime": "16:00", "endTime": "17:00" }.
/// Throws a FormatException (turned into a 400) if anything is missing
/// or wrong.
PostponeSlot parsePostponeSlot(Map<String, dynamic> body) {
  final date = body['date'];
  if (date is! String || !_datePattern.hasMatch(date.trim())) {
    throw const FormatException('date must look like 2026-10-31.');
  }
  final parsed = DateTime.tryParse(date.trim());
  // DateTime.tryParse rolls 2026-02-30 over to March, so compare it back.
  if (parsed == null || _isoDate(parsed) != date.trim()) {
    throw const FormatException('date is not a real calendar date.');
  }

  int time(String key) {
    final value = body[key];
    final match = value is String
        ? _timePattern.firstMatch(value.trim())
        : null;
    if (match == null) {
      throw FormatException('$key must be a 24-hour time like 16:00.');
    }
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  final start = time('startTime');
  final end = time('endTime');
  if (start >= end) {
    throw const FormatException('endTime must be after startTime.');
  }
  return PostponeSlot(date: date.trim(), start: start, end: end);
}

/// True when the tutor's availability ranges for a day cover [start]-[end].
/// Ranges that touch or overlap (08:00-12:00 + 12:00-17:00) are joined first.
bool availabilityCovers(
  List<({int start, int end})> ranges,
  int start,
  int end,
) {
  final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
  var from = -1;
  var to = -1;
  for (final r in sorted) {
    if (r.start <= to) {
      if (r.end > to) to = r.end; // joins the current block
    } else {
      if (from <= start && end <= to) return true;
      from = r.start; // starts a new block
      to = r.end;
    }
  }
  return from <= start && end <= to;
}

/// Keeps the sessions that follow the first one a week apart with no gaps.
/// [sessions] must be sorted by date, the first being the booking on screen.
/// Returns an empty list when there is no second week (not recurring).
List<Map<String, dynamic>> weeklyRun(List<Map<String, dynamic>> sessions) {
  if (sessions.length < 2) return const [];
  final first = DateTime.parse(sessions.first['date'] as String);
  final run = <Map<String, dynamic>>[sessions.first];
  for (final s in sessions.skip(1)) {
    // calendar maths in UTC, so a daylight-saving change cannot shift the day
    final expected = DateTime.utc(
      first.year,
      first.month,
      first.day + 7 * run.length,
    );
    if (s['date'] != _isoDate(expected)) break; // a week was skipped
    run.add(s);
  }
  return run.length < 2 ? const [] : run;
}

/// Everything the booking details page shows, or null if the booking does
/// not exist or belongs to another tutor.
Future<Map<String, dynamic>?> getBookingDetail(
  MySQLConnection conn,
  int tutorId,
  int bookingId,
) async {
  final result = await conn.execute(
    'SELECT b.Booking_id, b.Status, b.`Date`, b.StartTime, b.EndTime, '
    'b.Note, b.Link, b.SubjectID, sj.subjectName AS Subject, '
    'TIME_TO_SEC(TIMEDIFF(b.EndTime, b.StartTime)) DIV 60 AS DurationMinutes, '
    // 180 -> "Received 3h ago"
    'TIMESTAMPDIFF(MINUTE, b.Created_at, NOW()) AS ReceivedMinutesAgo, '
    // 1 once the session has started (it can no longer be postponed)
    'TIMESTAMP(b.`Date`, b.StartTime) <= NOW() AS HasStarted, '
    'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto, '
    'u.AccountStatus AS StudentAccountStatus, '
    's.InstitutionYear, s.Course ' // "Sophomore", "Major & Focus"
    'FROM Booking b '
    'JOIN Subjects sj ON sj.subjectId = b.SubjectID ' // booking -> subject name
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> name + photo
    'WHERE b.Booking_id = :id AND b.TutorID = :tid', // only the tutor's own
    {'id': bookingId, 'tid': tutorId},
  );
  if (result.rows.isEmpty) return null;
  final r = result.rows.first.assoc();

  int? number(String? v) => v == null ? null : int.tryParse(v);
  final status = r['Status'] ?? '';
  final hasStarted = r['HasStarted'] == '1';
  final duration = number(r['DurationMinutes']) ?? 0;

  return {
    'booking': {
      'bookingId': bookingId,
      'reference': 'REQ-$bookingId', // "ID #REQ-8842"
      'status': status,
      'subjectId': number(r['SubjectID']),
      'subject': r['Subject'], // "Calculus"
      'date': r['Date']?.substring(0, 10), // "2026-10-24"
      'startTime': _clock(r['StartTime']), // "16:00"
      'endTime': _clock(r['EndTime']), // "17:00"
      'durationMinutes': duration, // 60 -> "(1 hour)"
      'note': r['Note'], // the student's message (may be null)
      'link': r['Link'], // where the session takes place (may be null)
      'receivedMinutesAgo': number(r['ReceivedMinutesAgo']),
      'hasStarted': hasStarted,
      // shows the Decline (postpone) button
      'canPostpone': postponableStatuses.contains(status) && !hasStarted,
    },
    'student': {
      'name': r['StudentName'],
      'profilePhotoUrl': r['StudentPhoto'], // null if none uploaded
      'year': r['InstitutionYear'], // "Sophomore"
      'course': r['Course'], // "Major & Focus"
      // the blue tick: the student's account is active
      'verified': (r['StudentAccountStatus'] ?? '').toLowerCase() == 'active',
    },
    'recurring': _seriesStatuses.contains(status)
        ? await _getRecurring(conn, tutorId, bookingId, duration)
        : null,
  };
}

// The "Recurring Booking" card: the same student, subject and time slot
// booked on the following weeks. Null when the booking is a one-off.
Future<Map<String, dynamic>?> _getRecurring(
  MySQLConnection conn,
  int tutorId,
  int bookingId,
  int durationMinutes,
) async {
  final result = await conn.execute(
    'SELECT o.Booking_id, o.`Date`, o.Status, o.StartTime, o.EndTime '
    'FROM Booking t ' // t = the booking on screen
    'JOIN Booking o ON o.TutorID = t.TutorID ' // o = it and its later weeks
    'AND o.StudentID = t.StudentID AND o.SubjectID = t.SubjectID '
    'AND o.StartTime = t.StartTime AND o.EndTime = t.EndTime '
    'AND o.`Date` >= t.`Date` '
    'AND MOD(DATEDIFF(o.`Date`, t.`Date`), 7) = 0 ' // same weekday
    'WHERE t.Booking_id = :id AND t.TutorID = :tid '
    "AND o.Status IN ('Pending', 'Accepted', 'Confirmed') "
    'ORDER BY o.`Date`',
    {'id': bookingId, 'tid': tutorId},
  );
  final run = weeklyRun([
    for (final row in result.rows)
      {
        'bookingId': int.parse(row.colByName('Booking_id')!),
        'date': row.colByName('Date')!.substring(0, 10),
        'status': row.colByName('Status'),
        'startTime': _clock(row.colByName('StartTime')),
        'endTime': _clock(row.colByName('EndTime')),
      },
  ]);
  if (run.isEmpty) return null;

  final first = DateTime.parse(run.first['date'] as String);
  return {
    'frequency': 'Weekly',
    'weekday': _weekdays[first.weekday - 1], // "Every Tuesday (Weekly)"
    'startTime': run.first['startTime'],
    'endTime': run.first['endTime'],
    'sessions': [
      for (final s in run)
        {'bookingId': s['bookingId'], 'date': s['date'], 'status': s['status']},
    ],
    'totalSessions': run.length, // "4 Sessions"
    'totalMinutes': run.length * durationMinutes, // 240 -> "4.0 hrs"
  };
}

/// Moves the booking to [slot] and marks it 'Postponed', in one transaction.
/// Throws a [PostponeException] when the move is not allowed.
Future<PostponedBooking> postponeBooking(
  MySQLConnection conn,
  int tutorId,
  int bookingId,
  PostponeSlot slot,
) async {
  return conn.transactional((tx) async {
    // Lock the booking so two taps cannot postpone it twice.
    final found = await tx.execute(
      'SELECT b.Status, b.`Date`, b.StartTime, b.EndTime, '
      'sj.subjectName AS Subject, u.FirebaseUid AS StudentUid, '
      'TIMESTAMP(b.`Date`, b.StartTime) <= NOW() AS HasStarted, '
      'TIMESTAMP(:d, :s) >= NOW() + INTERVAL ${minimumLeadTime.inMinutes} '
      'MINUTE AS FarEnough '
      'FROM Booking b '
      'JOIN Subjects sj ON sj.subjectId = b.SubjectID '
      'JOIN StudentProfile s ON s.StudentID = b.StudentID '
      'JOIN `User` u ON u.UserId = s.UserID '
      'WHERE b.Booking_id = :id AND b.TutorID = :tid '
      'FOR UPDATE OF b',
      {'id': bookingId, 'tid': tutorId, 'd': slot.date, 's': slot.startTime},
    );
    if (found.rows.isEmpty) {
      throw const PostponeException(404, 'Booking not found.');
    }
    final b = found.rows.first.assoc();
    final status = b['Status'] ?? '';

    if (!postponableStatuses.contains(status)) {
      throw const PostponeException(
        409,
        'Only pending or confirmed sessions can be postponed.',
      );
    }
    if (b['HasStarted'] == '1') {
      throw const PostponeException(
        409,
        'This session has already started, so it cannot be postponed.',
      );
    }
    if (b['Date']?.substring(0, 10) == slot.date &&
        b['StartTime'] == slot.startTime &&
        b['EndTime'] == slot.endTime) {
      throw const PostponeException(400, 'Pick a different date or time.');
    }
    if (b['FarEnough'] != '1') {
      throw const PostponeException(
        400,
        'The new time must be at least 3 hours from now.',
      );
    }

    // The new slot must sit inside the tutor's availability for that weekday.
    final weekday = _weekdays[DateTime.parse(slot.date).weekday - 1];
    final ranges = await tx.execute(
      'SELECT StartTime, end_Time FROM TutAvailability '
      'WHERE TutorID = :tid AND Day = :day',
      {'tid': tutorId, 'day': weekday},
    );
    final covered = availabilityCovers(
      [
        for (final row in ranges.rows)
          (
            start: _toMinutes(row.colByName('StartTime')!),
            end: _toMinutes(row.colByName('end_Time')!),
          ),
      ],
      slot.start,
      slot.end,
    );
    if (!covered) {
      throw PostponeException(
        409,
        'You are not available on $weekday from '
        '${hhmm(slot.start)} to ${hhmm(slot.end)}. '
        'Pick a time inside your availability.',
      );
    }

    // ...and must not overlap another session that holds the tutor's time.
    final clashes = await tx.execute(
      'SELECT Booking_id FROM Booking '
      'WHERE TutorID = :tid AND Booking_id <> :id AND `Date` = :d '
      "AND Status IN ('${slotHoldingStatuses.join("', '")}') "
      'AND StartTime < :e AND EndTime > :s '
      'FOR UPDATE',
      {
        'tid': tutorId,
        'id': bookingId,
        'd': slot.date,
        's': slot.startTime,
        'e': slot.endTime,
      },
    );
    if (clashes.rows.isNotEmpty) {
      throw const PostponeException(
        409,
        'That time clashes with another session in your schedule.',
      );
    }

    await tx.execute(
      'UPDATE Booking SET `Date` = :d, StartTime = :s, EndTime = :e, '
      "Status = 'Postponed' WHERE Booking_id = :id",
      {
        'id': bookingId,
        'd': slot.date,
        's': slot.startTime,
        'e': slot.endTime,
      },
    );

    return (
      previousStatus: status,
      previousDate: b['Date']!.substring(0, 10),
      previousStartTime: _clock(b['StartTime'])!,
      previousEndTime: _clock(b['EndTime'])!,
      subject: b['Subject'] ?? '',
      studentFirebaseUid: b['StudentUid'],
    );
  });
}

/// "Fri 24 Oct, 16:00", for notification messages.
String sessionLabel(String date, String startTime) {
  final d = DateTime.parse(date);
  final day = _weekdays[d.weekday - 1].substring(0, 3);
  return '$day ${d.day} ${_shortMonths[d.month - 1]}, $startTime';
}

/// 960 -> "16:00"
String hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

String? _clock(String? v) => v?.substring(0, 5); // "15:00:00" -> "15:00"

int _toMinutes(String time) {
  final parts = time.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
