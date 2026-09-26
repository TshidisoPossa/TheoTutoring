import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
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

  // ── Verify JWT ──
  final authHeader = context.request.headers['Authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Unauthorised. Please complete Steps 1 and 2 first.'},
    );
  }

  final token = authHeader.substring(7);
  final payload = verifyToken(token);
  if (payload == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Invalid or expired session. Please start again.'},
    );
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;

    final tutorId = body['tutorId'] as int?;
    if (tutorId == null) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'tutorId is required'},
      );
    }

    // ── Validate availability slots ──
    final availCheck = Validator.validateAvailability(
      body['availability'] as List?,
    );
    if (!availCheck.isValid) {
      return Response.json(
        statusCode: 400,
        body: {'error': availCheck.error},
      );
    }

    final slots = (body['availability'] as List)
        .cast<Map<String, dynamic>>();

    final db = await getConnection();

    // ── Verify tutorId belongs to the JWT user ──
    final tutorCheck = await db.execute(
      '''
      SELECT TutorID FROM TutorProfile
      WHERE TutorID = :tutorId AND UserId = :userId
      ''',
      {
        'tutorId': tutorId,
        'userId': payload['userId'],
      },
    );

    if (tutorCheck.rows.isEmpty) {
      return Response.json(
        statusCode: 403,
        body: {'error': 'You are not authorised to update this profile'},
      );
    }

    // ── Clear old availability and insert new slots ──
    await db.execute(
      'DELETE FROM TutAvailability WHERE TutorID = :tutorId',
      {'tutorId': tutorId},
    );

    for (final slot in slots) {
      await db.execute(
        '''
        INSERT INTO TutAvailability (TutorID, Day, StartTime, EndTime)
        VALUES (:tutorId, :day, :startTime, :endTime)
        ''',
        {
          'tutorId': tutorId,
          'day': slot['day'],
          'startTime': slot['startTime'],
          'endTime': slot['endTime'],
        },
      );
    }

    // ── Mark registration as fully submitted ──
    await db.execute(
      '''
      UPDATE User SET AccountStatus = 'pending'
      WHERE UserId = :userId
      ''',
      {'userId': payload['userId']},
    );

    return Response.json(
      statusCode: 201,
      body: {
        'message': 'Registration complete! Your application is under review. '
            'You will be notified once an admin approves your account.',
        'tutorId': tutorId,
        'status': 'pending',
      },
    );
  } catch (e) {
    print('❌ Error in availability: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Something went wrong. Please try again.'},
    );
  }
}