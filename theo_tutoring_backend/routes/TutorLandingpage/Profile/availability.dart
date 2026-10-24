import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/profile_tutor.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// PUT /TutorLandingpage/Profile/availability   (the Save button)
//
// body: {"availability": {"Monday": ["Morning", "Evening"], "Friday": ["Afternoon"]}}
// Days are Monday to Saturday; periods are Morning (08:00-12:00),
// Afternoon (12:00-17:00) and Evening (17:00-20:00). The whole grid is
// replaced; a day that is left out has no availability.
// A period that has an upcoming booking cannot be removed (409).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    );
  }
  final tutor = context.read<TutorSession>();

  final Map<String, List<String>> selected; // day -> ticked periods
  try {
    selected = _readGrid(await readJsonObject(context));
  } on FormatException catch (e) {
    return jsonError(HttpStatus.badRequest, e.message);
  }

  try {
    final conn =
        await getConnection(); // shared DB connection (do not close it)
    await updateTutorAvailability(conn, tutor.tutorId, selected);
    return Response.json(
      body: {
        'message': 'Availability saved.',
        'availability': await getTutorAvailability(
          conn,
          tutor.tutorId,
        ), // the saved grid
      },
    );
  } on ArgumentError catch (e) {
    // unknown day or period, or nothing ticked
    return jsonError(HttpStatus.badRequest, e.message.toString());
  } on AvailabilityInUseException catch (e) {
    return jsonError(HttpStatus.conflict, e.message); // booked slot removed
  } catch (e) {
    stderr.writeln('Error saving tutor availability: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not save your availability. Please try again.',
    );
  }
}

// {"availability": {"Monday": ["Morning"]}} -> {"Monday": ["Morning"]}
Map<String, List<String>> _readGrid(Map<String, dynamic> body) {
  final grid = body['availability'];
  if (grid is! Map) {
    throw const FormatException(
      'Send {"availability": {"Monday": ["Morning"]}}',
    );
  }
  final selected = <String, List<String>>{};
  for (final entry in grid.entries) {
    final periods = entry.value; // e.g. ["Morning", "Evening"]
    if (periods is! List || periods.any((p) => p is! String)) {
      throw const FormatException('Each day must be a list of periods');
    }
    selected[entry.key.toString()] = periods.cast<String>();
  }
  return selected;
}
