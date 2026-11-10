import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';
import 'package:theo_tutoring_backend/student_reviews.dart';

// POST /students/lessons/<Booking_id>/review
// "Leave a review" on a completed lesson in My Schedule (documentation 4.9):
// only the student who had the lesson, only after it has taken place, and
// once per booking. The tutor's average rating is updated, and the tutor's
// bell shows the review the next time they open it.
//
// Body: { "rating": 1-5, "comment": "optional, up to 1000 characters" }
// 201: { reviewId, bookingId, rating, comment, tutorAverage,
//        tutorReviewCount }
Future<Response> onRequest(RequestContext context, String id) =>
    handleLessonReview(context, id);

/// Optional seams let the route test use a fake identity and repository.
Future<Response> handleLessonReview(
  RequestContext context,
  String id, {
  Future<FirebaseUser> Function(String?) tokenVerifier = verifyFirebaseToken,
  Future<StudentReviewsRepository> Function()? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(
      HttpStatus.methodNotAllowed,
      'Only POST requests are supported.',
    );
  }
  final bookingId = int.tryParse(id);
  if (bookingId == null || bookingId <= 0) {
    return jsonError(HttpStatus.badRequest, 'Invalid booking id.');
  }

  try {
    final identity = await tokenVerifier(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );

    final ReviewInput input;
    try {
      input = parseReviewBody(await readJsonObject(context));
    } on FormatException catch (e) {
      return jsonError(HttpStatus.badRequest, e.message);
    }

    final repository = await (repositoryFactory ?? _mySqlRepository)();
    final saved = await repository.submit(identity.uid, bookingId, input);
    return Response.json(statusCode: HttpStatus.created, body: saved.toJson());
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
    stderr.writeln('Reviewing lesson $bookingId failed: $error\n$stackTrace');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not save your review. Please try again.',
    );
  }
}

Future<StudentReviewsRepository> _mySqlRepository() async =>
    MySqlStudentReviewsRepository(await getConnection());
