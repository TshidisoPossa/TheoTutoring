import 'dart:io'; // HttpStatus codes + stderr

import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/booking_tutor.dart'; // postponeBooking
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/header_tutor.dart'; // tutor name
import 'package:theo_tutoring_backend/notifications.dart'; // NotificationStore
import 'package:theo_tutoring_backend/request_utils.dart'; // jsonError
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../../lib/tutorlanding_session.dart'; // TutorSession

// Author Tshidiso Possa
// POST /TutorLandingpage/bookings/<Booking_id>/postpone
// The Decline button on the booking details page. Declining does not cancel
// the session: the tutor picks a new time and the student must confirm it.
//
// Body: { "date": "2026-10-31", "startTime": "16:00", "endTime": "17:00" }
//
// Rules:
//   - only Pending or Confirmed sessions that have not started yet
//   - the new time is at least 3 hours away (documentation 4.5)
//   - it sits inside the tutor's availability for that weekday
//   - it does not clash with another of the tutor's sessions
// The booking moves to the new time with the status 'Postponed' and the
// student gets a notification asking them to confirm it.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    ); // only POST is allowed
  }
  final bookingId = int.tryParse(id); // the id in the url must be a number
  if (bookingId == null || bookingId <= 0) {
    return jsonError(HttpStatus.badRequest, 'Invalid booking id.');
  }

  final PostponeSlot slot;
  try {
    slot = parsePostponeSlot(await readJsonObject(context));
  } on FormatException catch (e) {
    return jsonError(HttpStatus.badRequest, e.message); // bad date or time
  }

  final tutor = context.read<TutorSession>(); // who is calling

  try {
    final conn = await getConnection(); // shared DB connection (don't close)
    final before = await postponeBooking(conn, tutor.tutorId, bookingId, slot);

    // "Thabo moved your Calculus session on Fri 24 Oct, 16:00 to
    //  Fri 31 Oct, 16:00-17:00. Please confirm the new time."
    final header = await getTutorHeader(conn, tutor.tutorId);
    final oldTime = sessionLabel(before.previousDate, before.previousStartTime);
    final newTime = '${sessionLabel(slot.date, hhmm(slot.start))}'
        '-${hhmm(slot.end)}';
    final notified = await _notifyStudent(
      context,
      bookingId: bookingId,
      studentUid: before.studentFirebaseUid,
      title: 'Session postponed',
      body:
          '${header?['name'] ?? 'Your tutor'} moved your ${before.subject} '
          'session on $oldTime to $newTime. Please confirm the new time.',
    );

    return Response.json(
      body: {
        'bookingId': bookingId,
        'status': 'Postponed',
        'date': slot.date,
        'startTime': hhmm(slot.start),
        'endTime': hhmm(slot.end),
        'previous': {
          'status': before.previousStatus,
          'date': before.previousDate,
          'startTime': before.previousStartTime,
          'endTime': before.previousEndTime,
        },
        'studentNotified': notified,
      },
    );
  } on PostponeException catch (e) {
    return jsonError(e.statusCode, e.message);
  } catch (e) {
    stderr.writeln('Error postponing booking $bookingId: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not postpone this session. Please try again.',
    );
  }
}

// The booking is already saved, so a Firestore problem must not undo it:
// log it and tell the app the student was not notified.
Future<bool> _notifyStudent(
  RequestContext context, {
  required int bookingId,
  required String? studentUid,
  required String title,
  required String body,
}) async {
  if (studentUid == null || studentUid.isEmpty) return false;
  try {
    await context.read<NotificationStore>().create(
      uid: studentUid,
      type: NotificationType.bookingPostponed,
      title: title,
      body: body,
      bookingId: bookingId,
    );
    return true;
  } catch (e) {
    stderr.writeln('Could not notify the student about booking $bookingId: $e');
    return false;
  }
}
