import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/mysql_client.dart';

import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/google_meet.dart';
import '../../../lib/request_utils.dart';
import '../../../lib/tutor_account_status.dart';

// POST /auth/tutor/meet-link  (Tutor registration, Step 3 of 3)
//
// body: {"accessToken": "<Google access token>"}  ->  {"meetConnected": true}
// The Connect Google Meet card. The account is still incomplete here, which
// the TutorLandingpage middleware blocks, so this route checks the Firebase
// token itself, as availability.dart does. The backend then creates the
// tutor's Meet room and saves it in TutorProfile.MeetLink. Connecting again
// makes a new room and replaces the link.

Future<Response> onRequest(RequestContext context) =>
    handleTutorMeetLink(context);

/// Optional seams let the route test use a fake identity, database and
/// Google, while production keeps the normal defaults.
Future<Response> handleTutorMeetLink(
  RequestContext context, {
  Future<FirebaseUser> Function(String?) tokenVerifier = verifyFirebaseToken,
  Future<MySQLConnection> Function() connectionFactory = getConnection,
  Future<String> Function(String accessToken) roomCreator = createMeetRoom,
}) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(405, 'Method not allowed');
  }

  try {
    // ── Verify the Firebase ID token ──
    final FirebaseUser firebaseUser;
    try {
      firebaseUser = await tokenVerifier(
        context.request.headers['Authorization'],
      );
    } on AuthTokenException catch (e) {
      return jsonError(401, e.message);
    }

    final db = await connectionFactory();

    // ── Find the tutor and check they are still registering ──
    final tutorResult = await db.execute(
      '''
      SELECT tp.TutorID, u.AccountStatus
      FROM tutorProfile tp
      INNER JOIN User u ON tp.UserId = u.UserId
      WHERE u.FirebaseUid = :uid AND u.Role = 'tutor'
      ''',
      {'uid': firebaseUser.uid},
    );

    if (tutorResult.rows.isEmpty) {
      return jsonError(
        404,
        'Tutor account not found. Please complete Step 1 first.',
      );
    }

    final row = tutorResult.rows.first;
    if (!canSubmitTutorAvailability(row.colByName('AccountStatus'))) {
      return jsonError(
        403,
        'This account cannot continue tutor registration.',
      );
    }

    return await connectTutorMeet(
      context,
      db,
      int.parse(row.colByName('TutorID')!),
      roomCreator: roomCreator,
    );
  } catch (e) {
    print('❌ Error connecting Google Meet: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}
