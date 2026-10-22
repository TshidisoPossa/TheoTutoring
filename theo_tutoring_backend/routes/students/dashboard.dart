import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }

  try {
    final identity = await verifyFirebaseToken(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    final data = await MySqlStudentDashboardRepository(
      await getConnection(),
    ).load(identity.uid);
    return Response.json(body: data);
  } on AuthTokenException catch (error) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': error.message},
    );
  } on StudentDashboardDenied {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': 'An active student account is required.'},
    );
  } catch (error, stackTrace) {
    stderr.writeln('Student dashboard load failed: $error\n$stackTrace');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The student dashboard is temporarily unavailable.'},
    );
  }
}
