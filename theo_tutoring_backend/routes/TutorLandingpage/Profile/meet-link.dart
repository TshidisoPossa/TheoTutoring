import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/google_meet.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// POST /TutorLandingpage/Profile/meet-link   (Google Meet card on Profile)
//
// body: {"accessToken": "<Google access token>"}  ->  {"meetConnected": true}
// Connect for tutors who registered before Google Meet, and Reconnect for a
// room that stopped working: creates a new room and replaces
// TutorProfile.MeetLink. Every lesson uses the new link straight away.
Future<Response> onRequest(RequestContext context) =>
    handleProfileMeetLink(context);

/// Optional seams let the route test use a fake database and Google.
Future<Response> handleProfileMeetLink(
  RequestContext context, {
  Future<MySQLConnection> Function() connectionFactory = getConnection,
  Future<String> Function(String accessToken) roomCreator = createMeetRoom,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    );
  }
  final tutor = context.read<TutorSession>();

  try {
    // shared DB connection (do not close it)
    final conn = await connectionFactory();
    return await connectTutorMeet(
      context,
      conn,
      tutor.tutorId,
      roomCreator: roomCreator,
    );
  } catch (e) {
    stderr.writeln('Error connecting Google Meet: $e');
    return jsonError(
      HttpStatus.internalServerError,
      "We couldn't connect Google Meet. Please try again.",
    );
  }
}
