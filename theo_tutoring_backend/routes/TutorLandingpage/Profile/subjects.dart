import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/profile_tutor.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// PUT /TutorLandingpage/Profile/subjects   ("+ Add Subject" and removing one)
//
// body: {"subjectIds": [1, 3, 22]}  - the full list the tutor will teach.
// At least one and at most 10 subjects, each from the Subjects table.
// A subject with an upcoming booking cannot be removed (409).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    );
  }
  final tutor = context.read<TutorSession>();

  try {
    final body = await readJsonObject(context);
    final subjectIds = parseTutorSubjectIds(body['subjectIds']);

    final conn = await getConnection(); // shared DB connection (do not close it)
    await updateTutorSubjects(conn, tutor.tutorId, subjectIds);
    return Response.json(
      body: {
        'message': 'Subjects saved.',
        'subjects': await getTutorSubjects(conn, tutor.tutorId),
        'lockedSubjectIds': (await getLockedSubjectIds(conn, tutor.tutorId))
            .toList()
          ..sort(),
      },
    );
  } on FormatException catch (e) {
    return jsonError(HttpStatus.badRequest, e.message); // bad or unknown IDs
  } on SubjectInUseException catch (e) {
    return jsonError(HttpStatus.conflict, e.message); // booked subject removed
  } catch (e) {
    stderr.writeln('Error saving tutor subjects: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not save your subjects. Please try again.',
    );
  }
}
