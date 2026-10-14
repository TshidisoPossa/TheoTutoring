import 'dart:io'; // gives us HttpStatus codes
import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/profile_tutor.dart'; // update + read the grid
import 'package:theo_tutoring_backend/tutorlanding_session.dart'; // TutorSession

// PUT /TutorLandingpage/Profile/availability   (the Save button)
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    ); // only PUT is allowed
  }
  final tutor = context.read<TutorSession>(); // who is calling

  // body looks like {"availability": {"Monday": ["Morning", "Evening"], ...}}
  final dynamic body;
  try {
    body = await context.request.json(); // read the JSON body
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Body must be valid JSON'},
    );
  }
  if (body is! Map || body['availability'] is! Map) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Send {"availability": {"Monday": ["Morning"]}}'},
    );
  }

  final selected = <String, List<String>>{}; // day -> ticked periods
  for (final entry in (body['availability'] as Map).entries) {
    final periods = entry.value; // e.g. ["Morning", "Evening"]
    if (periods is! List) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Each day must be a list of periods'},
      );
    }
    selected[entry.key.toString()] = periods.map((p) => p.toString()).toList();
  }

  final conn = await getConnection(); // shared DB connection (do not close it)
  try {
    await updateTutorAvailability(
      conn,
      tutor.tutorId,
      selected,
    ); // replace the grid
  } on ArgumentError catch (e) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': e.message.toString()}, // unknown day or period
    );
  }
  return Response.json(
    body: {
      'availability': await getTutorAvailability(
        conn,
        tutor.tutorId,
      ), // the saved grid
    },
  );
}
