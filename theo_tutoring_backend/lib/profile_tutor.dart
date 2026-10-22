import 'dart:io'; // stderr

import 'package:mysql_client/exception.dart'; // MySQLServerException
import 'package:mysql_client/mysql_client.dart'; // gives us the MySQLConnection type
import 'package:theo_tutoring_backend/header_tutor.dart';
import 'package:theo_tutoring_backend/session_rate.dart'; // current rate

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
    FROM TutorProfile
    WHERE TutorID = :tutorId
    ''',
    {'tutorId': tutorId}, // value for :tutorId (prevents SQL injection)
  );

  if (result.rows.isEmpty) return null; // no such tutor

  final data = result.rows.first.assoc(); // first row as a column -> value map

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
    FROM TutorSubjects ts
    JOIN Subjects s ON s.subjectId = ts.SubjectID
    WHERE ts.TutorID = :tutorId
    ORDER BY s.subjectName
    ''',
    {'tutorId': tutorId},
  );
  return [
    for (final row in result.rows)
      {
        'subjectId': int.parse(row.colByName('subjectId')!),
        'subjectName': row.colByName('subjectName'),
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
    FROM Qualification
    WHERE TutorID = :tutorId
    ORDER BY QualificationID
    ''',
    {'tutorId': tutorId},
  );
  return [
    for (final row in result.rows)
      {
        'qualificationId': int.parse(row.colByName('QualificationID')!),
        'degree': row.colByName('Degree'),
        'institution': row.colByName('Institution'),
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
  final availability = await getTutorAvailability(conn, tutorId);

  // Periods with an upcoming booking cannot be unticked (business rule 12),
  // so the app shows them as locked.
  final bookings = await getUpcomingBookings(conn, tutorId);
  for (final day in availability) {
    final ticked = [
      for (final slot in day['slots'] as List<Map<String, String>>)
        slot['period']!,
    ];
    day['locked'] = lockedPeriods(day['day'] as String, ticked, bookings);
  }

  return {
    ...header, // tutorId, name, profilePhotoUrl
    'sessionRate': sessionRate, // fixed by the admin, read-only
    'about': about, // bio text (null if not written yet)
    'subjects': subjects, // [{subjectId, subjectName}]
    'qualifications': qualifications, // [{qualificationId, degree, ...}]
    'availability': availability, // the Mon-Sat grid
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
    UPDATE `User` u
    JOIN TutorProfile tp ON tp.UserID = u.UserId
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
    UPDATE `User` u
    JOIN TutorProfile tp ON tp.UserID = u.UserId
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
    UPDATE TutorProfile
    SET Bio = :about
    WHERE TutorID = :tutorId
    ''',
    {
      'about': cleaned.isEmpty ? null : cleaned, // NULL when nothing written
      'tutorId': tutorId,
    },
  );
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
  final bookings = await getUpcomingBookings(conn, tutorId);
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

  await conn.execute('START TRANSACTION'); // all or nothing
  try {
    await conn.execute(
      'DELETE FROM TutAvailability WHERE TutorID = :tutorId', // remove the old grid
      {'tutorId': tutorId},
    );
    final params = <String, dynamic>{}; // values for the placeholders
    final values = <String>[]; // one "(...)" group per row
    for (var i = 0; i < rows.length; i++) {
      values.add('(:t$i, :d$i, :s$i, :e$i)'); // placeholders for row i
      params['t$i'] = tutorId;
      params['d$i'] = rows[i].day;
      params['s$i'] = _toTime(rows[i].start);
      params['e$i'] = _toTime(rows[i].end);
    }
    await conn.execute(
      'INSERT INTO TutAvailability (TutorID, Day, StartTime, end_Time) '
      'VALUES ${values.join(', ')}', // insert the new grid in one go
      params,
    );
    await conn.execute('COMMIT'); // keep the changes
  } catch (e) {
    await conn.execute('ROLLBACK'); // undo everything if anything failed
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
  return int.parse(p[0]) * 60 + int.parse(p[1]); // hours * 60 + minutes
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
  final v = raw.trim().toLowerCase(); // ignore spaces and letter case
  for (final d in _allDays) {
    if (d.toLowerCase() == v || d.substring(0, 3).toLowerCase() == v) return d;
  }
  return null; // not a weekday
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
      if (!chosen.contains(p.key)) continue; // not ticked
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
            (b) =>
                b.day == day && b.start < p.value[1] && b.end > p.value[0],
          ))
        p.key,
  ];
}

// The tutor's saved time ranges, straight from TutAvailability.
Future<List<DayRange>> _loadRanges(MySQLConnection conn, int tutorId) async {
  final result = await conn.execute(
    '''
    SELECT Day, StartTime, end_Time
    FROM TutAvailability
    WHERE TutorID = :tutorId
    ''',
    {'tutorId': tutorId}, // value for :tutorId (prevents SQL injection)
  );
  final ranges = <DayRange>[];
  for (final row in result.rows) {
    final r = row.assoc(); // row as a column -> value map
    final day = _fullDayName(r['Day'] ?? ''); // normalise "Mon" -> "Monday"
    if (day == null) continue; // skip rows with an unknown day
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
    FROM Booking
    WHERE TutorID = :tutorId
      AND Status IN ('Pending', 'Accepted', 'Confirmed', 'Postponed')
      AND (`Date` > CURDATE() OR (`Date` = CURDATE() AND EndTime > CURTIME()))
    ''',
    {'tutorId': tutorId},
  );
  final bookings = <UpcomingBooking>[];
  for (final row in result.rows) {
    final r = row.assoc();
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
