import 'dart:io'; // HttpStatus codes + stderr

import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/profile_tutor.dart'; // updateTutorAbout
import 'package:theo_tutoring_backend/request_utils.dart'; // JSON helpers
import 'package:theo_tutoring_backend/validator.dart'; // bio rule
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart'; // TutorSession

// PUT /TutorLandingpage/Profile/about   (pencil on the About Me box)
//
// body: {"about": "I have tutored first-year maths for three years..."}
// Uses the same bio rule as registration Step 2 (Validator.validateBio),
// and saves it in TutorProfile.Bio.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    ); // only PUT is allowed
  }
  final tutor = context.read<TutorSession>(); // who is calling

  try {
    final body = await readJsonObject(context);
    final about = optionalString(body, 'about'); // trimmed, null if blank
    final check = Validator.validateBio(about);
    if (!check.isValid) return jsonError(HttpStatus.badRequest, check.error);

    final conn = await getConnection(); // shared DB connection (do not close it)
    await updateTutorAbout(conn, tutor.tutorId, about!);
    return Response.json(
      body: {
        'message': 'About Me saved.',
        'about': await getTutorAbout(conn, tutor.tutorId), // what was saved
      },
    );
  } on FormatException catch (e) {
    return jsonError(HttpStatus.badRequest, e.message);
  } catch (e) {
    stderr.writeln('Error saving tutor About Me: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not save your About Me. Please try again.',
    );
  }
}
