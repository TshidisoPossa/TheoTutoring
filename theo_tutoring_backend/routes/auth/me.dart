import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

// GET /auth/me  ->  who is signed in, so the app knows where to send them.
//
// {"userId": 1, "role": "student", "accountStatus": "Active", "name": "...",
//  "email": "...", "emailVerified": false, "studentId": 4}
// (tutorId or adminId instead of studentId for those roles)
//
// 404 means the Firebase account exists but registration never created the
// MySQL user (for example the app closed half-way through sign-up).
// This route only says who the user is; every other route still checks the
// role and account status itself before doing anything.

Future<Response> onRequest(RequestContext context) => handleAuthMe(context);

/// Optional seams let the route test use a fake identity and database.
Future<Response> handleAuthMe(
  RequestContext context, {
  Future<FirebaseUser> Function(String?) tokenVerifier = verifyFirebaseToken,
  Future<MySQLConnection> Function() connectionFactory = getConnection,
}) async {
  if (context.request.method != HttpMethod.get) {
    return jsonError(405, 'Only GET requests are supported.');
  }

  final FirebaseUser firebaseUser;
  try {
    firebaseUser = await tokenVerifier(
      context.request.headers['Authorization'] ??
          context.request.headers['authorization'],
    );
  } on AuthTokenException catch (error) {
    return jsonError(401, error.message);
  } on StateError catch (error) {
    stderr.writeln('Firebase configuration error: $error');
    return jsonError(
      500,
      'Authentication service is not configured correctly.',
    );
  } catch (error) {
    stderr.writeln('Firebase authentication error: $error');
    return jsonError(
      503,
      'Authentication service is temporarily unavailable.',
    );
  }

  try {
    final db = await connectionFactory();
    final result = await db.execute(
      '''
      SELECT u.UserId, u.Name, u.Email, u.Role, u.AccountStatus,
             sp.StudentID, tp.TutorID, a.AdminID
      FROM `User` u
      LEFT JOIN StudentProfile sp ON sp.UserID = u.UserId
      LEFT JOIN TutorProfile tp ON tp.UserID = u.UserId
      LEFT JOIN Admin a ON a.UserId = u.UserId
      WHERE u.FirebaseUid = :uid
      LIMIT 1
      ''',
      {'uid': firebaseUser.uid},
    );

    if (result.rows.isEmpty) {
      return jsonError(404, 'Your registration is not complete.');
    }

    final row = result.rows.first;
    final role = row.str('Role');
    // The profile row that goes with the role (missing if registration
    // stopped before it was created).
    final profileKey = switch (role) {
      'student' => ('studentId', row.str('StudentID')),
      'tutor' => ('tutorId', row.str('TutorID')),
      'admin' => ('adminId', row.str('AdminID')),
      _ => null,
    };
    if (profileKey == null || profileKey.$2 == null) {
      return jsonError(404, 'Your registration is not complete.');
    }

    return Response.json(
      body: {
        'userId': int.parse(row.reqStr('UserId')),
        'role': role,
        'accountStatus': row.str('AccountStatus'),
        'name': row.str('Name'),
        'email': row.str('Email'),
        'emailVerified': firebaseUser.emailVerified,
        profileKey.$1: int.parse(profileKey.$2!),
      },
    );
  } catch (error) {
    stderr.writeln('Signed-in user lookup failed: $error');
    return jsonError(500, 'An unexpected error occurred.');
  }
}
