import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:bcrypt/bcrypt.dart';
import '../../../lib/database.dart';
import '../../../lib/jwt_helper.dart';
import '../../../lib/validator.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Method not allowed'},
    );
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;

    // ── Validate all fields ──
    final nameCheck = Validator.validateName(body['name'] as String?);
    if (!nameCheck.isValid) {
      return Response.json(
        statusCode: 400,
        body: {'error': nameCheck.error},
      );
    }

    final emailCheck = Validator.validateEmail(body['email'] as String?);
    if (!emailCheck.isValid) {
      return Response.json(
        statusCode: 400,
        body: {'error': emailCheck.error},
      );
    }

    final passwordCheck = Validator.validatePassword(body['password'] as String?);
    if (!passwordCheck.isValid) {
      return Response.json(
        statusCode: 400,
        body: {'error': passwordCheck.error},
      );
    }

    final phoneCheck = Validator.validatePhone(body['phoneNum'] as String?);
    if (!phoneCheck.isValid) {
      return Response.json(
        statusCode: 400,
        body: {'error': phoneCheck.error},
      );
    }

    final name = (body['name'] as String).trim();
    final email = (body['email'] as String).toLowerCase().trim();
    final password = body['password'] as String;
    final phoneNum = body['phoneNum'] as String? ?? '';

    final db = await getConnection();

    // ── Check if email already exists ──
    final existing = await db.execute(
      'SELECT UserId FROM User WHERE Email = :email',
      {'email': email},
    );

    if (existing.rows.isNotEmpty) {
      return Response.json(
        statusCode: 409,
        body: {'error': 'An account with this email already exists'},
      );
    }

    // ── Hash password ──
    final hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());

    // ── Insert user ──
    final userResult = await db.execute(
      '''
      INSERT INTO User (Name, Email, Password, PhoneNum, Role, AccountStatus)
      VALUES (:name, :email, :password, :phone, 'tutor', 'pending')
      ''',
      {
        'name': name,
        'email': email,
        'password': hashedPassword,
        'phone': phoneNum,
      },
    );

    final userId = userResult.lastInsertID.toInt();

    // ── Create empty tutor profile ──
    final profileResult = await db.execute(
      '''
      INSERT INTO TutorProfile (UserId, VerificationStat)
      VALUES (:userId, 'pending')
      ''',
      {'userId': userId},
    );

    final tutorId = profileResult.lastInsertID.toInt();

    // ── Generate JWT ──
    final token = generateToken(userId, 'tutor');

    return Response.json(
      statusCode: 201,
      body: {
        'message': 'Step 1 complete! Proceed to your teaching profile.',
        'token': token,
        'userId': userId,
        'tutorId': tutorId,
      },
    );
  } catch (e) {
    print('❌ Error in register: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Something went wrong. Please try again.'},
    );
  }
}