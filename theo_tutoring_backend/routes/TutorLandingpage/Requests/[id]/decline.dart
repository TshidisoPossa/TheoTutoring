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
  final conn = await getConnection(); // open a DB connection
  try {
    // The booking must belong to this tutor and still be Pending
    final found = await conn.execute(
      "SELECT `Date`, StartTime, EndTime FROM Booking "
      "WHERE Booking_id = :id AND TutorID = :tid AND Status = 'Pending'",
      {'id': bookingId, 'tid': tutor.tutorId},
    );
    if (found.rows.isEmpty) {
      return Response.json(
        statusCode: 404,
        body: {'error': 'Pending request not found'},
      );
    }
    final b = found.rows.first.assoc(); // date and times of the request

    // Tutors cannot be double-booked: look for an overlapping Accepted/Paid booking
    final clash = await conn.execute(
      "SELECT 1 FROM Booking WHERE TutorID = :tid AND `Date` = :d "
      "AND Status IN ('Accepted','Paid') AND StartTime < :e AND EndTime > :s LIMIT 1",
      {
        'tid': tutor.tutorId,
        'd': b['Date'],
        's': b['StartTime'],
        'e': b['EndTime'],
      },
    );
    if (clash.rows.isNotEmpty) {
      return Response.json(
        statusCode: 409,
        body: {'error': 'Time slot already booked'},
      );
    }

    // Accepted status is what unlocks the student's payment
    await conn.execute(
      "UPDATE Booking SET Status = 'Accepted' WHERE Booking_id = :id AND Status = 'Pending'",
      {'id': bookingId},
    );
    return Response.json(body: {'bookingId': bookingId, 'status': 'Accepted'});
  } finally {
    await conn.close(); // always close the connection
  }
}
