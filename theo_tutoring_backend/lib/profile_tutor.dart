import 'dart:io';

import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/availability_overrides.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/header_tutor.dart';
import 'package:theo_tutoring_backend/sa_time.dart';
import 'package:theo_tutoring_backend/session_rate.dart';

// ---------------------------------------------------------------------------
// TUTOR PROFILE PAGE: BACKEND
// Boxes: the tutor profile box (photo + name + fixed session rate), About Me,
// Subjects, Qualifications and the Availability grid.
// ---------------------------------------------------------------------------

// Loads the "About Me" text from TutorProfile.Bio.
Future<String?> getTutorAbout(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    '''
    SELECT Bio
    FROM tutorprofile
    WHERE TutorID = :tutorId
    ''',
    {'tutorId': tutorId},
  );

  if (result.rows.isEmpty) return null; // no such tutor

  final data = result.rows.first.textAssoc();

  return data['Bio']; // null if the tutor hasn't written a bio yet
}

// Subjects box: the subjects this tutor teaches (TutorSubjects -> Subjects).
Future<List<Map<String, dynamic>>> getTutorSubjects(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    '''
    SELECT s.subjectId, s.subjectName
    FROM tutorsubjects ts
    JOIN subjects s ON s.subjectId = ts.SubjectID
    WHERE ts.TutorID = :tutorId
    ORDER BY s.subjectName
    ''',
    {'tutorId': tutorId},
  );
  return [
    for (final row in result.rows)
      {
        'subjectId': int.parse(row.reqStr('subjectId')),
        'subjectName': row.str('subjectName'),
      },
  ];
}

// Qualifications box: every Degree + Institution the tutor added.
Future<List<Map<String, dynamic>>> getTutorQualifications(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    '''
    SELECT QualificationID, Degree, Institution
    FROM qualification
    WHERE TutorID = :tutorId
    ORDER BY QualificationID
    ''',
    {'tutorId': tutorId},
  );
  return [
    for (final row in result.rows)
      {
        'qualificationId': int.parse(row.reqStr('QualificationID')),
        'degree': row.str('Degree'),
        'institution': row.str('Institution'),
      },
  ];
}

// The fixed session rate set by the administrator (read-only for tutors).
// Stored in PlatformSettings.TutoringRate (lib/session_rate.dart). Returns
// null if no rate is set yet, or if the table does not exist on this database.
Future<double?> getSessionRate(MySQLConnection conn) async {
  try {
    // null until the admin sets a rate
    return double.tryParse(await getCurrentSessionRate(conn) ?? '');
  } on MySQLServerException catch (e) {
    stderr.writeln('Could not read the session rate: ${e.message}');
    return null; // the rest of the profile page still loads
  }
}

// The rating under the tutor's name: TutorProfile.AveRate (kept up to date
// when a review is added) and how many reviews it is based on.
Future<({double average, int count})> getTutorRating(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    '''
    SELECT tp.AveRate,
           (SELECT COUNT(*) FROM reviews r WHERE r.TutorId = tp.TutorID)
             AS ReviewCount
    FROM tutorprofile tp
    WHERE tp.TutorID = :tutorId
    ''',
    {'tutorId': tutorId},
  );
  if (result.rows.isEmpty) return (average: 0.0, count: 0);
  final row = result.rows.first.textAssoc();
  return (
    average: double.tryParse(row['AveRate'] ?? '') ?? 0.0, // "4.50" -> 4.5
    count: int.tryParse(row['ReviewCount'] ?? '') ?? 0,
  );
}

// Google Meet card: true once the tutor has a Meet room saved
// (TutorProfile.MeetLink, lib/google_meet.dart). The link itself stays off
// the Profile page.
Future<bool> getTutorMeetConnected(MySQLConnection conn, int tutorId) async {
  final result = await conn.execute(
    '''
    SELECT MeetLink
    FROM tutorprofile
    WHERE TutorID = :tutorId
    ''',
    {'tutorId': tutorId},
  );
  if (result.rows.isEmpty) return false;
  return (result.rows.first.str('MeetLink') ?? '').isNotEmpty;
}

// ONE call for the whole Profile page.
// Returns null if the tutor doesn't exist.
Future<Map<String, dynamic>?> getTutorProfilePage(
  MySQLConnection conn,
  int tutorId,
) async {
  // Name + photo (same shared function every tutor page uses)
  final header = await getTutorHeader(conn, tutorId);
  if (header == null) return null; // no such tutor

  final about = await getTutorAbout(conn, tutorId);
  final subjects = await getTutorSubjects(conn, tutorId);
  final qualifications = await getTutorQualifications(conn, tutorId);
  final sessionRate = await getSessionRate(conn);
  final rating = await getTutorRating(conn, tutorId);
  final meetConnected = await getTutorMeetConnected(conn, tutorId);
  final lockedSubjects = await getLockedSubjectIds(conn, tutorId);
  final availability = await getTutorAvailability(conn, tutorId);

  // Periods with an upcoming booking cannot be unticked (business rule 12),
  // so the app shows them as locked.
  final bookings = await getUpcomingBookings(conn, tutorId);
  final weeklyBookings = await _bookingsOnWeeklyHours(conn, tutorId, bookings);
  for (final day in availability) {
    final ticked = [
      for (final slot in day['slots'] as List<Map<String, String>>)
        slot['period']!,
    ];
    day['locked'] = lockedPeriods(
      day['day'] as String,
      ticked,
      weeklyBookings,
    );
  }
  final calendar = await getAvailabilityCalendar(
    conn,
    tutorId,
    bookings: bookings,
  );

  return {
    ...header, // tutorId, name, profilePhotoUrl
    'sessionRate': sessionRate, // fixed by the admin, read-only
    'averageRating': rating.average, // 0 until the first review
    'reviewCount': rating.count,
    'about': about, // bio text (null if not written yet)
    'meetConnected': meetConnected, // Google Meet card: Connect or Reconnect
    'subjects': subjects, // [{subjectId, subjectName}]
    // subjects with an upcoming booking: shown locked, cannot be removed
    'lockedSubjectIds': lockedSubjects.toList()..sort(),
    'qualifications': qualifications, // [{qualificationId, degree, ...}]
    'availability': availability, // the Mon-Sat grid
    // the month calendar: date changes and booked lessons, 90 days ahead
    'availabilityCalendar': calendar,
  };
}

// ============================== UPDATE =====================================

// Pencil next to the name.
// The name is stored in User.Name (VARCHAR(100), NOT NULL), so we reach the
// User row through TutorProfile.UserID.
// Throws ArgumentError if the name is empty or longer than 100 characters.
Future<void> updateTutorName(
  MySQLConnection conn,
  int tutorId,
  String name,
) async {
  final cleaned = name.trim();

  if (cleaned.isEmpty) {
    throw ArgumentError('Name cannot be empty.');
  }
  if (cleaned.length > 100) {
    throw ArgumentError('Name must be 100 characters or less.');
  }

  await conn.execute(
    '''
    UPDATE `user` u
    JOIN tutorprofile tp ON tp.UserID = u.UserId
    SET u.Name = :name
    WHERE tp.TutorID = :tutorId
    ''',
    {'name': cleaned, 'tutorId': tutorId},
  );
}

// Camera badge on the photo.
// This only saves the photo URL in User.ProfilePhoto (VARCHAR(255)).
// Uploading the image file itself (to wherever you host images) happens
// before this, and gives you the URL to pass in here.
// Throws ArgumentError if the URL is empty or longer than 255 characters.
Future<void> updateTutorPhoto(
  MySQLConnection conn,
  int tutorId,
  String photoUrl,
) async {
  final cleaned = photoUrl.trim();

  if (cleaned.isEmpty) {
    throw ArgumentError('Photo URL cannot be empty.');
  }
  if (cleaned.length > 255) {
    throw ArgumentError('Photo URL must be 255 characters or less.');
  }

  await conn.execute(
    '''
    UPDATE `user` u
    JOIN tutorprofile tp ON tp.UserID = u.UserId
    SET u.ProfilePhoto = :photoUrl
    WHERE tp.TutorID = :tutorId
    ''',
    {'photoUrl': cleaned, 'tutorId': tutorId},
  );
}

// Pencil on the About Me box.
// Saved in TutorProfile.Bio (TEXT). An empty bio is stored as NULL.
Future<void> updateTutorAbout(
  MySQLConnection conn,
  int tutorId,
  String about,
) async {
  final cleaned = about.trim();

  await conn.execute(
    '''
    UPDATE tutorprofile
    SET Bio = :about
    WHERE TutorID = :tutorId
    ''',
    {
      'about': cleaned.isEmpty ? null : cleaned, // NULL when nothing written
      'tutorId': tutorId,
    },
  );
}

// ── Subjects box: "+ Add Subject" and removing a subject ─────────────────────

/// Most subjects a tutor can teach (the same limit as registration Step 2).
const maxTutorSubjects = 10;

/// Thrown when the new subject list would drop a subject that still has an
/// upcoming booking. The route turns it into a 409.
class SubjectInUseException implements Exception {
  /// Creates the exception.
  const SubjectInUseException(this.message);

  /// Message the app shows the tutor.
  final String message;

  @override
  String toString() => message;
}

/// Reads {"subjectIds": [3, 5]}: positive whole numbers, duplicates removed,
/// at least one and at most [maxTutorSubjects].
/// Throws a FormatException (turned into a 400) for anything else.
List<int> parseTutorSubjectIds(Object? value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException('Please keep at least one subject.');
  }
  final ids = <int>{};
  for (final item in value) {
    if (item is! int || item <= 0) {
      throw const FormatException(
        'Subject IDs must be positive whole numbers.',
      );
    }
    ids.add(item);
  }
  if (ids.length > maxTutorSubjects) {
    throw const FormatException(
      'You can teach up to $maxTutorSubjects subjects.',
    );
  }
  return ids.toList();
}

/// Subjects that still have a booking holding the tutor's time (requested,
/// accepted, confirmed or postponed, and not finished). They cannot be
/// removed, so the app shows them as locked.
Future<Set<int>> getLockedSubjectIds(MySQLConnection conn, int tutorId) async {
  final result = await conn.execute(
    '''
    SELECT DISTINCT SubjectID
    FROM booking
    WHERE TutorID = :tutorId
      AND Status IN ('Pending', 'Accepted', 'Confirmed', 'Postponed')
      AND (`Date` > $saTodaySql OR (`Date` = $saTodaySql AND EndTime > $saClockSql))
    ''',
    {'tutorId': tutorId},
  );
  return {
    for (final row in result.rows) int.parse(row.reqStr('SubjectID')),
  };
}

/// Replaces the subjects the tutor teaches with [subjectIds], in one
/// transaction. Throws a FormatException if a subject does not exist and a
/// [SubjectInUseException] if a subject with an upcoming booking is removed.
Future<void> updateTutorSubjects(
  MySQLConnection conn,
  int tutorId,
  List<int> subjectIds,
) async {
  final params = <String, dynamic>{
    for (var i = 0; i < subjectIds.length; i++) 's$i': subjectIds[i],
  };
  final placeholders = params.keys.map((k) => ':$k').join(', ');

  // Every subject must be in the Subjects table
  final found = await conn.execute(
    'SELECT subjectId FROM subjects WHERE subjectId IN ($placeholders)',
    params,
  );
  if (found.rows.length != subjectIds.length) {
    throw const FormatException('One or more subjects do not exist.');
  }

  // A subject with an upcoming booking must stay
  final locked = await getLockedSubjectIds(conn, tutorId);
  final removed = locked.difference(subjectIds.toSet());
  if (removed.isNotEmpty) {
    final names = await conn.execute(
      'SELECT subjectName FROM subjects WHERE subjectId = :id',
      {'id': removed.first},
    );
    final name = names.rows.isEmpty
        ? 'That subject'
        : names.rows.first.str('subjectName');
    throw SubjectInUseException(
      '$name has an upcoming booking, so you cannot remove it yet.',
    );
  }

  await conn.transactional((tx) async {
    await tx.execute(
      'DELETE FROM tutorsubjects WHERE TutorID = :tutorId',
      {'tutorId': tutorId},
    );
    for (final id in subjectIds) {
      await tx.execute(
        'INSERT INTO tutorsubjects (TutorID, SubjectID) '
        'VALUES (:tutorId, :subjectId)',
        {'tutorId': tutorId, 'subjectId': id},
      );
    }
  });
}

// Thrown when the new grid would remove a period that has an upcoming
// booking (business rule 12 / FR32). The route turns it into a 409.
class AvailabilityInUseException implements Exception {
  const AvailabilityInUseException(this.message);
  final String message;

  @override
  String toString() => message;
}

// Pencil on the Availability box + Save button.
// selected = {"Monday": ["Morning", "Afternoon"], "Tuesday": ["Evening"], ...}
// The whole grid is replaced by what is sent; a day that is left out has no availability.
// Throws ArgumentError if a day or period name is not recognised or nothing
// is ticked, and AvailabilityInUseException if a booked period is removed.
Future<void> updateTutorAvailability(
  MySQLConnection conn,
  int tutorId,
  Map<String, List<String>> selected,
) async {
  final rows = availabilityRanges(selected); // validates, then merges

  // A tutor cannot remove a slot that has an upcoming booking.
  final before = await _loadRanges(conn, tutorId);
  final bookings = await _bookingsOnWeeklyHours(
    conn,
    tutorId,
    await getUpcomingBookings(conn, tutorId),
  );
  final clash = findRemovedBooking(
    before: before,
    after: rows,
    bookings: bookings,
  );
  if (clash != null) {
    throw AvailabilityInUseException(
      'You have an upcoming booking on ${clash.day} ${clash.date} '
      '(${_toClock(clash.start)} - ${_toClock(clash.end)}), '
      'so that time must stay available.',
    );
  }

  await conn.execute('START TRANSACTION');
  try {
    await conn.execute(
      'DELETE FROM tutavailability WHERE TutorID = :tutorId',
      {'tutorId': tutorId},
    );
    final params = <String, dynamic>{};
    final values = <String>[];
    for (var i = 0; i < rows.length; i++) {
      values.add('(:t$i, :d$i, :s$i, :e$i)');
      params['t$i'] = tutorId;
      params['d$i'] = rows[i].day;
      params['s$i'] = _toTime(rows[i].start);
      params['e$i'] = _toTime(rows[i].end);
    }
    await conn.execute(
      'INSERT INTO tutavailability (TutorID, Day, StartTime, end_Time) '
      'VALUES ${values.join(', ')}',
      params,
    );
    await conn.execute('COMMIT');
  } catch (e) {
    await conn.execute('ROLLBACK');
    rethrow;
  }
}

// ---------------------------------------------------------------------------
// AVAILABILITY BOX (Mon-Sat grid with Morning / Afternoon / Evening rows)
// Saved in TutAvailability. The hours of each row come from the project
// documentation (section 11.1, TutAvailability) and are set ONCE below.
const _weekDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

// DateTime.weekday: 1 = Monday ... 7 = Sunday
const _allDays = [..._weekDays, 'Sunday'];

const _availabilityPeriods = {
  'Morning': [480, 720], // 08:00-12:00
  'Afternoon': [720, 1020], // 12:00-17:00
  'Evening': [1020, 1200], // 17:00-20:00
};

/// A time range on one weekday, in minutes after midnight.
typedef DayRange = ({String day, int start, int end});

/// A booking that has not ended yet.
typedef UpcomingBooking = ({String date, String day, int start, int end});

int _toMinutes(String time) {
  final p = time.split(':'); // ["16", "30", "00"]
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

// 990 -> "16:30:00"
String _toTime(int minutes) => '${_toClock(minutes)}:00';

// 990 -> "16:30"
String _toClock(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

// "Fri" or "friday" -> "Friday" (null if it is not a day)
String? _fullDayName(String raw) {
  final v = raw.trim().toLowerCase();
  for (final d in _allDays) {
    if (d.toLowerCase() == v || d.substring(0, 3).toLowerCase() == v) return d;
  }
  return null;
}

/// Turns the ticked grid into the rows saved in TutAvailability: one row per
/// day, with touching periods merged (Afternoon + Evening -> 12:00-20:00) so
/// Request Details can suggest a window that crosses two periods.
/// Throws ArgumentError if a day or period is unknown or nothing is ticked.
List<DayRange> availabilityRanges(Map<String, List<String>> selected) {
  // check every day and period first, so nothing is saved if one is wrong
  for (final entry in selected.entries) {
    if (!_weekDays.contains(entry.key)) {
      throw ArgumentError(
        'Unknown day: ${entry.key}. Use Monday to Saturday.',
      );
    }
    for (final p in entry.value) {
      if (!_availabilityPeriods.containsKey(p)) {
        throw ArgumentError(
          'Unknown period: $p. Use Morning, Afternoon or Evening.',
        );
      }
    }
  }

  final rows = <DayRange>[];
  for (final day in _weekDays) {
    final chosen = (selected[day] ?? []).toSet(); // periods ticked for this day
    final merged = <List<int>>[];
    for (final p in _availabilityPeriods.entries) {
      if (!chosen.contains(p.key)) continue;
      final start = p.value[0];
      final end = p.value[1];
      if (merged.isNotEmpty && merged.last[1] == start) {
        merged.last[1] = end; // touches the previous period: extend it
      } else {
        merged.add([start, end]); // starts a new range
      }
    }
    for (final m in merged) {
      rows.add((day: day, start: m[0], end: m[1]));
    }
  }

  if (rows.isEmpty) {
    throw ArgumentError('Select at least one time slot you are available.');
  }
  return rows;
}

/// Returns the first upcoming booking that the old availability covered but
/// the new availability no longer covers, or null if the change is allowed.
/// Bookings that were never inside the tutor's availability are ignored.
UpcomingBooking? findRemovedBooking({
  required List<DayRange> before,
  required List<DayRange> after,
  required List<UpcomingBooking> bookings,
}) {
  bool covers(List<DayRange> ranges, UpcomingBooking b) => ranges.any(
    (r) => r.day == b.day && r.start <= b.start && r.end >= b.end,
  );
  for (final b in bookings) {
    if (covers(before, b) && !covers(after, b)) return b;
  }
  return null;
}

/// The ticked periods on [day] that overlap an upcoming booking, so the app
/// can show them as locked.
List<String> lockedPeriods(
  String day,
  List<String> ticked,
  List<UpcomingBooking> bookings,
) {
  return [
    for (final p in _availabilityPeriods.entries)
      if (ticked.contains(p.key) &&
          bookings.any(
            (b) => b.day == day && b.start < p.value[1] && b.end > p.value[0],
          ))
        p.key,
  ];
}

// The tutor's saved time ranges, straight from TutAvailability.
Future<List<DayRange>> _loadRanges(MySQLConnection conn, int tutorId) async {
  final result = await conn.execute(
    '''
    SELECT Day, StartTime, end_Time
    FROM tutavailability
    WHERE TutorID = :tutorId
    ''',
    {'tutorId': tutorId},
  );
  final ranges = <DayRange>[];
  for (final row in result.rows) {
    final r = row.textAssoc();
    final day = _fullDayName(r['Day'] ?? ''); // normalise "Mon" -> "Monday"
    if (day == null) continue;
    ranges.add((
      day: day,
      start: _toMinutes(r['StartTime'] ?? '00:00:00'),
      end: _toMinutes(r['end_Time'] ?? '00:00:00'),
    ));
  }
  return ranges;
}

/// Bookings that still hold the tutor's time: requested, accepted,
/// confirmed or postponed (moved, waiting for the student), and not
/// finished yet.
Future<List<UpcomingBooking>> getUpcomingBookings(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    '''
    SELECT `Date`, StartTime, EndTime
    FROM booking
    WHERE TutorID = :tutorId
      AND Status IN ('Pending', 'Accepted', 'Confirmed', 'Postponed')
      AND (`Date` > $saTodaySql OR (`Date` = $saTodaySql AND EndTime > $saClockSql))
    ''',
    {'tutorId': tutorId},
  );
  final bookings = <UpcomingBooking>[];
  for (final row in result.rows) {
    final r = row.textAssoc();
    final date = DateTime.tryParse(r['Date'] ?? '');
    if (date == null) continue;
    bookings.add((
      date: r['Date']!.substring(0, 10), // "2026-10-24"
      day: _allDays[date.weekday - 1], // "Saturday"
      start: _toMinutes(r['StartTime'] ?? '00:00:00'),
      end: _toMinutes(r['EndTime'] ?? '00:00:00'),
    ));
  }
  return bookings;
}

// Loads the Availability grid, one entry per day (Mon..Sat).
// Used by the tutor's Profile page AND the student's Tutor Profile page.
// A period counts as available when a saved range covers all of it.
Future<List<Map<String, dynamic>>> getTutorAvailability(
  MySQLConnection conn,
  int tutorId,
) async {
  final ranges = await _loadRanges(conn, tutorId);

  final days = <Map<String, dynamic>>[];
  for (final day in _weekDays) {
    final slots = <Map<String, String>>[];
    for (final p in _availabilityPeriods.entries) {
      final covered = ranges.any(
        (r) => r.day == day && r.start <= p.value[0] && r.end >= p.value[1],
      );
      if (covered) {
        slots.add({
          'period': p.key,
          'StartTime': _toTime(p.value[0]),
          'EndTime': _toTime(p.value[1]),
        });
      }
    }
    days.add({
      'day': day, // "Monday"
      'short': day.substring(0, 3), // "Mon"
      'available': slots.isNotEmpty, // student side: blue dot or grey dot
      'slots': slots, // student side: shown when a day is tapped
    });
  }
  return days;
}

// ---------------------------------------------------------------------------
// AVAILABILITY CALENDAR (one-off date changes, under the weekly grid)
// A date can take the day off or have its own hours instead of the weekly
// ones. Saved in TutAvailabilityOverride (migration 007); students see the
// change straight away when they book.
// ---------------------------------------------------------------------------

/// Custom hours on a date must sit inside 06:00-22:00.
const dateHoursEarliest = 6 * 60;

/// See [dateHoursEarliest].
const dateHoursLatest = 22 * 60;

/// What the tutor chose for one date: the usual weekly hours, a day off or
/// their own hours.
enum DateAvailabilityMode { usual, off, custom }

/// A change to one date, read from the request.
typedef DateAvailabilityChange = ({
  BookingDate date,
  DateAvailabilityMode mode,
  List<({int start, int end})> times,
});

/// Reads {"date": "2026-11-13", "mode": "off"}, or "usual", or
/// {"mode": "custom", "times": [{"startTime": "09:00", "endTime": "12:00"}]}.
/// The date must be from [today] up to 90 days ahead; custom times are whole
/// hours inside 06:00-22:00 and are merged when they touch.
/// Throws a FormatException (turned into a 400) for anything else.
DateAvailabilityChange parseDateAvailability(
  Map<String, dynamic> body, {
  required BookingDate today,
}) {
  final rawDate = body['date'];
  final BookingDate date;
  try {
    if (rawDate is! String) throw const FormatException();
    date = BookingDate.parse(rawDate.trim());
  } on FormatException {
    throw const FormatException('date must look like 2026-11-13.');
  }
  final last = today.addDays(maximumBookingDays);
  if (today.daysUntil(date) < 0 || date.daysUntil(last) < 0) {
    throw FormatException('Pick a date from ${today.iso} to ${last.iso}.');
  }

  final mode = DateAvailabilityMode.values
      .where((m) => m.name == body['mode'])
      .firstOrNull;
  if (mode == null) {
    throw const FormatException('mode must be usual, off or custom.');
  }
  if (mode != DateAvailabilityMode.custom) {
    return (date: date, mode: mode, times: const []);
  }

  final rawTimes = body['times'];
  if (rawTimes is! List || rawTimes.isEmpty || rawTimes.length > 24) {
    throw const FormatException('Pick at least one hour, or take the day off.');
  }
  final times = <({int start, int end})>[];
  for (final item in rawTimes) {
    final int start;
    final int end;
    try {
      start = parseClockTime((item as Map)['startTime'] as String);
      end = parseClockTime(item['endTime'] as String);
    } on Object {
      throw const FormatException(
        'Each time must look like {"startTime": "09:00", "endTime": "12:00"}.',
      );
    }
    if (start % 60 != 0 || end % 60 != 0) {
      throw const FormatException('Times must be on the hour, like 09:00.');
    }
    if (start < dateHoursEarliest || end > dateHoursLatest || start >= end) {
      throw const FormatException(
        'Hours must be between 06:00 and 22:00, each ending after it starts.',
      );
    }
    times.add((start: start, end: end));
  }

  // Overlapping or touching times become one range (09-10 + 10-11 -> 09-11)
  times.sort((a, b) => a.start.compareTo(b.start));
  final merged = <({int start, int end})>[];
  for (final t in times) {
    if (merged.isNotEmpty && t.start <= merged.last.end) {
      final previous = merged.removeLast();
      merged.add((
        start: previous.start,
        end: t.end > previous.end ? t.end : previous.end,
      ));
    } else {
      merged.add(t);
    }
  }
  return (date: date, mode: mode, times: merged);
}

/// Saves [change] for one date in a transaction that locks the tutor row.
/// Throws an [AvailabilityInUseException] if a lesson booked that day would
/// lose its time.
Future<void> saveDateAvailability(
  MySQLConnection conn,
  int tutorId,
  DateAvailabilityChange change,
) async {
  final date = change.date;
  await conn.transactional((tx) async {
    await tx.execute(
      'SELECT TutorID FROM tutorprofile WHERE TutorID = :tutorId FOR UPDATE',
      {'tutorId': tutorId},
    );

    final weekly = [
      for (final r in await _loadRanges(tx, tutorId))
        WeeklyAvailability(
          weekday: _allDays.indexOf(r.day) + 1,
          startMinutes: r.start,
          endMinutes: r.end,
        ),
    ];
    final before = availabilityWindowsOn(
      date,
      weekly: weekly,
      overrides: await loadAvailabilityOverrides(
        tx,
        tutorId,
        from: date,
        through: date,
      ),
    );
    final after = switch (change.mode) {
      DateAvailabilityMode.usual => availabilityWindowsOn(date, weekly: weekly),
      DateAvailabilityMode.off => const <AvailabilityWindow>[],
      DateAvailabilityMode.custom => [
        for (final t in change.times)
          (startMinutes: t.start, endMinutes: t.end),
      ],
    };

    bool covers(List<AvailabilityWindow> windows, UpcomingBooking b) =>
        windows.any((w) => w.startMinutes <= b.start && w.endMinutes >= b.end);
    for (final b in await getUpcomingBookings(tx, tutorId)) {
      if (b.date != date.iso) continue;
      if (covers(before, b) && !covers(after, b)) {
        throw AvailabilityInUseException(
          'You have a lesson booked on ${b.day} ${b.date} '
          '(${_toClock(b.start)} - ${_toClock(b.end)}), '
          'so that time must stay open.',
        );
      }
    }

    await tx.execute(
      'DELETE FROM tutavailabilityoverride '
      'WHERE TutorID = :tutorId AND `Date` = :date',
      {'tutorId': tutorId, 'date': date.iso},
    );
    switch (change.mode) {
      case DateAvailabilityMode.usual:
        break; // no rows: the weekly hours apply again
      case DateAvailabilityMode.off:
        await tx.execute(
          'INSERT INTO tutavailabilityoverride (TutorID, `Date`) '
          'VALUES (:tutorId, :date)',
          {'tutorId': tutorId, 'date': date.iso},
        );
      case DateAvailabilityMode.custom:
        for (final t in change.times) {
          await tx.execute(
            'INSERT INTO tutavailabilityoverride '
            '(TutorID, `Date`, StartTime, EndTime) '
            'VALUES (:tutorId, :date, :start, :end)',
            {
              'tutorId': tutorId,
              'date': date.iso,
              'start': _toTime(t.start),
              'end': _toTime(t.end),
            },
          );
        }
    }
  });
}

/// The calendar under the weekly grid, from today to the last bookable date:
/// the dates with their own hours and the lessons booked in that time.
/// [bookings] are the tutor's upcoming bookings when already loaded.
Future<Map<String, dynamic>> getAvailabilityCalendar(
  MySQLConnection conn,
  int tutorId, {
  List<UpcomingBooking>? bookings,
  DateTime? nowUtc,
}) async {
  final today = johannesburgDate(nowUtc ?? DateTime.now().toUtc());
  final last = today.addDays(maximumBookingDays);
  final changes = <String, List<AvailabilityOverride>>{};
  final overrides = await loadAvailabilityOverrides(
    conn,
    tutorId,
    from: today,
    through: last,
  );
  for (final o in overrides) {
    (changes[o.date.iso] ??= []).add(o);
  }
  final booked = bookings ?? await getUpcomingBookings(conn, tutorId);

  return {
    'today': today.iso, // "2026-10-26", Johannesburg time
    'lastDate': last.iso, // students can book up to this date
    'dateChanges': [
      for (final entry in changes.entries)
        {
          'date': entry.key,
          'dayOff': entry.value.every((o) => o.isDayOff),
          'times': [
            for (final o in entry.value)
              if (!o.isDayOff)
                {
                  'startTime': _toClock(o.startMinutes!),
                  'endTime': _toClock(o.endMinutes!),
                },
          ],
        },
    ],
    'bookings': [
      for (final b in booked)
        if (b.date.compareTo(today.iso) >= 0 && b.date.compareTo(last.iso) <= 0)
          {
            'date': b.date,
            'startTime': _toClock(b.start),
            'endTime': _toClock(b.end),
          },
    ],
  };
}

// Bookings on a date with its own hours do not depend on the weekly grid,
// so the grid can change around them.
Future<List<UpcomingBooking>> _bookingsOnWeeklyHours(
  MySQLConnection conn,
  int tutorId,
  List<UpcomingBooking> bookings,
) async {
  if (bookings.isEmpty) return bookings;
  final dates = [for (final b in bookings) b.date]..sort();
  final overrides = await loadAvailabilityOverrides(
    conn,
    tutorId,
    from: BookingDate.parse(dates.first),
    through: BookingDate.parse(dates.last),
  );
  final changed = {for (final o in overrides) o.date.iso};
  return [
    for (final b in bookings)
      if (!changed.contains(b.date)) b,
  ];
}
