import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/profile_tutor.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// GET /TutorLandingpage/Profile   (Profile tab in the bottom navigation bar)
//
// Everything the tutor's Profile page shows, in one call:
//   name + profile photo, rating + review count, the fixed session rate
//   (read-only), About Me, subjects, qualifications and the Mon-Sat
//   availability grid.
// Each availability day also lists its "locked" periods: ticked periods that
// have an upcoming booking and so cannot be removed (business rule 12).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    );
  }
  final tutor = context.read<TutorSession>();

  try {
    final conn = await getConnection(); // shared DB connection (do not close it)
    final profile = await getTutorProfilePage(conn, tutor.tutorId);
    if (profile == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Tutor not found'},
      ); // no tutor profile for this session
    }
    return Response.json(
      body: {
        ...profile,
        'accountStatus': tutor.accountStatus, // 'Active' or 'Pending'
      },
    );
  } catch (e) {
    stderr.writeln('Error loading tutor profile: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Could not load your profile. Please try again.'},
    );
  }
}
