import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_students.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context, String studentId) =>
    handleStudentStatus(context, studentId);

/// PATCH /admin/students/{studentId}/status {"status": "Suspended"}.
/// Super Admin only; changes User.AccountStatus and nothing else.
Future<Response> handleStudentStatus(
  RequestContext context,
  String studentId, {
  AdminResolver? adminResolver,
  StudentRosterRepository? repository,
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
    requireAdminPermission(admin, 'admin.students.manage');

    final id = int.tryParse(studentId);
    final Object? body;
    try {
      body = await context.request.json();
    } on Object {
      return _bad('A JSON body is required.');
    }
    final status = body is Map ? body['status'] : null;
    if (id == null || id < 1) return _bad('Invalid student id.');
    if (status is! String || !rosterSettableStatuses.contains(status)) {
      return _bad('status must be Active, Suspended or Deactivated.');
    }
    final result = await (repository ?? MySqlStudentRosterRepository())
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
  } on StudentNotFound {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'Student not found.'},
    );
  } catch (error) {
    stderr.writeln('Student status update failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The student status could not be updated.'},
    );
  }
}

Response _bad(String message) => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {'error': message},
);
