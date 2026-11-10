import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_reviews.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminReviews(context);

/// GET /admin/reviews?search=&rating=1-5&range=all|7d|30d|90d
///   &withComment=true&sort=newest|oldest|lowest|highest&page=&pageSize=
/// Read-only list for the admin Reviews page (permission admin.reviews.read).
///
/// { adminName, total, page, pageSize,
///   summary: { totalReviews, averageRating, lowRatingsLast30Days,
///              reviewsThisMonth },
///   distribution: { "5": n, "4": n, "3": n, "2": n, "1": n },
///   needsAttention: [ { tutorId, name, photoUrl, status, averageRating,
///                       reviewCount } ],
///   reviews: [ { reviewId, rating, comment, bookingId, createdAt, subject,
///                tutor: {tutorId, name, photoUrl},
///                student: {studentId, name, photoUrl}, reportCount } ] }
Future<Response> handleAdminReviews(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminReviewsRepository? repository,
}) async {
  if (context.request.method != HttpMethod.get) {
    return _error(
      HttpStatus.methodNotAllowed,
      'Only GET requests are supported.',
    );
  }

  final params = context.request.uri.queryParameters;
  final page = int.tryParse(params['page'] ?? '1');
  final pageSize = int.tryParse(params['pageSize'] ?? '10');
  if (page == null ||
      page < 1 ||
      pageSize == null ||
      pageSize < 1 ||
      pageSize > 100) {
    return _error(
      HttpStatus.badRequest,
      'page must be 1 or more and pageSize 1-100.',
    );
  }
  final ratingText = params['rating'];
  final rating = ratingText == null || ratingText == 'all'
      ? null
      : int.tryParse(ratingText);
  if (ratingText != null &&
      ratingText != 'all' &&
      (rating == null || rating < 1 || rating > 5)) {
    return _error(HttpStatus.badRequest, 'rating must be 1-5 or all.');
  }
  final range = params['range'] ?? 'all';
  if (!adminReviewRanges.containsKey(range)) {
    return _error(HttpStatus.badRequest, 'Unknown date range.');
  }
  final sort = params['sort'] ?? 'newest';
  if (!adminReviewSorts.containsKey(sort)) {
    return _error(HttpStatus.badRequest, 'Unknown sort order.');
  }

  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.reviews.read');
    final result = await (repository ?? MySqlAdminReviewsRepository()).list(
      AdminReviewQuery(
        search: params['search']?.trim(),
        rating: rating,
        days: adminReviewRanges[range],
        withComment: params['withComment'] == 'true',
        sort: sort,
        page: page,
        pageSize: pageSize,
      ),
    );
    return Response.json(body: {...result, 'adminName': admin.name});
  } on AuthTokenException catch (e) {
    return _error(HttpStatus.unauthorized, e.message);
  } on AdminAccessDenied catch (e) {
    return _error(HttpStatus.forbidden, e.message);
  } catch (error, stackTrace) {
    stderr.writeln('Admin reviews failed: $error\n$stackTrace');
    return _error(
      HttpStatus.internalServerError,
      'Reviews could not be loaded.',
    );
  }
}

Response _error(int status, String message) =>
    Response.json(statusCode: status, body: {'error': message});
