import 'dart:io';

import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import '../../lib/database.dart'; // getConnection()
import '../../lib/firebase_auth.dart';
import '../../lib/tutor_account_status.dart';
import '../../lib/tutor_presence.dart'; // markTutorActive
import '../../lib/tutorlanding_session.dart'; // TutorSession

// The dashboard is the only tutor page a Pending or Rejected tutor may open,
// so they can see their application status (all other routes need Active).
// Its bell icon opens the notifications, so those are allowed too.
// A Pending tutor may also complete their profile while they wait
// (project documentation 4.3 / business rule 5).

const _dashboardPath = '/TutorLandingpage/LandingPageScreen';
const _notificationsPath = '/TutorLandingpage/notifications';
const _profilePath = '/TutorLandingpage/Profile';
const _presencePath = '/TutorLandingpage/presence';

bool _pendingTutorMayOpen(Uri uri) {
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  return path == _dashboardPath ||
      path == _presencePath ||
      path == _notificationsPath ||
      path.startsWith('$_notificationsPath/') ||
      path == _profilePath ||
      path.startsWith('$_profilePath/');
}

// Finds the tutor profile belonging to a Firebase UID.
Future<({int tutorId, String status})?> _findTutor(String firebaseUid) async {
  final conn = await getConnection(); // shared DB connection (do not close it)
  final result = await conn.execute(
    'SELECT tp.TutorID, u.AccountStatus FROM TutorProfile tp ' // tutor row
    'INNER JOIN `User` u ON tp.UserID = u.UserId ' // link tutor to user
    "WHERE u.FirebaseUid = :uid AND u.Role = 'tutor'", // verified tutor UID
    {'uid': firebaseUid},
  );
  if (result.rows.isEmpty) return null; // this user is not a tutor
  final row = result.rows.first.assoc();
  return (
    tutorId: int.parse(row['TutorID']!), // TutorID as int
    status: row['AccountStatus'] ?? '',
  );
}

// Runs before every route under /tutor
Handler middleware(Handler handler) {
  return (context) async {
    final header =
        context.request.headers['Authorization'] ??
        ''; // read the Authorization header
    if (!header.startsWith('Bearer ')) {
      return Response.json(
        statusCode: 401,
        body: {'error': 'Missing token'},
      ); // no token sent
    }
    final FirebaseUser user;
    try {
      user = await verifyFirebaseToken(header);
    } on AuthTokenException {
      return Response.json(
        statusCode: 401,
        body: {'error': 'Invalid token'},
      ); // bad token
    } on StateError {
      return Response.json(
        statusCode: 500,
        body: {'error': 'Authentication service is not configured correctly.'},
      );
    } catch (_) {
      stderr.writeln('Firebase authentication failed unexpectedly.');
      return Response.json(
        statusCode: 503,
        body: {'error': 'Authentication service is temporarily unavailable.'},
      );
    }
    final uid = user.uid;
    final tutor = await _findTutor(uid); // map UID to TutorID + status
    final uri = context.request.uri;
    final canOpenTutorRoute =
        tutor != null && canAccessTutorRoute(tutor.status, uri);
    if (tutor == null || !canOpenTutorRoute) {
      return Response.json(
        statusCode: 403,
        body: {'error': 'An active tutor account is required.'},
      );
    }
    // Any tutor request means they are using the app ("Available Now" on
    // the student's Tutor Profile). Never fail the request over it.
    try {
      await markTutorActive(await getConnection(), tutor.tutorId);
    } catch (e) {
      stderr.writeln('Could not record tutor ${tutor.tutorId} activity: $e');
    }
    return handler(
      context.provide<TutorSession>(
        () => TutorSession(uid, tutor.tutorId, accountStatus: tutor.status),
      ), // make session available to routes
    );
  };
}
