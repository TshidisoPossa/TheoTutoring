import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';
import 'package:theo_tutoring_backend/student_reschedule.dart';

NotificationStore? _store; // shared, so the Google access token is reused

// POST /students/lessons/<Booking_id>/reschedule
// The Reschedule option in My Schedule's lesson menu.
//
// Body: { "date": "2026-11-20", "startTime": "14:00" }  (SA time)
//
// Moves the student's own paid (Confirmed) lesson to a free hour in the
// tutor's availability. The payment stays with the lesson: nothing is
// charged or refunded. The tutor is notified. See lib/student_reschedule.dart.
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

    final BookingDate date;
    final int startMinutes;
    try {
      final body = await readJsonObject(context);
      date = BookingDate.parse('${body['date'] ?? ''}');
      startMinutes = parseClockTime('${body['startTime'] ?? ''}');
    } on FormatException catch (e) {
      return jsonError(HttpStatus.badRequest, e.message);
    }

    // Its own connection: the move is a transaction.
    final connection = await createIndependentConnection();
    final LessonReschedule moved;
    try {
      moved = await rescheduleStudentLesson(
        connection,
        firebaseUid: identity.uid,
        bookingId: bookingId,
        date: date,
        startMinutes: startMinutes,
        nowUtc: DateTime.now().toUtc(),
      );
    } finally {
      await connection.close();
    }
    final notified = await _notifyTutor(moved);

    return Response.json(
      body: {
        'bookingId': bookingId,
        'status': 'Confirmed',
        'date': moved.date,
        'startTime': moved.startTime,
        'endTime': moved.endTime,
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
  } on FormatException catch (error) {
    return jsonError(HttpStatus.badRequest, error.message);
  } catch (error, stackTrace) {
    stderr.writeln(
      'Rescheduling lesson $bookingId failed: $error\n$stackTrace',
    );
    return jsonError(
      HttpStatus.internalServerError,
      'Could not reschedule this lesson. Please try again.',
    );
  }
}

// The move is already saved, so a Firestore problem must not undo it: log
// it and tell the app the tutor was not notified.
Future<bool> _notifyTutor(LessonReschedule moved) async {
  final tutorUid = moved.tutorFirebaseUid;
  if (tutorUid == null || tutorUid.isEmpty) return false;
  try {
    await (_store ??= NotificationStore.fromFirebaseAdmin()).create(
      uid: tutorUid,
      type: NotificationType.bookingRescheduled,
      title: 'Session moved',
      body:
          '${moved.studentName} moved the ${moved.subject} session from '
          '${sessionLabel(moved.oldDate, moved.oldStartTime)} to '
          '${sessionLabel(moved.date, moved.startTime)}.',
      bookingId: moved.bookingId,
    );
    return true;
  } catch (e) {
    stderr.writeln(
      'Could not notify the tutor about rescheduled booking '
      '${moved.bookingId}: $e',
    );
    return false;
  }
}
