import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/header_tutor.dart';
import 'package:theo_tutoring_backend/profile_tutor.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
import 'package:theo_tutoring_backend/schedule_tutor.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// Author Tshidiso Possa
// GET /TutorLandingpage/schedule   (Schedule tab in the bottom navigation bar)
//
// Query string (all optional):
//   tab       = upcoming (default) | new | past | all
//   date      = all (default) | today | tomorrow | week
//   subjectId = 3,5        (the filter icon; leave out for every subject)
//
// Upcoming = Confirmed (paid) sessions that have not ended.
// New      = Pending booking requests from students. Accepting or declining
//            them happens on the Requests tab.
// Sessions come grouped by day, for headings like "Today, 30 Sep (2 sessions)".
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final ScheduleQuery query;
  try {
    query = parseScheduleQuery(context.request.uri.queryParameters);
  } on FormatException catch (e) {
    return jsonError(HttpStatus.badRequest, e.message); // bad tab/date/subject
  }

  final tutor = context.read<TutorSession>();

  try {
    final conn = await getConnection(); // shared DB connection (do not close it)

    // tutor name + profile picture, same helper as every tutor page
    final header = await getTutorHeader(conn, tutor.tutorId);
    if (header == null) {
      return jsonError(HttpStatus.notFound, 'Tutor not found');
    }

    final sessions = await getScheduleSessions(conn, tutor.tutorId, query);
    return Response.json(
      body: {
        'tutor': header, // name + profile picture
        'tab': context.request.uri.queryParameters['tab'] ?? 'upcoming',
        'date': context.request.uri.queryParameters['date'] ?? 'all',
        'subjectIds': query.subjectIds, // filters in use (badge on the icon)
        'counts': await getScheduleCounts(conn, tutor.tutorId), // tab numbers
        'subjects': await getTutorSubjects(conn, tutor.tutorId), // filter list
        'count': sessions.length, // cards on this tab
        'days': groupSessionsByDay(sessions), // cards grouped under each day
      },
    );
  } catch (e) {
    stderr.writeln('Error loading tutor schedule: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not load your schedule. Please try again.',
    );
  }
}
