import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import '../../../lib/database.dart';
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/tutorlanding_session.dart'; // TutorSession
import 'package:theo_tutoring_backend/header_tutor.dart'; // shared tutor name + photo

// GET /TutorLandingpage/requests/<Booking_id>  (opened by the "View" button)
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405); // only GET is allowed
  }
  final bookingId = int.tryParse(id); // the id in the url must be a number
  if (bookingId == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid request id'},
    ); // reject anything else
  }
  final tutor = context.read<TutorSession>(); // who is calling
  final conn = await getConnection(); // shared DB connection (do not close it)

  // tutor name + profile picture, same helper as every tutor page
  final header = await getTutorHeader(conn, tutor.tutorId);
  if (header == null) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Tutor not found'},
    ); // no tutor profile for this session
  }

  // 1. the request itself + the student's details
  final detailResult = await conn.execute(
    'SELECT b.Booking_id, b.Subject, b.Note, b.`Date`, b.StartTime, b.EndTime, '
    'b.Status, b.Link, b.Created_at, '
    'TIME_TO_SEC(TIMEDIFF(b.EndTime, b.StartTime)) DIV 60 AS DurationMinutes, ' // 90 -> "1 hr 30 mins"
    'TIMESTAMPDIFF(MINUTE, b.Created_at, NOW()) AS MinutesAgo, ' // 180 -> "Received 3h ago"
    'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto, ' // student name + photo
    's.InstitutionYear, s.Course ' // student year + "Major & Focus"
    'FROM Booking b '
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // booking -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> user
    'WHERE b.Booking_id = :id AND b.TutorID = :tid', // only this tutor's own request
    {'id': bookingId, 'tid': tutor.tutorId},
  );
  if (detailResult.rows.isEmpty) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Request not found'},
    ); // wrong id, or it belongs to another tutor
  }
  final request = detailResult.rows.first.assoc(); // the request as a map

  // 2. "Your Schedule on This Day": the tutor's other Accepted/Paid sessions on the same date
  final scheduleResult = await conn.execute(
    'SELECT o.Booking_id, o.Subject, o.StartTime, o.EndTime, o.Status, '
    'u.Name AS StudentName, '
    // minutes this session overlaps the request (0 = no overlap)
    'GREATEST(0, (TIME_TO_SEC(LEAST(o.EndTime, t.EndTime)) '
    '- TIME_TO_SEC(GREATEST(o.StartTime, t.StartTime))) DIV 60) AS OverlapMinutes '
    'FROM Booking t ' // t = the request being viewed
    'JOIN Booking o ON o.TutorID = t.TutorID ' // o = the tutor's other bookings
    'AND o.`Date` = t.`Date` ' // same day
    'AND o.Booking_id <> t.Booking_id ' // not the request itself
    'JOIN StudentProfile s ON s.StudentID = o.StudentID '
    'JOIN `User` u ON u.UserId = s.UserID '
    'WHERE t.Booking_id = :id AND t.TutorID = :tid '
    "AND o.Status IN ('Accepted', 'Paid') " // only confirmed sessions block the tutor
    'ORDER BY o.StartTime', // earliest first
    {'id': bookingId, 'tid': tutor.tutorId},
  );
  final sessions = scheduleResult.rows.map((r) {
    final d = r.assoc(); // session as a map
    final overlap = int.parse(d['OverlapMinutes'] ?? '0'); // minutes of overlap
    return {...d, 'conflict': overlap > 0}; // conflict = true when they overlap
  }).toList();
  final hasConflict = sessions.any((s) => s['conflict'] == true); // any clash?

  return Response.json(
    body: {
      'tutor': header, // name + profile picture
      'request': {
        ...request, // every field from the query above
        'RequestRef': 'REQ-${request['Booking_id']}', // "ID #REQ-8842"
      },
      'schedule': {
        'date': request['Date'], // "Tue, Oct 24" heading
        'hasConflict': hasConflict, // true -> show "Schedule Overlap Detected"
        'sessions': sessions, // the day's other sessions (conflict flagged)
      },
    },
  );
}
