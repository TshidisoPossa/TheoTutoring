import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/tutor_public_profile.dart';

// GET /tutors/<TutorID>
// The Tutor Profile page a student opens from Find a Tutor: the same fields
// as a search result plus availableNow, qualifications, availability and
// reviews. Public like GET /tutors; only approved, active tutors are found.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }
  final tutorId = int.tryParse(id);
  if (tutorId == null || tutorId <= 0) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Invalid tutor id.'},
    );
  }

  try {
    final profile = await MySqlTutorPublicProfileRepository(
      await getConnection(),
    ).load(tutorId);
    if (profile == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'This tutor is not available.'},
      );
    }
    return Response.json(body: profile);
  } catch (error, stackTrace) {
    stderr.writeln('Tutor profile $tutorId failed: $error\n$stackTrace');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'This tutor profile is temporarily unavailable.'},
    );
  }
}
