import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import '../../../lib/database.dart'; // getConnection()
import '../../../lib/tutorlanding_session.dart';
import 'package:theo_tutoring_backend/header_tutor.dart'; // shared tutor name + photo

//auther Tshidiso Possa
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
  final result = await conn.execute(
    'SELECT b.Booking_id, b.Subject, b.Note, b.`Date`, b.StartTime, b.EndTime, '
    'b.Status, b.Created_at, u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto ' // booking + student name/photo
    'FROM Booking b '
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // booking -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> user
    'WHERE b.TutorID = :tid AND b.Status = :status ' // only this tutor's bookings with this status
    'ORDER BY b.Created_at DESC', // newest first
    {'tid': tutor.tutorId, 'status': status},
  );
  return Response.json(
    body: {
      'status': status, // which filter was applied
      'count': result.rows.length, // number of requests returned
      'requests': result.rows.map((r) => r.assoc()).toList(), // request cards
    },
  );
}
