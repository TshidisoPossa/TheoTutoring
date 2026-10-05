import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/header_tutor.dart'; // NEW: shared tutor name + photo
import 'package:theo_tutoring_backend/tutorlanding_session.dart'; // TutorSession

//Author Tshidiso Possa
//Request Details page

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405); // only GET is allowed
  }
  final bookingId = int.tryParse(id); // route parameter as int
  if (bookingId == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid id'},
    ); // not a number
  }
  final tutor = context.read<TutorSession>(); // who is calling
  final conn = await getConnection(); // shared DB connection (do not close it)

  // NEW: tutor name + profile picture, same helper as every tutor page
  final header = await getTutorHeader(conn, tutor.tutorId);
  if (header == null) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Tutor not found'},
    ); // no tutor profile for this session
  }

  // Booking details and student profile in one query
  final found = await conn.execute(
    'SELECT b.Booking_id, b.Subject, b.Note, b.`Date`, b.StartTime, b.EndTime, '
    'b.Status, b.Link, b.Created_at, ' // booking details (NEW: Link)
    'TIME_TO_SEC(TIMEDIFF(b.EndTime, b.StartTime)) DIV 60 AS DurationMinutes, ' // NEW: 90 -> "1 hr 30 mins"
    'TIMESTAMPDIFF(MINUTE, b.Created_at, NOW()) AS MinutesAgo, ' // NEW: 180 -> "Received 3h ago"
    'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto, ' // student identity
    's.Course, s.InstitutionYear, s.Subject_of_interest ' // student profile
    'FROM Booking b '
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // booking -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> user
    'WHERE b.Booking_id = :id AND b.TutorID = :tid', // must belong to this tutor
    {'id': bookingId, 'tid': tutor.tutorId},
  );
  if (found.rows.isEmpty) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Request not found'},
    ); // not found or not theirs
  }
  final r = found.rows.first.assoc(); // the booking + student row

  // The tutor's schedule on the same date (Accepted/Paid sessions only)
  final day = await conn.execute(
    'SELECT o.Booking_id, o.Subject, o.StartTime, o.EndTime, '
    'u.Name AS StudentName, ' // NEW: "Advanced Essay Writing • Sarah Jenkins"
    // NEW: minutes this session overlaps the request (0 = no overlap)
    'GREATEST(0, (TIME_TO_SEC(LEAST(o.EndTime, t.EndTime)) '
    '- TIME_TO_SEC(GREATEST(o.StartTime, t.StartTime))) DIV 60) AS OverlapMinutes '
    'FROM Booking t ' // t = the request being viewed
    'JOIN Booking o ON o.TutorID = t.TutorID ' // o = the tutor's other bookings
    'AND o.`Date` = t.`Date` AND o.Booking_id <> t.Booking_id ' // same day, not itself
    'JOIN StudentProfile s ON s.StudentID = o.StudentID '
    'JOIN `User` u ON u.UserId = s.UserID '
    'WHERE t.Booking_id = :id AND t.TutorID = :tid '
    "AND o.Status IN ('Accepted','Paid') " // sessions that block the slot
    'ORDER BY o.StartTime', // earliest first
    {'id': bookingId, 'tid': tutor.tutorId},
  );
  final daySchedule = day.rows.map((row) {
    final s = row.assoc(); // session as a map
    final overlap = int.parse(s['OverlapMinutes'] ?? '0'); // minutes of overlap
    return {
      ...s,
      'conflict': overlap > 0,
    }; // NEW: true when it overlaps the request
  }).toList();
  final hasConflict = daySchedule.any(
    (s) => s['conflict'] == true,
  ); // any clash?

  // NEW: "Suggested Open Window" = free time inside the tutor's availability
  final openWindows =
      <Map<String, String>>[]; // stays empty when there is no clash
  if (hasConflict) {
    final availResult = await conn.execute(
      'SELECT a.StartTime, a.end_Time, '
      '(t.`Date` = CURDATE()) AS IsToday, ' // 1 when the request is for today
      'TIME_TO_SEC(CURTIME()) DIV 60 AS NowMinutes ' // minutes since midnight now
      'FROM Booking t '
      'JOIN TutAvailability a ON a.TutorID = t.TutorID '
      'AND a.Day IN (DAYNAME(t.`Date`), LEFT(DAYNAME(t.`Date`), 3)) ' // "Friday" or "Fri"
      'WHERE t.Booking_id = :id AND t.TutorID = :tid '
      'ORDER BY a.StartTime',
      {'id': bookingId, 'tid': tutor.tutorId},
    );
    final duration = int.parse(
      r['DurationMinutes'] ?? '0',
    ); // length of the request
    final busy = daySchedule
        .map(
          (s) => [
            _toMinutes(s['StartTime']! as String), // busy block start
            _toMinutes(s['EndTime']! as String), // busy block end
          ],
        )
        .toList(); // already ordered by start time

    for (final row in availResult.rows) {
      final a = row.assoc(); // availability row as a map
      final isToday = a['IsToday'] == '1'; // is the request for today?
      final now = int.parse(
        a['NowMinutes'] ?? '0',
      ); // minutes since midnight now
      // today: nothing earlier than 3 hours from now (Deliverable 3 booking rule),
      // rounded up to the next half hour; other days: from midnight
      final earliest = isToday ? ((now + 180 + 29) ~/ 30) * 30 : 0;
      final availEnd = _toMinutes(
        a['end_Time'] ?? '00:00:00',
      ); // availability ends
      var cursor = _toMinutes(
        a['StartTime'] ?? '00:00:00',
      ); // walk from the start
      if (cursor < earliest) cursor = earliest; // skip time that is too soon

      for (final b in busy) {
        if (b[1] <= cursor) continue; // busy block already finished
        if (b[0] >= availEnd)
          break; // busy block starts after availability ends
        if (b[0] - cursor >= duration) {
          openWindows.add({
            'StartTime': _toTime(cursor), // free gap before this busy block
            'EndTime': _toTime(cursor + duration),
          });
        }
        if (b[1] > cursor) cursor = b[1]; // continue after this busy block
      }
      if (availEnd - cursor >= duration) {
        openWindows.add({
          'StartTime': _toTime(cursor), // free time after the last busy block
          'EndTime': _toTime(cursor + duration),
        });
      }
    }
  }

  return Response.json(
    body: {
      'tutor': header, // NEW: name + profile picture
      'booking': {
        'bookingId': r['Booking_id'], // used by Accept / Decline
        'requestRef': 'REQ-${r['Booking_id']}', // NEW: "ID #REQ-8842"
        'subject': r['Subject'], // subject requested
        'note': r['Note'], // student's message
        'date': r['Date'], // session date
        'startTime': r['StartTime'], // session start
        'endTime': r['EndTime'], // session end
        'durationMinutes': r['DurationMinutes'], // NEW
        'status': r['Status'], // Pending / Accepted / Declined / Paid
        'link': r['Link'], // NEW: session link
        'createdAt': r['Created_at'], // when it was requested
        'requestedMinutesAgo': r['MinutesAgo'], // NEW
      },
      'student': {
        'name': r['StudentName'], // student name
        'profilePhoto': r['StudentPhoto'], // student photo
        'course': r['Course'], // course of study
        'institutionYear': r['InstitutionYear'], // year of study
        'subjectOfInterest':
            r['Subject_of_interest'], // subjects they want help with
      },
      'daySchedule':
          daySchedule, // planner schedule for that day (conflict flagged)
      'hasConflict': hasConflict, // true means Accept would return 409
      'openWindows': openWindows
          .take(3)
          .toList(), // NEW: up to 3 suggested windows
    },
  );
}

// NEW helper: "16:30:00" -> 990 (minutes since midnight)
int _toMinutes(String time) {
  final p = time.split(':'); // ["16", "30", "00"]
  return int.parse(p[0]) * 60 + int.parse(p[1]); // hours * 60 + minutes
}

// NEW helper: 990 -> "16:30:00"
String _toTime(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0'); // hours, 2 digits
  final m = (minutes % 60).toString().padLeft(2, '0'); // minutes, 2 digits
  return '$h:$m:00'; // same TIME format as the database
}
