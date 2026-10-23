import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_monitor.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminAuditLog(context);

Future<Response> handleAdminAuditLog(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminMonitorRepositoryFactory? repositoryFactory,
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
    requireAdminPermission(admin, 'admin.monitor.read');
    final query = context.request.uri.queryParameters;
    final rawLimit = query['limit'] ?? '20';
    final limit = int.tryParse(rawLimit);
    if (limit == null || limit < 1 || limit > 100) {
      throw const AdminMonitorValidation('Limit must be between 1 and 100.');
    }
    final before = AdminMonitorCursor.parse(query['before']);
    final result =
        await (repositoryFactory ?? MySqlAdminMonitorRepository.new)()
            .fetchAuditPage(limit: limit, before: before);
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
  } on AdminMonitorValidation catch (error) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': error.message},
    );
  } catch (error) {
    stderr.writeln('Admin audit lookup failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The audit log is temporarily unavailable.'},
    );
  }
}
