import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
import 'package:theo_tutoring_backend/tutor_presence.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../lib/tutorlanding_session.dart';

// POST   /TutorLandingpage/presence -> "I'm still here" (every minute)
// DELETE /TutorLandingpage/presence -> signed out, offline straight away
// Students see "Available Now" on the Tutor Profile while the last ping is
// recent (lib/tutor_presence.dart).
Future<Response> onRequest(RequestContext context) async {
  final tutor = context.read<TutorSession>();
  try {
    final conn = await getConnection(); // shared DB connection (don't close)
    final method = context.request.method;
    if (method == HttpMethod.post) {
      await markTutorActive(conn, tutor.tutorId);
      return Response.json(body: {'availableNow': true});
    }
    if (method == HttpMethod.delete) {
      await markTutorOffline(conn, tutor.tutorId);
      return Response.json(body: {'availableNow': false});
    }
    return Response(statusCode: HttpStatus.methodNotAllowed);
  } catch (e) {
    stderr.writeln('Presence update failed for tutor ${tutor.tutorId}: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not update your availability.',
    );
  }
}
