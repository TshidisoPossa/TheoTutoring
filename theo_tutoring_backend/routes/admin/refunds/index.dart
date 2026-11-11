import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) => handleRefundCases(
  context,
);

Future<Response> handleRefundCases(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminRefundRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }

  final query = context.request.uri.queryParameters;
  final type = query['type'] ?? 'all';
  final status = query['status'] ?? 'all';
  if (!const {'all', 'cancellation', 'report'}.contains(type)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Type must be all, cancellation, or report.'},
    );
  }
  if (!const {'all', 'open', 'resolved'}.contains(status)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Status must be all, open, or resolved.'},
    );
  }

  final authorization =
      context.request.headers['authorization'] ??
      context.request.headers['Authorization'];
  try {
    final admin = await (adminResolver ?? resolveAdmin)(authorization);
    if (type == 'report') {
      requireAdminPermission(admin, 'admin.reports.read');
    } else if (type == 'cancellation') {
      requireAdminPermission(admin, 'admin.refunds.read');
    } else {
      requireAdminPermission(admin, 'admin.refunds.read');
      requireAdminPermission(admin, 'admin.reports.read');
    }
    final result =
        await (repositoryFactory ?? MySqlAdminRefundsRepository.new)()
            .fetchCases(type: type, status: status, adminName: admin.name);
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
  } catch (error) {
    if (error is AdminRefundValidation) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': error.message},
      );
    }
    if (error is MySQLServerException) {
      stderr.writeln('Admin refunds lookup failed (MySQL ${error.errorCode}).');
      // 1146: a table the refunds query needs (e.g. from migration 003/004)
      // has not been created in this database. Retrying will not help.
      if (error.errorCode == 1146) {
        return Response.json(
          statusCode: HttpStatus.serviceUnavailable,
          body: {
            'error':
                'Refunds & Issues is not set up on this server yet: required '
                'database tables are missing. Apply the pending database '
                'migrations, then try again.',
          },
        );
      }
    } else {
      stderr.writeln('Admin refunds lookup failed (${error.runtimeType}).');
    }
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Refund cases are temporarily unavailable.'},
    );
  }
}
