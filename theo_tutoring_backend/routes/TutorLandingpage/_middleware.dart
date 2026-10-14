import 'dart:io';

import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import '../../lib/database.dart'; // getConnection()
import '../../lib/firebase_auth.dart';
import '../../lib/tutor_account_status.dart';
import '../../lib/tutorlanding_session.dart'; // TutorSession

//auther Tshidiso Possa

// Finds an active tutor profile belonging to a Firebase UID.
Future<int?> _findActiveTutorId(String firebaseUid) async {
  final conn = await getConnection(); // shared DB connection (do not close it)
  final result = await conn.execute(
    'SELECT tp.TutorID, u.AccountStatus FROM TutorProfile tp ' // tutor row
    'INNER JOIN `User` u ON tp.UserId = u.UserId ' // link tutor to user
    "WHERE u.FirebaseUid = :uid AND u.Role = 'tutor'", // verified tutor UID
    {'uid': firebaseUid},
  );
  if (result.rows.isEmpty) return null; // this user is not a tutor
  final row = result.rows.first.assoc();
  if (!canAccessTutorLandingPage(row['AccountStatus'])) return null;
  return int.parse(row['TutorID']!); // TutorID as int
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
    final tutorId = await _findActiveTutorId(uid); // map UID to active TutorID
    if (tutorId == null) {
      return Response.json(
        statusCode: 403,
        body: {'error': 'An active tutor account is required.'},
      );
    }
    return handler(
      context.provide<TutorSession>(
        () => TutorSession(uid, tutorId),
      ), // make session available to routes
    );
  };
}
