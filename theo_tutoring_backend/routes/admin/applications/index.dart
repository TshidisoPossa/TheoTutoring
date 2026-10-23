import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_applications.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminApplications(context);

Future<Response> handleAdminApplications(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminApplicationsRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }

  final authorization =
      context.request.headers['authorization'] ??
      context.request.headers['Authorization'];
  try {
    final admin = await (adminResolver ?? resolveAdmin)(authorization);
    requireAdminPermission(admin, 'admin.applications.read');
    final applications =
        await (repositoryFactory ?? MySqlAdminApplicationsRepository.new)()
            .fetchApplications();
    return Response.json(
      body: {'adminName': admin.name, 'applications': applications},
    );
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
    stderr.writeln('Admin applications lookup failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Tutor applications are temporarily unavailable.'},
    );
  }
}
