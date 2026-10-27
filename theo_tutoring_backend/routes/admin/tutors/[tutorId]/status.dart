import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_tutors.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context, String tutorId) =>
    handleTutorStatus(context, tutorId);

/// PATCH /admin/tutors/{tutorId}/status {"status": "Suspended"}.
/// Super Admin only; changes User.AccountStatus and nothing else. Tutors
/// still in review are decided on the Applications page instead (409).
Future<Response> handleTutorStatus(
  RequestContext context,
  String tutorId, {
  AdminResolver? adminResolver,
  TutorRosterRepository? repository,
}) async {
  if (context.request.method != HttpMethod.patch) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only PATCH requests are supported.'},
    );
  }
  try {
    // Authorize before looking at the body or the target.
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.tutors.manage');

    final id = int.tryParse(tutorId);
    final Object? body;
    try {
      body = await context.request.json();
    } on Object {
      return _bad('A JSON body is required.');
    }
    final status = body is Map ? body['status'] : null;
    if (id == null || id < 1) return _bad('Invalid tutor id.');
    if (status is! String || !tutorRosterSettableStatuses.contains(status)) {
      return _bad('status must be Active, Suspended or Deactivated.');
    }
    final result = await (repository ?? MySqlTutorRosterRepository())
        .setStatus(id, status);
    return Response.json(body: result);
  } on AuthTokenException catch (e) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': e.message},
    );
  } on AdminAccessDenied catch (e) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': e.message},
    );
  } on TutorNotFound {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'Tutor not found.'},
    );
  } on TutorStatusLocked catch (e) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {
        'error':
            'This tutor is ${e.status} and has not been approved yet. '
            'Review them on the Applications page.',
      },
    );
  } catch (error) {
    stderr.writeln('Tutor status update failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The tutor status could not be updated.'},
    );
  }
}

Response _bad(String message) => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {'error': message},
);
