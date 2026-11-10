import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_reviews.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context, String reviewId) =>
    handleAdminReviewDetail(context, reviewId);

/// GET /admin/reviews/<Reviewid>
/// One review for the admin's details panel (permission admin.reviews.read):
/// the review, the booking it was for, the tutor (email, status, average),
/// the student (email, university) and every report filed on that booking.
Future<Response> handleAdminReviewDetail(
  RequestContext context,
  String reviewId, {
  AdminResolver? adminResolver,
  AdminReviewsRepository? repository,
}) async {
  if (context.request.method != HttpMethod.get) {
    return _error(
      HttpStatus.methodNotAllowed,
      'Only GET requests are supported.',
    );
  }
  final id = int.tryParse(reviewId);
  if (id == null || id <= 0) {
    return _error(HttpStatus.badRequest, 'Invalid review id.');
  }

  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.reviews.read');
    final review = await (repository ?? MySqlAdminReviewsRepository()).detail(
      id,
    );
    return Response.json(body: review);
  } on AuthTokenException catch (e) {
    return _error(HttpStatus.unauthorized, e.message);
  } on AdminAccessDenied catch (e) {
    return _error(HttpStatus.forbidden, e.message);
  } on AdminReviewNotFound {
    return _error(HttpStatus.notFound, 'Review not found.');
  } catch (error, stackTrace) {
    stderr.writeln('Admin review $id failed: $error\n$stackTrace');
    return _error(
      HttpStatus.internalServerError,
      'The review could not be loaded.',
    );
  }
}

Response _error(int status, String message) =>
    Response.json(statusCode: status, body: {'error': message});
