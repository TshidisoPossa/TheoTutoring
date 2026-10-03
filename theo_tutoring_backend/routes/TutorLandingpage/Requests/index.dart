import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import '../../../lib/database.dart'; // getConnection()
import '../../../lib/tutorlanding_session.dart';
import 'package:theo_tutoring_backend/header_tutor.dart'; // shared tutor name + photo

//auther Tshidiso Possa
//Request Page
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405); // only GET is allowed
  }
  final status =
      context.request.uri.queryParameters['status'] ??
      'Pending'; // default to Pending requests
  const allowed = [
    'Pending',
    'Accepted',
    'Declined',
    'Paid',
  ]; // valid Booking.Status values
  if (!allowed.contains(status)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid status'},
    ); // reject anything else
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

  // NEW: the numbers shown on the tabs, e.g. Pending (3), Accepted (1)
  final countResult = await conn.execute(
    'SELECT Status, COUNT(*) AS Total FROM Booking ' // one row per status
    'WHERE TutorID = :tid GROUP BY Status', // only this tutor's bookings
    {'tid': tutor.tutorId},
  );
  final counts = {
    'pending': 0,
    'accepted': 0,
    'declined': 0,
    'paid': 0,
  }; // start at 0
  for (final row in countResult.rows) {
    final d = row.assoc(); // row as a map
    final key = (d['Status'] ?? '').toLowerCase(); // 'pending', 'accepted'...
    if (counts.containsKey(key))
      counts[key] = int.parse(d['Total']!); // real count
  }

  final result = await conn.execute(
    'SELECT b.Booking_id, b.Subject, b.Note, b.`Date`, b.StartTime, b.EndTime, '
    'b.Status, b.Created_at, '
    'TIME_TO_SEC(TIMEDIFF(b.EndTime, b.StartTime)) DIV 60 AS DurationMinutes, ' // NEW: 90 -> "1.5 hrs"
    'TIMESTAMPDIFF(MINUTE, b.Created_at, NOW()) AS MinutesAgo, ' // NEW: 25 -> "25m ago"
    'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto ' // booking + student name/photo
    'FROM Booking b '
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // booking -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> user
    'WHERE b.TutorID = :tid AND b.Status = :status ' // only this tutor's bookings with this status
    'ORDER BY b.Created_at DESC', // newest first
    {'tid': tutor.tutorId, 'status': status},
  );
  return Response.json(
    body: {
      'tutor': header, // NEW: name + profile picture
      'counts': counts, // NEW: tab numbers
      'status': status, // which filter was applied
      'count': result.rows.length, // number of requests returned
      'requests': result.rows.map((r) => r.assoc()).toList(), // request cards
    },
  );
}
