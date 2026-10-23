import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminIdentity(context);

Future<Response> handleAdminIdentity(
  RequestContext context, {
  AdminResolver? adminResolver,
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
    return Response.json(
      body: {
        'adminId': admin.id,
        'adminName': admin.name,
        'adminRole': admin.roleKey,
        'permissions': admin.permissions,
      },
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
    stderr.writeln('Admin identity lookup failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Administrator access could not be verified.'},
    );
  }
}
