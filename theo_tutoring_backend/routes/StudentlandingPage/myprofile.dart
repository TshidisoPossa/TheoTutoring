import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Only GET requests are supported.'},
    );
  }

  final authorization =
      context.request.headers['authorization'] ??
      context.request.headers['Authorization'];

  try {
    final firebaseUser = await verifyFirebaseToken(authorization);
    final connection = await getConnection();
    final result = await connection.execute(
      '''
      SELECT u.UserId, sp.StudentID, u.Name, u.Email, u.Role, u.AccountStatus
      FROM `User` u
      INNER JOIN StudentProfile sp ON sp.UserID = u.UserId
      WHERE u.FirebaseUid = :uid AND u.Role = 'student'
      LIMIT 1
      ''',
      {'uid': firebaseUser.uid},
    );

    if (result.rows.isEmpty) {
      return Response.json(
        statusCode: 404,
        body: {'error': 'Student account or profile not found.'},
      );
    }

    final row = result.rows.first;
    final accountStatus = row.colByName('AccountStatus');
    if (accountStatus == 'Suspended' || accountStatus == 'Deactivated') {
      return Response.json(
        statusCode: 403,
        body: {'error': 'This account is not active.'},
      );
    }
    return Response.json(
      body: {
        'userId': int.parse(row.colByName('UserId')!),
        'studentId': int.parse(row.colByName('StudentID')!),
        'name': row.colByName('Name'),
        'email': row.colByName('Email'),
        'role': row.colByName('Role'),
        'accountStatus': row.colByName('AccountStatus'),
      },
    );
  } on AuthTokenException catch (error) {
    return Response.json(
      statusCode: 401,
      body: {'error': error.message},
    );
  } catch (error) {
    stderr.writeln('Student identity lookup error: $error');
    return Response.json(
      statusCode: 500,
      body: {'error': 'An unexpected error occurred.'},
    );
  }
}
