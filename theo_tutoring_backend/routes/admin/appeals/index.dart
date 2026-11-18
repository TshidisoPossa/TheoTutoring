import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAppealList(context);

const _statuses = {'pending', 'approved', 'rejected', 'closed', 'all'};

/// GET /admin/appeals?status=pending|approved|rejected|closed|all
///
/// Suspension appeals for the accounts this administrator may manage:
/// students with admin.students.manage, tutors with admin.tutors.manage
/// (neither: 403). Pending appeals first, newest first.
///
/// {"adminName", "summary": {"pending"},
///  "appeals": [{"appealId", "status", "explanation", "submittedAt",
///    "decisionNote", "decidedAt", "reviewedBy",
///    "suspension": {"suspensionId", "reason", "suspendedAt", "suspendedBy",
///                   "status", "liftedAt", "liftReason"},
///    "user": {"userId", "role", "profileId", "name", "email", "phone",
///             "photoUrl", "accountStatus", "joinedAt"}}]}
Future<Response> handleAppealList(
  RequestContext context, {
  AdminResolver? adminResolver,
  AccountSuspensionRepository? repository,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }
  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    final roles = appealRolesFor(admin);
    if (roles.isEmpty) {
      throw const AdminPermissionDenied('admin.students.manage');
    }
    final status = context.request.uri.queryParameters['status'] ?? 'pending';
    if (!_statuses.contains(status)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'error':
              'status must be pending, approved, rejected, closed or all.',
        },
      );
    }
    final result = await (repository ?? MySqlAccountSuspensionRepository())
        .listAppeals(status: status, roles: roles);
    return Response.json(body: {'adminName': admin.name, ...result});
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
    stderr.writeln('Appeal list failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Appeals could not be loaded.'},
    );
  }
}
