import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/header_tutor.dart'; // NEW: shared tutor name + photo
import 'package:theo_tutoring_backend/tutorlanding_session.dart';

//Author Tshidiso Possa
//Schedule Page for the tutorLanding page.

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405); // only GET is allowed
  }
  final filter =
      context.request.uri.queryParameters['filter'] ??
      'upcoming'; // default to upcoming sessions

  // Pick the date condition and sort order from fixed strings (no user text goes into the SQL)
  String condition; // extra WHERE condition
  String order; // ORDER BY clause
  switch (filter) {
    case 'upcoming':
      condition =
          'AND (b.`Date` > CURDATE() OR (b.`Date` = CURDATE() AND b.EndTime > CURTIME())) '; // not yet ended
      order = 'ORDER BY b.`Date` ASC, b.StartTime ASC'; // soonest first
    case 'past':
      condition =
          'AND (b.`Date` < CURDATE() OR (b.`Date` = CURDATE() AND b.EndTime <= CURTIME())) '; // already ended
      order = 'ORDER BY b.`Date` DESC, b.StartTime DESC'; // most recent first
    case 'today':
      condition = 'AND b.`Date` = CURDATE() '; // every session today
      order = 'ORDER BY b.StartTime ASC'; // earliest first

    case 'all':
      condition = ''; // no date restriction
      order = 'ORDER BY b.`Date` DESC, b.StartTime DESC'; // most recent first
    default:
      return Response.json(
        statusCode: 400,
        body: {'error': 'Invalid filter'},
      );
  }

  final tutor = context.read<TutorSession>();
  final conn = await getConnection(); // shared DB connection (do not close it)

  // NEW: tutor name + profile picture, same helper as every tutor page
  final header = await getTutorHeader(conn, tutor.tutorId);
  if (header == null) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Tutor not found'},
    ); // no tutor profile for this session
  }

  // NEW: the number on each tab, e.g. Upcoming (5), using the same rules as the list conditions
  final countResult = await conn.execute(
    'SELECT COALESCE(SUM(`Date` > CURDATE() OR (`Date` = CURDATE() AND EndTime > CURTIME())), 0) AS Upcoming, ' // not yet ended
    'COALESCE(SUM(`Date` < CURDATE() OR (`Date` = CURDATE() AND EndTime <= CURTIME())), 0) AS Past, ' // already ended
    'COUNT(*) AS Total ' // everything
    'FROM Booking '
    "WHERE TutorID = :tid AND Status = 'Paid'", // this tutor's confirmed (paid) sessions
    {'tid': tutor.tutorId},
  );
  final c = countResult.rows.first.assoc();

  final result = await conn.execute(
    'SELECT b.Booking_id, b.`Date`, b.StartTime, b.EndTime, b.Subject, b.Link, '
    'TIMESTAMPDIFF(MINUTE, NOW(), TIMESTAMP(b.`Date`, b.StartTime)) AS StartsInMinutes, ' // NEW: 45 -> "Starts in 45m"
    'u.Name AS StudentName ' // who the session is with
    'FROM Booking b '
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // booking -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> user
    "WHERE b.TutorID = :tid AND b.Status = 'Paid' " // this tutor's confirmed (paid) sessions
    '$condition$order', // date filter and sort order
    {'tid': tutor.tutorId},
  );
  return Response.json(
    body: {
      'tutor': header, // NEW: name + profile picture
      'counts': {
        // NEW: tab numbers
        'upcoming': int.parse(c['Upcoming'] ?? '0'),
        'past': int.parse(c['Past'] ?? '0'),
        'all': int.parse(c['Total'] ?? '0'),
      },
      'filter': filter,
      'count': result.rows.length,
      'sessions': result.rows.map((r) => r.assoc()).toList(),
    },
  );
}
