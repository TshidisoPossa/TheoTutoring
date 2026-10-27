import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/exception.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/profile_tutor.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// PUT /TutorLandingpage/Profile/availability-dates   (Save in the date sheet)
//
// Changes ONE date in the availability calendar:
//   {"date": "2026-11-13", "mode": "off"}      the tutor takes the day off
//   {"date": "2026-11-14", "mode": "custom",
//    "times": [{"startTime": "09:00", "endTime": "12:00"}]}   only these hours
//   {"date": "2026-11-14", "mode": "usual"}    back to the weekly hours
// Students see the change straight away when they book. A change that takes
// away a booked lesson's time is refused (409).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final tutor = context.read<TutorSession>();

  final DateAvailabilityChange change;
  try {
    change = parseDateAvailability(
      await readJsonObject(context),
      today: johannesburgDate(DateTime.now().toUtc()),
    );
  } on FormatException catch (e) {
    return jsonError(HttpStatus.badRequest, e.message);
  }

  try {
    final conn = await getConnection(); // shared DB connection (do not close)
    await saveDateAvailability(conn, tutor.tutorId, change);
    return Response.json(
      body: {
        'message': _savedMessage(change),
        'availabilityCalendar': await getAvailabilityCalendar(
          conn,
          tutor.tutorId,
        ),
      },
    );
  } on AvailabilityInUseException catch (e) {
    return jsonError(HttpStatus.conflict, e.message); // a booked lesson
  } on MySQLServerException catch (e) {
    stderr.writeln('Error saving a date in the availability calendar: $e');
    return jsonError(
      HttpStatus.serviceUnavailable,
      e.errorCode == 1146 // table missing
          ? 'Date changes are not set up yet (database migration 007).'
          : 'Could not save this date. Please try again.',
    );
  } catch (e) {
    stderr.writeln('Error saving a date in the availability calendar: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not save this date. Please try again.',
    );
  }
}

String _savedMessage(DateAvailabilityChange change) {
  final date = change.date.iso;
  return switch (change.mode) {
    DateAvailabilityMode.off => 'Day off saved for $date.',
    DateAvailabilityMode.custom => 'Your hours for $date are saved.',
    DateAvailabilityMode.usual => '$date is back to your usual hours.',
  };
}
