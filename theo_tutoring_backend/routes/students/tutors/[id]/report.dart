import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';
import 'package:theo_tutoring_backend/student_reports.dart';

// POST /students/tutors/<TutorID>/report
// "Report tutor" in the ⋮ menu of the student's Tutor Profile page: the
// student reports the tutor to the administrator without a lesson
// (documentation 4.9).
//
// Body: { "reason": "Rude in messages" }  (5-500 characters)
//
// Saves a Report row with the status 'Open' for the admin dashboard.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only POST requests are supported.'},
    );
  }
  final tutorId = int.tryParse(id);
  if (tutorId == null || tutorId <= 0) {
    return jsonError(HttpStatus.badRequest, 'Invalid tutor id.');
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

    final reportId = await MySqlStudentReportsRepository(
      await getConnection(),
    ).reportTutor(identity.uid, tutorId, reason);
    announceToAdmins(() => notifyAdminsOfReport(reportId));

    return Response.json(
      statusCode: HttpStatus.created,
      body: {'reportId': reportId, 'tutorId': tutorId, 'status': 'Open'},
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
    stderr.writeln('Reporting tutor $tutorId failed: $error\n$stackTrace');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not send your report. Please try again.',
    );
  }
}
