import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_roles.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

Future<Response> onRequest(RequestContext context, String adminId) =>
    handleAdminRoleChange(context, targetAdminId: int.tryParse(adminId));

Future<Response> handleAdminRoleChange(
  RequestContext context, {
  int? targetAdminId,
  AdminResolver? adminResolver,
  AdminRoleRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.put) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only PUT requests are supported.'},
    );
  }

  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.roles.manage');

    final segments = context.request.uri.pathSegments;
    final id =
        targetAdminId ?? int.tryParse(segments.isEmpty ? '' : segments.last);
    if (id == null || id <= 0) {
      throw const AdminRoleValidation('A valid adminId is required.');
    }
    final body = await readJsonObject(context);
    final role = body['role'];
    if (role is! String || !isKnownAdminRole(role.trim())) {
      throw const AdminRoleValidation('A recognized role is required.');
    }
    final reason = body['reason'];
    if (reason is! String ||
        reason.trim().length < 3 ||
        reason.trim().length > 500) {
      throw const AdminRoleValidation('Reason must be 3 to 500 characters.');
    }

    final result = await (repositoryFactory ?? MySqlAdminRoleRepository.new)()
        .changeRole(
          targetAdminId: id,
          newRole: role.trim(),
          reason: reason.trim(),
          actor: admin,
        );
    return Response.json(body: result);
  } on AuthTokenException catch (error) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': error.message},
    );
  } on AdminAccessDenied catch (error) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': error.message},
    );
  } on AdminRoleValidation catch (error) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': error.message},
    );
  } on AdminRoleNotFound {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'Administrator not found.'},
    );
  } on AdminRoleConflict catch (error) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': error.message},
    );
  } catch (error) {
    stderr.writeln('Admin role change failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The administrator role could not be changed.'},
    );
  }
}
