import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';

import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';
import '../../../lib/validator.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(405, 'Method not allowed');
  }

  final FirebaseUser firebaseUser;
  try {
    firebaseUser = await verifyFirebaseToken(
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
    return jsonError(503, 'Authentication service is temporarily unavailable.');
  }

  if (firebaseUser.email == null || firebaseUser.email!.isEmpty) {
    return jsonError(400, 'A Firebase account with an email is required.');
  }

  try {
    final body = await readJsonObject(context);
    final errors = validateTutorRegistration(body);
    if (errors.isNotEmpty) {
      return Response.json(statusCode: 422, body: {'errors': errors});
    }

    final name = (body['name'] as String).trim();
    final phone = (body['phoneNum'] as String?)?.trim() ?? '';
    // The transaction gets its own connection so a stuck registration can't
    // leave the shared connection holding locks for every other request.
    final db = await createIndependentConnection();
    try {
      final existing = await db.execute(
        'SELECT UserId FROM `User` WHERE Email = :email OR FirebaseUid = :uid',
        {'email': firebaseUser.email, 'uid': firebaseUser.uid},
      );
      if (existing.rows.isNotEmpty) {
        return jsonError(409, 'An account with this email already exists.');
      }

      await db.execute('START TRANSACTION');
      try {
        final userResult = await db.execute(
          '''
          INSERT INTO `user`
            (Name, Email, FirebaseUid, PhoneNum, Role, AccountStatus)
          VALUES
            (:name, :email, :uid, :phone, 'tutor', 'Incomplete')
          ''',
          {
            'name': name,
            'email': firebaseUser.email,
            'uid': firebaseUser.uid,
            'phone': phone,
          },
        );
        final userId = userResult.lastInsertID.toInt();
        final tutorResult = await db.execute(
          '''
          INSERT INTO TutorProfile (UserId, VerificationStat)
          VALUES (:userId, 'Pending')
          ''',
          {'userId': userId},
        );
        await db.execute('COMMIT');

        return Response.json(
          statusCode: 201,
          body: {
            'message': 'Step 1 complete! Proceed to your teaching profile.',
            'userId': userId,
            'tutorId': tutorResult.lastInsertID.toInt(),
          },
        );
      } catch (_) {
        // If the connection is already broken, ROLLBACK can fail too; closing
        // the connection below makes MySQL roll back and release the locks.
        try {
          await db.execute('ROLLBACK');
        } catch (_) {}
        rethrow;
      }
    } finally {
      if (db.connected) await db.close();
    }
  } on FormatException catch (error) {
    return jsonError(400, error.message);
  } on MySQLServerException catch (error) {
    if (error.errorCode == 1062) {
      return jsonError(409, 'An account with this email already exists.');
    }
    stderr.writeln('Tutor registration error: $error');
    return jsonError(500, 'Something went wrong. Please try again.');
  } catch (error) {
    stderr.writeln('Tutor registration error: $error');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}

Map<String, String> validateTutorRegistration(Map<String, dynamic> body) {
  final errors = <String, String>{};
  final name = body['name'];
  final nameResult = Validator.validateName(name is String ? name : null);
  if (!nameResult.isValid) errors['name'] = nameResult.error!;

  final phone = body['phoneNum'];
  if (phone != null && phone is! String) {
    errors['phoneNum'] = 'Phone number must be text.';
  } else {
    final phoneResult = Validator.validatePhone(phone as String?);
    if (!phoneResult.isValid) errors['phoneNum'] = phoneResult.error!;
  }
  return errors;
}
