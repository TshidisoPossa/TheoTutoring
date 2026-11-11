import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/cloudinary_url.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

// GET   /students/profile  ->  what the student's Profile tab shows.
// PATCH /students/profile  ->  saves Edit Profile.
//
// GET answers:
// {"name": "Lerato Dube", "email": "lerato@example.com",
//  "photo": "https://res.cloudinary.com/...",
//  "institution": "University of Pretoria",
//  "subjectsOfInterest": ["Mathematics", "Physics"]}
//
// photo and institution are null when blank (older accounts have no
// institution). Dark Mode is not here: it is saved on the device.
//
// PATCH takes any of these fields and changes only the ones sent:
//   name, photo, institution, subjectsOfInterest
// Save Changes sends the edited fields; the camera badge sends only photo.
// The answer is the updated profile (as GET) plus a "message".

const _maxName = 100; // User.Name
const _maxPhoto = 500; // User.ProfilePhoto
const _maxInstitution = 150; // StudentProfile.Institution
const _maxSubjectsText = 255; // StudentProfile.Subject_of_interest
const _maxSubjects = 10;
const _maxSubjectName = 100;

Future<Response> onRequest(RequestContext context) =>
    handleStudentProfile(context);

/// Optional seams let the route test use a fake identity, database and
/// Cloudinary account.
Future<Response> handleStudentProfile(
  RequestContext context, {
  Future<FirebaseUser> Function(String?) tokenVerifier = verifyFirebaseToken,
  Future<MySQLConnection> Function() connectionFactory = getConnection,
  String Function() cloudName = cloudinaryCloudName,
}) async {
  final method = context.request.method;
  if (method != HttpMethod.get && method != HttpMethod.patch) {
    return jsonError(405, 'Only GET and PATCH requests are supported.');
  }

  final FirebaseUser firebaseUser;
  try {
    firebaseUser = await tokenVerifier(
      context.request.headers['Authorization'] ??
          context.request.headers['authorization'],
    );
  } on AuthTokenException catch (error) {
    return jsonError(401, error.message);
  } catch (error) {
    stderr.writeln('Student profile sign-in failed: $error');
    return jsonError(
      503,
      'Authentication service is temporarily unavailable.',
    );
  }

  // Check the body before touching the database
  _ProfileChanges? changes;
  if (method == HttpMethod.patch) {
    try {
      changes = _ProfileChanges.parse(
        await readJsonObject(context),
        cloudName,
      );
    } on FormatException catch (error) {
      return jsonError(400, error.message);
    }
  }

  try {
    final db = await connectionFactory();
    final before = await _loadProfile(db, firebaseUser.uid);
    if (before == null) {
      return jsonError(403, 'An active student account is required.');
    }
    if (changes == null) return Response.json(body: before.json);

    await changes.save(db, before.userId);
    final after = await _loadProfile(db, firebaseUser.uid);
    return Response.json(
      body: {
        ...?after?.json,
        'message': changes.onlyPhoto
            ? 'Profile photo updated.'
            : 'Your profile has been saved.',
      },
    );
  } catch (error, stackTrace) {
    stderr.writeln('Student profile failed: $error\n$stackTrace');
    return jsonError(
      500,
      method == HttpMethod.get
          ? 'Your profile is temporarily unavailable.'
          : 'Your profile could not be saved. Please try again.',
    );
  }
}

class _Profile {
  const _Profile(this.userId, this.json);

  final String userId;
  final Map<String, Object?> json;
}

Future<_Profile?> _loadProfile(MySQLConnection db, String uid) async {
  final result = await db.execute(
    '''
    SELECT u.UserId, u.Name, u.Email, u.ProfilePhoto, sp.Institution,
           sp.Subject_of_interest
    FROM `user` u
    INNER JOIN studentprofile sp ON sp.UserID = u.UserId
    WHERE u.FirebaseUid = :uid
      AND u.Role = 'student'
      AND u.AccountStatus = 'Active'
    LIMIT 1
    ''',
    {'uid': uid},
  );
  if (result.rows.isEmpty) return null;

  final row = result.rows.first;
  return _Profile(row.str('UserId') ?? '', {
    'name': row.str('Name'),
    'email': row.str('Email'),
    'photo': _blankToNull(row.str('ProfilePhoto')),
    'institution': _blankToNull(row.str('Institution')),
    'subjectsOfInterest': _splitList(row.str('Subject_of_interest')),
  });
}

/// The fields a PATCH changes; null means "leave as it is".
class _ProfileChanges {
  _ProfileChanges._({this.name, this.photo, this.institution, this.subjects});

  /// Throws a FormatException with a message for the student.
  factory _ProfileChanges.parse(
    Map<String, dynamic> body,
    String Function() cloudName,
  ) {
    final name = _requiredText(body, 'name', 'Your name', _maxName);
    final institution = _requiredText(
      body,
      'institution',
      'Your school or university',
      _maxInstitution,
    );

    String? photo;
    if (body.containsKey('photo')) {
      photo = optionalString(body, 'photo', maxLength: _maxPhoto);
      if (photo == null) throw const FormatException('Please choose a photo.');
      final error = checkCloudinaryUrl(
        photo,
        'Profile photo',
        cloudinaryImageTypes,
        cloudName(),
      );
      if (error != null) throw FormatException(error);
    }

    String? subjects;
    if (body.containsKey('subjectsOfInterest')) {
      final list = _textList(body['subjectsOfInterest'], 'subjectsOfInterest');
      if (list.isEmpty) {
        throw const FormatException('Choose at least one subject.');
      }
      if (list.length > _maxSubjects) {
        throw const FormatException(
          'Choose up to $_maxSubjects subjects of interest.',
        );
      }
      for (final subject in list) {
        if (subject.length > _maxSubjectName || subject.contains(',')) {
          throw const FormatException('A subject name is not valid.');
        }
      }
      subjects = list.join(', ');
      if (subjects.length > _maxSubjectsText) {
        throw const FormatException(
          'Your subjects of interest are too long. Remove one and try again.',
        );
      }
    }

    final changes = _ProfileChanges._(
      name: name,
      photo: photo,
      institution: institution,
      subjects: subjects,
    );
    if (changes._isEmpty) {
      throw const FormatException('Nothing to update.');
    }
    return changes;
  }

  final String? name;
  final String? photo;
  final String? institution;
  final String? subjects;

  bool get _isEmpty =>
      name == null && photo == null && institution == null && subjects == null;

  bool get onlyPhoto =>
      photo != null && name == null && institution == null && subjects == null;

  Future<void> save(MySQLConnection db, String userId) async {
    final userSets = [
      if (name != null) 'Name = :name',
      if (photo != null) 'ProfilePhoto = :photo',
    ];
    final profileSets = [
      if (institution != null) 'Institution = :institution',
      if (subjects != null) 'Subject_of_interest = :subjects',
    ];
    if (userSets.isNotEmpty) {
      await db.execute(
        'UPDATE `user` SET ${userSets.join(', ')} WHERE UserId = :userId',
        {
          'userId': userId,
          if (name != null) 'name': name,
          if (photo != null) 'photo': photo,
        },
      );
    }
    if (profileSets.isNotEmpty) {
      await db.execute(
        'UPDATE studentprofile SET ${profileSets.join(', ')} '
        'WHERE UserID = :userId',
        {
          'userId': userId,
          if (institution != null) 'institution': institution,
          if (subjects != null) 'subjects': subjects,
        },
      );
    }
  }
}

/// A field that may be left out, but not sent blank.
String? _requiredText(
  Map<String, dynamic> body,
  String key,
  String label,
  int maxLength,
) {
  if (!body.containsKey(key)) return null;
  final value = body[key];
  if (value != null && value is! String) {
    throw FormatException('$key must be text.');
  }
  final trimmed = (value as String? ?? '').trim();
  if (trimmed.isEmpty) throw FormatException('$label cannot be empty.');
  if (trimmed.length > maxLength) {
    throw FormatException('$label must be $maxLength characters or fewer.');
  }
  return trimmed;
}

/// A JSON list of text, trimmed, without blanks or repeats.
List<String> _textList(Object? value, String key) {
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key must be a list of text.');
  }
  final seen = <String>{};
  return [
    for (final item in value.cast<String>())
      if (item.trim().isNotEmpty && seen.add(item.trim().toLowerCase()))
        item.trim(),
  ];
}

/// "Maths, Statistics ,Accounting" -> ["Maths", "Statistics", "Accounting"]
List<String> _splitList(String? value) => [
  for (final part in (value ?? '').split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
