import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import '../../../lib/database.dart'; // getConnection()
import '../../../lib/tutorlanding_session.dart'; // TutorSession

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
    case 'all':
      condition = ''; // no date restriction
      order = 'ORDER BY b.`Date` DESC, b.StartTime DESC'; // most recent first
    default:
      return Response.json(
        statusCode: 400,
        body: {'error': 'Invalid filter'},
      ); // reject anything else
  }

  final tutor = context.read<TutorSession>();
  final conn = await getConnection(); // shared DB connection (do not close it)
  final result = await conn.execute(
    'SELECT b.Booking_id, b.`Date`, b.StartTime, b.EndTime, b.Subject, b.Link, '
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
      'filter': filter, // which filter was applied
      'count': result.rows.length, // number of sessions returned
      'sessions': result.rows
          .map((r) => r.assoc())
          .toList(), // Flutter groups these by Date
    },
  );
}
