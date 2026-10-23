import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';

NotificationStore? _store; // shared, so the Google access token is reused

// POST /students/lessons/<Booking_id>/cancel
// The Cancel option in My Schedule's lesson menu.
//
// Body: { "reason": "I have a test that day" }  (5-500 characters)
//
// Only the student's own Pending/Accepted/Postponed/Confirmed lessons that
// have not started can be cancelled. A paid lesson gets a Refund record
// (documentation 4.6) and the tutor is notified.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only POST requests are supported.'},
    );
  }
  final bookingId = int.tryParse(id);
  if (bookingId == null || bookingId <= 0) {
    return jsonError(HttpStatus.badRequest, 'Invalid booking id.');
  }

  try {
    final identity = await verifyFirebaseToken(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );

    final String reason;
    try {
      final body = await readJsonObject(context);
      reason = optionalString(body, 'reason', maxLength: 500) ?? '';
      if (reason.length < 5) {
        throw const FormatException(
          'Please give a reason of at least 5 characters.',
        );
      }
    } on FormatException catch (e) {
      return jsonError(HttpStatus.badRequest, e.message);
    }

    final cancellation = await MySqlStudentLessonsRepository(
      await getConnection(),
    ).cancel(identity.uid, bookingId, reason);
    final notified = await _notifyTutor(cancellation);

    return Response.json(
      body: {
        'bookingId': bookingId,
        'status': 'Cancelled',
        'cancellationReason': reason,
        'refundPercentage': cancellation.refundPercentage,
        'refundAmount': cancellation.refundAmount,
        'tutorNotified': notified,
      },
    );
  } on AuthTokenException catch (error) {
    return jsonError(HttpStatus.unauthorized, error.message);
  } on StudentDashboardDenied {
    return jsonError(
      HttpStatus.forbidden,
      'An active student account is required.',
    );
  } on LessonActionException catch (error) {
    return jsonError(error.statusCode, error.message);
  } catch (error, stackTrace) {
    stderr.writeln('Cancelling lesson $bookingId failed: $error\n$stackTrace');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not cancel this lesson. Please try again.',
    );
  }
}

// The cancellation is already saved, so a Firestore problem must not undo
// it: log it and tell the app the tutor was not notified.
Future<bool> _notifyTutor(LessonCancellation cancellation) async {
  final tutorUid = cancellation.tutorFirebaseUid;
  if (tutorUid == null || tutorUid.isEmpty) return false;
  try {
    await (_store ??= NotificationStore.fromFirebaseAdmin()).create(
      uid: tutorUid,
      type: NotificationType.bookingCancelled,
      title: 'Session cancelled',
      body:
          '${cancellation.studentName} cancelled the ${cancellation.subject} '
          'session on '
          '${sessionLabel(cancellation.date, cancellation.startTime)}.',
      bookingId: cancellation.bookingId,
    );
    return true;
  } catch (e) {
    stderr.writeln(
      'Could not notify the tutor about cancelled booking '
      '${cancellation.bookingId}: $e',
    );
    return false;
  }
}
