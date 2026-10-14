import 'header_tutor.dart';
import 'package:mysql_client/mysql_client.dart'; // gives us the MySQLConnection type
import 'package:theo_tutoring_backend/header_tutor.dart';
import 'package:mysql_client/mysql_client.dart'; // gives us the MySQLConnection type
import 'package:theo_tutoring_backend/header_tutor.dart';

// ---------------------------------------------------------------------------
// TUTOR PROFILE PAGE: BACKEND
// Boxes covered so far: the tutor profile box (photo + name) and About Me.
// More functions get added to this same file as we build the other boxes.
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

// ONE call for the whole Profile page.
// Your teammate calls this once and gets everything the page needs so far.
// Returns null if the tutor doesn't exist.
Future<Map<String, dynamic>?> getTutorProfilePage(
  MySQLConnection conn,
  int tutorId,
) async {
  // Name + photo (same shared function every tutor page uses)
  final header = await getTutorHeader(conn, tutorId);
  if (header == null) return null; // no such tutor

  final about = await getTutorAbout(conn, tutorId);
  final availability = await getTutorAvailability(conn, tutorId); // NEW line 1
  return {
    ...header, // tutorId, name, profilePhotoUrl
    'about': about, // bio text (null if not written yet)
    'availability': availability, // NEW line 2: the Mon-Sun grid
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

// Pencil on the Availability box + Save button.
// selected = {"Monday": ["Morning", "Afternoon"], "Tuesday": ["Evening"], ...}
// The whole grid is replaced by what is sent; a day that is left out has no availability.
// Throws ArgumentError if a day or period name is not recognised.
Future<void> updateTutorAvailability(
  MySQLConnection conn,
  int tutorId,
  Map<String, List<String>> selected,
) async {
  // check every day and period first, so nothing is saved if one is wrong
  for (final entry in selected.entries) {
    if (!_weekDays.contains(entry.key)) {
      throw ArgumentError('Unknown day: ${entry.key}.');
    }
    for (final p in entry.value) {
      if (!_availabilityPeriods.containsKey(p)) {
        throw ArgumentError('Unknown period: $p.');
      }
    }
  }

  // one row per day, with touching periods merged (Afternoon + Evening -> 12:00-21:00)
  // so Request Details can suggest a window that crosses two periods
  final rows = <List<Object>>[]; // [day, startMinutes, endMinutes]
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
      rows.add([day, m[0], m[1]]);
    }
  }

  await conn.execute('START TRANSACTION'); // all or nothing
  try {
    await conn.execute(
      'DELETE FROM TutAvailability WHERE TutorID = :tutorId', // remove the old grid
      {'tutorId': tutorId},
    );
    if (rows.isNotEmpty) {
      final params = <String, dynamic>{}; // values for the placeholders
      final values = <String>[]; // one "(...)" group per row
      for (var i = 0; i < rows.length; i++) {
        values.add('(:t$i, :d$i, :s$i, :e$i)'); // placeholders for row i
        params['t$i'] = tutorId;
        params['d$i'] = rows[i][0];
        params['s$i'] = _toTime(rows[i][1] as int);
        params['e$i'] = _toTime(rows[i][2] as int);
      }
      await conn.execute(
        'INSERT INTO TutAvailability (TutorID, Day, StartTime, end_Time) '
        'VALUES ${values.join(', ')}', // insert the new grid in one go
        params,
      );
    }
    await conn.execute('COMMIT'); // keep the changes
  } catch (e) {
    await conn.execute('ROLLBACK'); // undo everything if anything failed
    rethrow;
  }
}

// ---------------------------------------------------------------------------
// AVAILABILITY BOX (Mon-Sun grid with Morning / Afternoon / Evening rows)
// Saved in TutAvailability. The hours of each row are set ONCE in the table below.
const _weekDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _availabilityPeriods = {
  'Morning': [480, 720],
  'Afternoon': [720, 1020],
  'Evening': [1020, 1260],
};

int _toMinutes(String time) {
  final p = time.split(':'); // ["16", "30", "00"]
  return int.parse(p[0]) * 60 + int.parse(p[1]); // hours * 60 + minutes
}

// 990 -> "16:30:00"
String _toTime(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m:00';
}

// "Fri" or "friday" -> "Friday" (null if it is not a day)
String? _fullDayName(String raw) {
  final v = raw.trim().toLowerCase(); // ignore spaces and letter case
  for (final d in _weekDays) {
    if (d.toLowerCase() == v || d.substring(0, 3).toLowerCase() == v) return d;
  }
  return null; // not a weekday
}

// Loads the Availability grid, one entry per day (Mon..Sun).
// Used by the tutor's Profile page AND the student's Tutor Profile page.
Future<List<Map<String, dynamic>>> getTutorAvailability(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    '''
    SELECT Day, StartTime, end_Time
    FROM TutAvailability
    WHERE TutorID = :tutorId
    ''',
    {'tutorId': tutorId}, // value for :tutorId (prevents SQL injection)
  );

  // group the saved time ranges by day: {"Monday": [[480, 1260]], ...}
  final ranges = <String, List<List<int>>>{};
  for (final row in result.rows) {
    final r = row.assoc(); // row as a column -> value map
    final day = _fullDayName(r['Day'] ?? ''); // normalise "Mon" -> "Monday"
    if (day == null) continue; // skip rows with an unknown day
    ranges.putIfAbsent(day, () => []).add([
      _toMinutes(r['StartTime'] ?? '00:00:00'),
      _toMinutes(r['end_Time'] ?? '00:00:00'),
    ]);
  }

  final days = <Map<String, dynamic>>[];
  for (final day in _weekDays) {
    final slots = <Map<String, String>>[];
    for (final p in _availabilityPeriods.entries) {
      final covered = (ranges[day] ?? []).any(
        (r) => r[0] <= p.value[0] && r[1] >= p.value[1],
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
