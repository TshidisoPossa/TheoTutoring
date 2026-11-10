import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';

// POST /students/lessons/<Booking_id>/join
// The Start session button in My Schedule. No request body.
//
// Replies { "link": "https://meet.google.com/..." } for the student's own
// Confirmed lesson, or a paid Postponed one, from 15 minutes before it
// starts until it ends. The rules are in
// MySqlStudentLessonsRepository.joinLink.
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

    final link = await MySqlStudentLessonsRepository(
      await getConnection(),
    ).joinLink(identity.uid, bookingId);

    return Response.json(body: {'link': link});
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
    stderr.writeln('Joining lesson $bookingId failed: $error\n$stackTrace');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not open this session. Please try again.',
    );
  }
}
