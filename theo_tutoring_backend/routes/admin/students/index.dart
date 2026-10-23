import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_students.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleStudentRoster(context);

/// GET /admin/students?status=all|active|suspended|pending&search=&page=&pageSize=
/// Super Admin only (permission admin.students.read).
Future<Response> handleStudentRoster(
  RequestContext context, {
  AdminResolver? adminResolver,
  StudentRosterRepository? repository,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }
  final params = context.request.uri.queryParameters;
  final filter = params['status'] ?? 'all';
  final page = int.tryParse(params['page'] ?? '1');
  final pageSize = int.tryParse(params['pageSize'] ?? '10');
  if (!rosterStatusFilters.containsKey(filter)) {
    return _bad('Unknown status filter.');
  }
  if (page == null ||
      page < 1 ||
      pageSize == null ||
      pageSize < 1 ||
      pageSize > 100) {
    return _bad('page must be 1 or more and pageSize 1-100.');
  }
  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.students.read');
    final result = await (repository ?? MySqlStudentRosterRepository()).list(
      status: rosterStatusFilters[filter],
      search: params['search']?.trim(),
      page: page,
      pageSize: pageSize,
    );
    return Response.json(body: {...result, 'adminName': admin.name});
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
  } catch (error) {
    stderr.writeln('Student roster failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The student roster could not be loaded.'},
    );
  }
}

Response _bad(String message) => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {'error': message},
);
