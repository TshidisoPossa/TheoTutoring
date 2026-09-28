import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';
import '../../../lib/validator.dart';

// POST /auth/tutor/profile
// Body: {
//   firebaseUid,
//   tutorId,
//   bio,
//   experience,
//   hourlyRate,
//   certificateUrl,
//   profilePhotoUrl,   ← NEW: Firebase Storage URL of profile photo
//   subjectIds,
//   qualifications
// }
// Note: Auth is verified via Firebase UID (no JWT)

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Method not allowed'},
    );
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;

    // ── Verify Firebase UID ──
    final firebaseUid = body['firebaseUid'] as String?;
    if (firebaseUid == null || firebaseUid.trim().isEmpty) {
      return Response.json(
        statusCode: 401,
        body: {'error': 'Unauthorised. Firebase UID is required.'},
      );
    }

    final tutorId = body['tutorId'] as int?;
    if (tutorId == null) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'tutorId is required'},
      );
    }

    // ── Validate fields ──
    final bioCheck = Validator.validateBio(body['bio'] as String?);
    if (!bioCheck.isValid) {
      return Response.json(
        statusCode: 400,
        body: {'error': bioCheck.error},
      );
    }

    final rateCheck = Validator.validateHourlyRate(body['hourlyRate']);
    if (!rateCheck.isValid) {
      return Response.json(
        statusCode: 400,
        body: {'error': rateCheck.error},
      );
    }

    final subjectCheck = Validator.validateSubjects(
      body['subjectIds'] as List?,
    );
    if (!subjectCheck.isValid) {
      return Response.json(
        statusCode: 400,
        body: {'error': subjectCheck.error},
      );
    }

    final bio = (body['bio'] as String).trim();
    final experience = body['experience'] as String? ?? '';
    final hourlyRate = body['hourlyRate'];
    final certificateUrl = body['certificateUrl'] as String? ?? '';
    final profilePhotoUrl = body['profilePhotoUrl'] as String? ?? '';
    final subjectIds = (body['subjectIds'] as List).cast<int>();
    final qualifications =
        (body['qualifications'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final db = await getConnection();

    // ── Verify firebaseUid matches the tutorId ──
    final tutorCheck = await db.execute(
      '''
      SELECT tp.TutorID FROM TutorProfile tp
      INNER JOIN User u ON tp.UserId = u.UserId
      WHERE tp.TutorID = :tutorId AND u.FirebaseUid = :firebaseUid
      ''',
      {
        'tutorId': tutorId,
        'firebaseUid': firebaseUid,
      },
    );

    if (tutorCheck.rows.isEmpty) {
      return Response.json(
        statusCode: 403,
        body: {'error': 'You are not authorised to update this profile'},
      );
    }

    // ── Update TutorProfile (including ProfilePhotoUrl) ──
    await db.execute(
      '''
      UPDATE TutorProfile
      SET Bio = :bio,
          Experience = :experience,
          HourlyRate = :hourlyRate,
          Certificate = :certificate,
          ProfilePhotoUrl = :profilePhotoUrl
      WHERE TutorID = :tutorId
      ''',
      {
        'bio': bio,
        'experience': experience,
        'hourlyRate': hourlyRate,
        'certificate': certificateUrl,
        'profilePhotoUrl': profilePhotoUrl,
        'tutorId': tutorId,
      },
    );

    // ── Clear old subjects and insert new ones ──
    await db.execute(
      'DELETE FROM TutorSubjects WHERE TutorID = :tutorId',
      {'tutorId': tutorId},
    );

    for (final subjectId in subjectIds) {
      await db.execute(
        '''
        INSERT IGNORE INTO TutorSubjects (TutorID, SubjectID)
        VALUES (:tutorId, :subjectId)
        ''',
        {'tutorId': tutorId, 'subjectId': subjectId},
      );
    }

    // ── Clear old qualifications and insert new ones ──
    await db.execute(
      'DELETE FROM Qualification WHERE TutorID = :tutorId',
      {'tutorId': tutorId},
    );

    for (final qual in qualifications) {
      final degree = (qual['degree'] as String?)?.trim();
      final institution = (qual['institution'] as String?)?.trim();
      if (degree != null &&
          degree.isNotEmpty &&
          institution != null &&
          institution.isNotEmpty) {
        await db.execute(
          '''
          INSERT INTO Qualification (TutorID, Degree, Institution)
          VALUES (:tutorId, :degree, :institution)
          ''',
          {
            'tutorId': tutorId,
            'degree': degree,
            'institution': institution,
          },
        );
      }
    }

    return Response.json(
      statusCode: 200,
      body: {
        'message': 'Step 2 complete! Proceed to set your availability.',
        'tutorId': tutorId,
      },
    );
  } catch (e) {
    print('❌ Error in profile: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Something went wrong. Please try again.'},
    );
  }
}