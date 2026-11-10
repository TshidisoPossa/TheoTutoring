import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/header_tutor.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

// ---------------------------------------------------------------------------
// The Cancel and Reschedule buttons on the tutor's booking details page.
//
//   POST /TutorLandingpage/bookings/<Booking_id>/cancel
//   POST /TutorLandingpage/bookings/<Booking_id>/reschedule
//
// No body. Both cancel the session (see [tutorCancelBooking]) and notify the
// student: "Session cancelled", or "Session rescheduled" with a link to book
// a new time with the same tutor and subject.
// ---------------------------------------------------------------------------

/// Cancels the booking in the database.
typedef TutorBookingCanceller =
    Future<TutorCancellation> Function(
      int tutorId,
      int bookingId,
      TutorCancelKind kind,
    );

/// The tutor's name for the student's message, or null if unknown.
typedef TutorNameLookup = Future<String?> Function(int tutorId);

Future<TutorCancellation> _cancelInMySql(
  int tutorId,
  int bookingId,
  TutorCancelKind kind,
) async => tutorCancelBooking(await getConnection(), tutorId, bookingId, kind);

Future<String?> _tutorNameFromMySql(int tutorId) async =>
    (await getTutorHeader(await getConnection(), tutorId))?['name']?.toString();

/// Handles both routes for the signed-in tutor [tutorId]. [id] is the
/// booking id from the path. Tests pass their own [cancel] and [tutorName].
Future<Response> handleTutorCancelBooking(
  RequestContext context,
  String id, {
  required int tutorId,
  required TutorCancelKind kind,
  TutorBookingCanceller cancel = _cancelInMySql,
  TutorNameLookup tutorName = _tutorNameFromMySql,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bookingId = int.tryParse(id);
  if (bookingId == null || bookingId <= 0) {
    return jsonError(HttpStatus.badRequest, 'Invalid booking id.');
  }

  final TutorCancellation cancelled;
  try {
    cancelled = await cancel(tutorId, bookingId, kind);
  } on PostponeException catch (e) {
    return jsonError(e.statusCode, e.message);
  } catch (e) {
    stderr.writeln('Tutor could not ${kind.name} booking $bookingId: $e');
    return jsonError(
      HttpStatus.internalServerError,
      kind == TutorCancelKind.cancel
          ? 'Could not cancel this session. Please try again.'
          : 'Could not reschedule this session. Please try again.',
    );
  }

  // The booking is already cancelled, so a problem with the name or
  // Firestore must not undo it: log it and say the student was not told.
  var notified = false;
  final studentUid = cancelled.studentFirebaseUid;
  if (studentUid != null && studentUid.isNotEmpty) {
    try {
      final name = await tutorName(tutorId) ?? 'Your tutor';
      final message = tutorCancellationMessage(kind, name, cancelled);
      await context.read<NotificationStore>().create(
        uid: studentUid,
        type: kind == TutorCancelKind.cancel
            ? NotificationType.bookingCancelled
            : NotificationType.bookingRescheduled,
        title: message.title,
        body: message.body,
        bookingId: bookingId,
        // "Book a new time" opens this tutor's booking page
        tutorId: kind == TutorCancelKind.reschedule ? tutorId : null,
        subjectId: kind == TutorCancelKind.reschedule
            ? cancelled.subjectId
            : null,
      );
      notified = true;
    } catch (e) {
      stderr.writeln(
        'Could not notify the student about booking $bookingId: $e',
      );
    }
  }

  return Response.json(
    body: {
      'bookingId': bookingId,
      'status': 'Cancelled',
      'refundAmount': cancelled.refundAmount, // null when nothing was paid
      'studentNotified': notified,
    },
  );
}

/// The student's notification, e.g. "Session rescheduled" / "Thabo needs to
/// reschedule your Calculus session on Tue 17 Nov, 13:00. Please book again
/// at a time that suits you. Your R 250.00 payment will be refunded in full."
({String title, String body}) tutorCancellationMessage(
  TutorCancelKind kind,
  String tutorName,
  TutorCancellation cancelled,
) {
  final session =
      'your ${cancelled.subject} session on '
      '${sessionLabel(cancelled.date, cancelled.startTime)}';
  final refund = cancelled.refundAmount == null
      ? ''
      : ' Your R ${cancelled.refundAmount} payment will be refunded in full.';
  return switch (kind) {
    TutorCancelKind.cancel => (
      title: 'Session cancelled',
      body: '$tutorName cancelled $session.$refund',
    ),
    TutorCancelKind.reschedule => (
      title: 'Session rescheduled',
      body:
          '$tutorName needs to reschedule $session. Please book again at a '
          'time that suits you.$refund',
    ),
  };
}
