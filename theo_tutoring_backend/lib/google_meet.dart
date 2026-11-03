import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

// ---------------------------------------------------------------------------
// GOOGLE MEET
// Each tutor has one reusable Meet room, saved in TutorProfile.MeetLink
// (migration 008). The tutor connects Google once, on registration Step 3 or
// the Profile page: the app gets a one-hour Google access token and the
// backend creates the room as that tutor. The token is used for that one call
// and never stored or logged.
// ---------------------------------------------------------------------------

/// The lesson's link for tutor queries on Booking `b`: an older lesson's own
/// Booking.Link, otherwise the tutor's Meet room. Keeps the alias Link, so
/// the JSON the tutor app reads does not change.
const tutorMeetLinkSql =
    'COALESCE(b.Link, (SELECT ml.MeetLink FROM TutorProfile ml '
    'WHERE ml.TutorID = b.TutorID)) AS Link';

const _spacesUrl = 'https://meet.googleapis.com/v2/spaces';

// The app waits 15 seconds for the backend, so give up on Google first and
// the tutor sees the real message.
const _googleTimeout = Duration(seconds: 10);

// Google says access tokens can grow to 2048 bytes; leave room above that.
const _maxAccessTokenLength = 4096;

/// Thrown when Google refuses the token or the account (HTTP 401 or 403).
class GoogleMeetDenied implements Exception {
  /// Creates the exception.
  const GoogleMeetDenied();
}

/// Thrown when Google could not create the room for any other reason: it
/// is down or busy, the connection failed, or the reply made no sense.
class GoogleMeetUnavailable implements Exception {
  /// Creates the exception.
  const GoogleMeetUnavailable();
}

/// Creates one reusable Meet room as the tutor and returns its link.
/// [accessToken] is used for this one call. Never store or log it.
/// Throws [GoogleMeetDenied] or [GoogleMeetUnavailable].
Future<String> createMeetRoom(
  String accessToken, {
  http.Client? client,
  Duration timeout = _googleTimeout,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .post(
          Uri.parse(_spacesUrl),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: '{}', // empty, so the room keeps Google's default access
        )
        .timeout(timeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const GoogleMeetDenied();
    }
    if (response.statusCode != 200) throw const GoogleMeetUnavailable();

    final decoded = jsonDecode(response.body);
    final link = decoded is Map<String, dynamic> ? decoded['meetingUri'] : null;
    if (link is! String || !link.startsWith('https://meet.google.com/')) {
      throw const GoogleMeetUnavailable();
    }
    return link;
  } on TimeoutException {
    throw const GoogleMeetUnavailable();
  } on http.ClientException {
    throw const GoogleMeetUnavailable(); // connection lost or refused
  } on IOException {
    throw const GoogleMeetUnavailable();
  } on FormatException {
    throw const GoogleMeetUnavailable(); // the reply was not JSON
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Saves [link] as the tutor's Meet room, replacing any earlier one.
Future<void> saveTutorMeetLink(
  MySQLConnection conn,
  int tutorId,
  String link,
) async {
  await conn.execute(
    'UPDATE TutorProfile SET MeetLink = :link WHERE TutorID = :tutorId',
    {'link': link, 'tutorId': tutorId},
  );
}

/// Both meet-link routes end here once they know the tutor: reads
/// {"accessToken": "..."}, creates the room as the tutor, saves its link and
/// replies {"meetConnected": true}. Nothing is saved if Google says no.
Future<Response> connectTutorMeet(
  RequestContext context,
  MySQLConnection conn,
  int tutorId, {
  Future<String> Function(String accessToken) roomCreator = createMeetRoom,
}) async {
  try {
    final body = await readJsonObject(context);
    final accessToken = optionalString(
      body,
      'accessToken',
      maxLength: _maxAccessTokenLength,
    );
    if (accessToken == null) {
      return jsonError(
        HttpStatus.badRequest,
        "Google Meet wasn't connected. Please try again.",
      );
    }

    final link = await roomCreator(accessToken);
    await saveTutorMeetLink(conn, tutorId, link);
    return Response.json(body: {'meetConnected': true});
  } on FormatException catch (e) {
    return jsonError(HttpStatus.badRequest, e.message);
  } on GoogleMeetDenied {
    // Not 401/403: the app reads those as a problem with the tutor's own
    // TheoTutoring sign-in.
    return jsonError(
      HttpStatus.badRequest,
      "We couldn't create a Meet room with this account. "
      'Try another Google account.',
    );
  } on GoogleMeetUnavailable {
    return jsonError(
      HttpStatus.serviceUnavailable,
      "We couldn't connect Google Meet. Please try again.",
    );
  }
}
