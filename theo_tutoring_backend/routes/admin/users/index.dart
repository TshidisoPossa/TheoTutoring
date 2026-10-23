import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_users.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminUsers(context);

/// GET lists Admin accounts; POST creates one (Firebase login + User/Admin
/// rows). Both require the `admin.users.manage` permission.
Future<Response> handleAdminUsers(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminUsersRepositoryFactory? repositoryFactory,
  AdminAccountProvisionerFactory? provisionerFactory,
}) async {
  final method = context.request.method;
  if (method != HttpMethod.get && method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET and POST requests are supported.'},
    );
  }

  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.users.manage');
    final repository = (repositoryFactory ?? MySqlAdminUsersRepository.new)();

    if (method == HttpMethod.get) {
      return Response.json(
        body: {
          'adminName': admin.name,
          'roles': adminRolePermissions.keys.toList(),
          // Lets the create form describe each role from the real RBAC map.
          'rolePermissions': {
            for (final entry in adminRolePermissions.entries)
              entry.key: entry.value.toList()..sort(),
          },
          'admins': await repository.listAdmins(),
        },
      );
    }

    final Map<String, dynamic> body;
    try {
      body = await readJsonObject(context);
    } on FormatException catch (error) {
      throw AdminUserValidation(error.message);
    }
    final created = await createAdminAccount(
      NewAdminAccount.fromJson(body),
      repository: repository,
      provisioner: (provisionerFactory ?? FirebaseAccountProvisioner.new)(),
    );
    return Response.json(statusCode: HttpStatus.created, body: created);
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
  } on AdminUserValidation catch (error) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': error.message},
    );
  } on AdminUserConflict catch (error) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': error.message},
    );
  } on AdminAccountSetupUnavailable {
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'error':
            'Administrator accounts cannot be created on this server yet: '
            'the Firebase service account is not configured.',
      },
    );
  } catch (error) {
    // Never log the request body: it contains the initial password.
    stderr.writeln('Admin users request failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The administrator request could not be completed.'},
    );
  }
}
