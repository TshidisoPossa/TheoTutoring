import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_monitor.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleMonitorSnapshot(context);

Future<Response> handleMonitorSnapshot(
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
    final range = query['range'] ?? 'live';
    if (!const {'live', '24h'}.contains(range)) {
      throw const AdminMonitorValidation('Range must be live or 24h.');
    }
    final result =
        await (repositoryFactory ?? MySqlAdminMonitorRepository.new)()
            .fetchSnapshot(range: range, adminName: admin.name);
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
    stderr.writeln('Admin monitor snapshot failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Platform metrics are temporarily unavailable.'},
    );
  }
}
