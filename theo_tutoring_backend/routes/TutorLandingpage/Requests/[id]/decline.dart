import '../../../../lib/database.dart'; // getConnection()
import '../../../../lib/tutorlanding_session.dart'; // TutorSession
import 'package:dart_frog/dart_frog.dart'; // Dart Frog types

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405); // only POST is allowed
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

  // Only this tutor's own Pending request can be declined
  final result = await conn.execute(
    "UPDATE Booking SET Status = 'Declined' "
    "WHERE Booking_id = :id AND TutorID = :tid AND Status = 'Pending'",
    {'id': bookingId, 'tid': tutor.tutorId},
  );
  if (result.affectedRows.toInt() == 0) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Pending request not found'},
    ); // wrong id, not theirs, or already answered
  }
  return Response.json(body: {'bookingId': bookingId, 'status': 'Declined'});
}
