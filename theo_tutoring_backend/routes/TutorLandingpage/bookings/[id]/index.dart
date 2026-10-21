import 'dart:io'; // HttpStatus codes + stderr

import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/booking_tutor.dart'; // getBookingDetail
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/header_tutor.dart'; // name + photo
import 'package:theo_tutoring_backend/request_utils.dart'; // jsonError
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../../lib/tutorlanding_session.dart'; // TutorSession

// Author Tshidiso Possa
// GET /TutorLandingpage/bookings/<Booking_id>
// Opened by the View button on the Schedule page (any tab).
//
// Returns:
//   tutor     - name + profile picture (top right)
//   booking   - subject, date, time, duration, student note, "ID #REQ-8842",
//               "Received 3h ago", and canPostpone (shows the Decline button)
//   student   - name, photo, year, course ("Major & Focus"), verified tick
//   recurring - the "Recurring Booking" card, or null for a one-off session
//
// The Decline button calls POST /TutorLandingpage/bookings/<id>/postpone.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    ); // only GET is allowed
  }
  final bookingId = int.tryParse(id); // the id in the url must be a number
  if (bookingId == null || bookingId <= 0) {
    return jsonError(HttpStatus.badRequest, 'Invalid booking id.');
  }

  final tutor = context.read<TutorSession>(); // who is calling

  try {
    final conn = await getConnection(); // shared DB connection (don't close)

    // tutor name + profile picture, same helper as every tutor page
    final header = await getTutorHeader(conn, tutor.tutorId);
    if (header == null) {
      return jsonError(HttpStatus.notFound, 'Tutor not found');
    }

    final detail = await getBookingDetail(conn, tutor.tutorId, bookingId);
    if (detail == null) {
      // wrong id, or it belongs to another tutor
      return jsonError(HttpStatus.notFound, 'Booking not found.');
    }
    return Response.json(body: {'tutor': header, ...detail});
  } catch (e) {
    stderr.writeln('Error loading booking $bookingId: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not load this session. Please try again.',
    );
  }
}
