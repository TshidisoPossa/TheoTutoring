import 'package:dart_frog/dart_frog.dart';

import '../../../lib/database.dart';
import '../../../lib/env.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';
import '../../../lib/tutor_account_status.dart';
import '../../../lib/validator.dart';

// The tutor is identified from the verified token, never from the body.
// Tutors cannot set a rate. The session rate is fixed by the administrator.

const _experienceOptions = {'0-1', '1-2', '3-5', '5+'};

const _documentTypes = {'pdf', 'jpg', 'jpeg', 'png'};
const _imageTypes = {'jpg', 'jpeg', 'png'};

const _maxSubjects = 10;
const _maxQualifications = 10;
const _maxQualificationLength = 150;
const _maxUrlLength = 500;

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(405, 'Method not allowed');
  }

  try {
    // ── Verify the Firebase ID token ──
    final FirebaseUser firebaseUser;
    try {
      firebaseUser = await verifyFirebaseToken(
        context.request.headers['Authorization'],
      );
    } on AuthTokenException catch (e) {
      return jsonError(401, e.message);
    }

    final cloudName = env['CLOUDINARY_CLOUD_NAME'];
    if (cloudName == null || cloudName.isEmpty) {
      throw StateError('CLOUDINARY_CLOUD_NAME is not set');
    }

    // ── Read and validate the body ──
    final body = await readJsonObject(context);

    if (body.containsKey('hourlyRate')) {
      return jsonError(
        400,
        'Tutors cannot set a rate. The session rate is fixed by the administrator.',
      );
    }

    final bio = optionalString(body, 'bio');
    final bioCheck = Validator.validateBio(bio);
    if (!bioCheck.isValid) {
      return jsonError(400, bioCheck.error);
    }

    final experience = optionalString(body, 'experience');
    if (experience == null || !_experienceOptions.contains(experience)) {
      return jsonError(400, 'Please select your years of tutoring experience.');
    }

    final certificateUrl = optionalString(
      body,
      'certificateUrl',
      maxLength: _maxUrlLength,
    );
    if (certificateUrl == null) {
      return jsonError(400, 'Please upload your certificate.');
    }
    final certificateError = _checkUploadUrl(
      certificateUrl,
      'Certificate',
      _documentTypes,
      cloudName,
    );
    if (certificateError != null) return jsonError(400, certificateError);

    final idDocumentUrl = optionalString(
      body,
      'idDocumentUrl',
      maxLength: _maxUrlLength,
    );
    if (idDocumentUrl != null) {
      final error = _checkUploadUrl(
        idDocumentUrl,
        'ID document',
        _documentTypes,
        cloudName,
      );
      if (error != null) return jsonError(400, error);
    }

    final profilePhotoUrl = optionalString(
      body,
      'profilePhotoUrl',
      maxLength: _maxUrlLength,
    );
    if (profilePhotoUrl != null) {
      final error = _checkUploadUrl(
        profilePhotoUrl,
        'Profile photo',
        _imageTypes,
        cloudName,
      );
      if (error != null) return jsonError(400, error);
    }

    final subjectIds = _parseSubjectIds(body['subjectIds']);
    final qualifications = _parseQualifications(body['qualifications']);

    final db = await getConnection();

    // ── Find the tutor that belongs to this Firebase account ──
    final tutorResult = await db.execute(
      '''
      SELECT tp.TutorID, u.UserId, u.AccountStatus
      FROM TutorProfile tp
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
    final tutorId = int.parse(row.colByName('TutorID')!);
    final userId = int.parse(row.colByName('UserId')!);
    final accountStatus = row.colByName('AccountStatus');

    if (!canUpdateTutorRegistrationProfile(accountStatus)) {
      return jsonError(
        accountStatus?.toLowerCase() == 'active' ||
                accountStatus?.toLowerCase() == 'pending'
            ? 409
            : 403,
        'This account cannot continue tutor registration.',
      );
    }

    // ── Check that every selected subject exists ──
    final subjectParams = <String, dynamic>{
      for (var i = 0; i < subjectIds.length; i++) 's$i': subjectIds[i],
    };
    final placeholders = subjectParams.keys.map((k) => ':$k').join(', ');

    final foundSubjects = await db.execute(
      'SELECT SubjectID FROM Subjects WHERE SubjectID IN ($placeholders)',
      subjectParams,
    );
    if (foundSubjects.rows.length != subjectIds.length) {
      return jsonError(400, 'One or more selected subjects do not exist.');
    }

    // ── Save everything in one transaction ──
    // If any step fails, nothing is changed, so a tutor is never left
    // with their subjects or qualifications deleted.
    await db.transactional((conn) async {
      await conn.execute(
        '''
        UPDATE tutorProfile
        SET Bio = :bio,
            Experience = :experience,
            Certificate = :certificate,
            IdDocument = :idDocument
        WHERE TutorID = :tutorId
        ''',
        {
          'bio': bio,
          'experience': experience,
          'certificate': certificateUrl,
          'idDocument': idDocumentUrl,
          'tutorId': tutorId,
        },
      );

      // The profile photo belongs to User, not TutorProfile.
      await conn.execute(
        'UPDATE User SET ProfilePhoto = :photo WHERE UserId = :userId',
        {'photo': profilePhotoUrl, 'userId': userId},
      );

      await conn.execute(
        'DELETE FROM tutorSubjects WHERE TutorID = :tutorId',
        {'tutorId': tutorId},
      );
      for (final subjectId in subjectIds) {
        await conn.execute(
          '''
          INSERT INTO tutorSubjects (TutorID, SubjectID)
          VALUES (:tutorId, :subjectId)
          ''',
          {'tutorId': tutorId, 'subjectId': subjectId},
        );
      }

      await conn.execute(
        'DELETE FROM qualification WHERE TutorID = :tutorId',
        {'tutorId': tutorId},
      );
      for (final q in qualifications) {
        await conn.execute(
          '''
          INSERT INTO qualification (TutorID, Degree, Institution)
          VALUES (:tutorId, :degree, :institution)
          ''',
          {
            'tutorId': tutorId,
            'degree': q.degree,
            'institution': q.institution,
          },
        );
      }
    });

    return Response.json(
      body: {
        'message': 'Step 2 complete! Proceed to set your availability.',
        'tutorId': tutorId,
      },
    );
  } on FormatException catch (e) {
    return jsonError(400, e.message);
  } catch (e) {
    print('❌ Error in tutor profile: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}

/// Checks that a URL is an HTTPS link to a file in this project's
/// Cloudinary account, with an allowed file type.
/// Returns an error message, or null if the URL is valid.
String? _checkUploadUrl(
  String url,
  String label,
  Set<String> allowedTypes,
  String cloudName,
) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'res.cloudinary.com' ||
      uri.pathSegments.length < 2 ||
      uri.pathSegments.first != cloudName) {
    return '$label must be a file uploaded through the app.';
  }

  final fileName = uri.pathSegments.last;
  final dot = fileName.lastIndexOf('.');
  final extension = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();

  if (!allowedTypes.contains(extension)) {
    final allowed = allowedTypes.map((t) => t.toUpperCase()).join(', ');
    return '$label must be one of these file types: $allowed.';
  }
  return null;
}

/// Reads subjectIds as a list of unique positive whole numbers.
List<int> _parseSubjectIds(Object? value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException('Please select at least one subject.');
  }

  final ids = <int>{};
  for (final item in value) {
    if (item is! int || item <= 0) {
      throw const FormatException(
        'Subject IDs must be positive whole numbers.',
      );
    }
    ids.add(item);
  }

  if (ids.length > _maxSubjects) {
    throw const FormatException('You can select up to $_maxSubjects subjects.');
  }
  return ids.toList();
}

/// Reads qualifications as a list of { degree, institution } entries.
/// Any invalid entry rejects the request instead of being silently dropped.
List<({String degree, String institution})> _parseQualifications(
  Object? value,
) {
  if (value is! List || value.isEmpty) {
    throw const FormatException('Please add at least one qualification.');
  }
  if (value.length > _maxQualifications) {
    throw const FormatException(
      'You can add up to $_maxQualifications qualifications.',
    );
  }

  return [
    for (final item in value)
      if (item is Map<String, dynamic>)
        (
          degree: _requiredQualificationField(item, 'degree'),
          institution: _requiredQualificationField(item, 'institution'),
        )
      else
        throw const FormatException(
          'Each qualification needs a degree and an institution.',
        ),
  ];
}

String _requiredQualificationField(Map<String, dynamic> item, String key) {
  final value = optionalString(item, key, maxLength: _maxQualificationLength);
  if (value == null) {
    throw const FormatException(
      'Each qualification needs a degree and an institution.',
    );
  }
  return value;
}
