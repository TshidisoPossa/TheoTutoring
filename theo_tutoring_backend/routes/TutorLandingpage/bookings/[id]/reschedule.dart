import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
import 'package:theo_tutoring_backend/tutor_cancel_booking.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../../lib/tutorlanding_session.dart';

// POST /TutorLandingpage/bookings/<Booking_id>/reschedule
// The Reschedule button on the booking details page (see
// lib/tutor_cancel_booking.dart).
Future<Response> onRequest(RequestContext context, String id) async {
  final (response, body) = await readResponseJson(
    await handleTutorCancelBooking(
      context,
      id,
      tutorId: context.read<TutorSession>().tutorId,
      kind: TutorCancelKind.reschedule,
    ),
  );
  announceTutorCancelRefund(response, body);
  return response;
}
