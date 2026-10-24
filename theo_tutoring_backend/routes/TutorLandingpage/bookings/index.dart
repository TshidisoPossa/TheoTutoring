import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/tutor_bookings.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// GET /TutorLandingpage/bookings[?status=Confirmed&limit=50]
// Lists the signed-in tutor's own bookings. The folder middleware verifies the
// Firebase token and only lets Active tutors reach this path (Pending tutors
// are limited to the dashboard); the handler re-checks Active as a safeguard.
Future<Response> onRequest(RequestContext context) => handleTutorBookings(
  context,
  repositoryFactory: () async =>
      MySqlTutorBookingsRepository(await getConnection()),
);

Future<Response> handleTutorBookings(
  RequestContext context, {
  required Future<TutorBookingsRepository> Function() repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final tutor = context.read<TutorSession>();
  if (!tutor.isActive) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': 'An active tutor account is required.'},
    );
  }

  final query = context.request.uri.queryParameters;
  final status = query['status'];
  if (status != null && !tutorBookingStatuses.contains(status)) {
    return _badRequest('status must be one of the booking statuses.');
  }
  var limit = defaultTutorBookingsLimit;
  final rawLimit = query['limit'];
  if (rawLimit != null) {
    final parsed = int.tryParse(rawLimit);
    if (parsed == null || parsed < 1 || parsed > maxTutorBookingsLimit) {
      return _badRequest(
        'limit must be between 1 and $maxTutorBookingsLimit.',
      );
    }
    limit = parsed;
  }

  try {
    final repository = await repositoryFactory();
    final bookings = await repository.listForTutor(
      tutor.tutorId,
      status: status,
      limit: limit,
    );
    return Response.json(
      body: {
        'bookings': [for (final b in bookings) b.toJson()],
      },
    );
  } catch (_) {
    stderr.writeln('Tutor bookings database operation failed.');
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {'error': 'Bookings are temporarily unavailable.'},
    );
  }
}

Response _badRequest(String message) =>
    Response.json(statusCode: HttpStatus.badRequest, body: {'error': message});
