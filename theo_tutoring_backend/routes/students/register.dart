import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';

import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

const _requiredFields = <String>[
  'fullName',
  'email',
  'phone',
  'address',
  'institutionYear',
  'course',
  'tutoringModule',
];

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Only POST requests are supported.'},
    );
  }

  final authorization =
      context.request.headers['authorization'] ??
      context.request.headers['Authorization'];
  if (authorization == null || !authorization.startsWith('Bearer ')) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'A Firebase ID token is required.'},
    );
  }

  final firebaseUid = await verifyFirebaseToken(authorization.substring(7));
  if (firebaseUid == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Invalid or expired Firebase ID token.'},
    );
  }

  late final dynamic body;
  try {
    body = jsonDecode(await context.request.body());
  } on FormatException {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Request body must be valid JSON.'},
    );
  }

  if (body is! Map<String, dynamic>) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Request body must be a JSON object.'},
    );
  }

  final errors = validateStudentRegistration(body);
  if (errors.isNotEmpty) {
    return Response.json(statusCode: 422, body: {'errors': errors});
  }

  final fullName = (body['fullName'] as String).trim();
  final email = (body['email'] as String).trim().toLowerCase();
  final phone = (body['phone'] as String).trim();
  final address = (body['address'] as String).trim();
  final course = (body['course'] as String).trim();
  final tutoringModule = (body['tutoringModule'] as String).trim();
  final institutionYear = (body['institutionYear'] as String).trim();
  final profilePhotoUrl = _optionalUrl(body['profilePhotoUrl']);
  final proofOfRegistrationUrl = _optionalUrl(
    body['proofOfRegistrationUrl'],
  );

  try {
    final connection = await getConnection();
    return await createStudentRecords(
      connection,
      firebaseUid: firebaseUid,
      fullName: fullName,
      email: email,
      phone: phone,
      address: address,
      course: course,
      tutoringModule: tutoringModule,
      institutionYear: institutionYear,
      profilePhotoUrl: profilePhotoUrl,
      proofOfRegistrationUrl: proofOfRegistrationUrl!,
    );
  } on MySQLServerException catch (error) {
    if (error.errorCode == 1062) {
      return Response.json(
        statusCode: 409,
        body: {
          'error': 'An account with this email or Firebase UID already exists.',
        },
      );
    }
    stderr.writeln('Student registration error: $error');
    return Response.json(
      statusCode: 500,
      body: {'error': 'An unexpected error occurred during registration.'},
    );
  } catch (error) {
    stderr.writeln('Student registration error: $error');
    return Response.json(
      statusCode: 500,
      body: {'error': 'An unexpected error occurred during registration.'},
    );
  }
}

Future<Response> createStudentRecords(
  MySQLConnection connection, {
  required String firebaseUid,
  required String fullName,
  required String email,
  required String phone,
  required String address,
  required String course,
  required String tutoringModule,
  required String institutionYear,
  required String? profilePhotoUrl,
  required String proofOfRegistrationUrl,
}) async {
  final existingUser = await connection.execute(
    'SELECT UserId FROM User WHERE Email = :email OR FirebaseUid = :uid',
    {'email': email, 'uid': firebaseUid},
  );
  if (existingUser.rows.isNotEmpty) {
    return Response.json(
      statusCode: 409,
      body: {
        'error': 'An account with this email or Firebase UID already exists.',
      },
    );
  }

  await connection.execute('START TRANSACTION');
  try {
    final userResult = await connection.execute(
      '''
      INSERT INTO User (
        Name, Email, FirebaseUid, PhoneNum, ProfilePhoto, Role, AccountStatus
      )
      VALUES (
        :name, :email, :firebaseUid, :phone, :profilePhoto, 'student', 'Active'
      )
      ''',
      {
        'name': fullName,
        'email': email,
        'firebaseUid': firebaseUid,
        'phone': phone,
        'profilePhoto': profilePhotoUrl,
      },
    );

    final studentResult = await connection.execute(
      '''
      INSERT INTO StudentProfile (
        Address, ProofOfReg, InstitutionYear, Course, Subject_of_interest, UserID
      )
      VALUES (
        :address, :proofOfRegistration, :institutionYear, :course, :tutoringModule, :userId
      )
      ''',
      {
        'address': address,
        'proofOfRegistration': proofOfRegistrationUrl,
        'institutionYear': institutionYear,
        'course': course,
        'tutoringModule': tutoringModule,
        'userId': userResult.lastInsertID,
      },
    );
    await connection.execute('COMMIT');

    return Response.json(
      statusCode: 201,
      body: {
        'message': 'Student registered successfully.',
        'userId': userResult.lastInsertID,
        'studentId': studentResult.lastInsertID,
      },
    );
  } catch (_) {
    await connection.execute('ROLLBACK');
    rethrow;
  }
}

Map<String, String> validateStudentRegistration(
  Map<String, dynamic> data,
) {
  final errors = <String, String>{};

  for (final field in _requiredFields) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      errors[field] = 'This field is required.';
    }
  }

  final name = data['fullName'];
  if (name is String && name.trim().length > 100) {
    errors['fullName'] = 'Name must be 100 characters or fewer.';
  }

  final email = data['email'];
  if (email is String &&
      email.trim().isNotEmpty &&
      (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim()) ||
          email.trim().length > 150)) {
    errors['email'] = 'Enter a valid email address of 150 characters or fewer.';
  }

  final phone = data['phone'];
  if (phone is String && phone.trim().length > 20) {
    errors['phone'] = 'Phone number must be 20 characters or fewer.';
  }

  final address = data['address'];
  if (address is String && address.trim().length > 255) {
    errors['address'] = 'Address must be 255 characters or fewer.';
  }

  final course = data['course'];
  if (course is String && course.trim().length > 100) {
    errors['course'] = 'Course must be 100 characters or fewer.';
  }

  final year = data['institutionYear'];
  if (year is String && year.trim().length > 20) {
    errors['institutionYear'] =
        'Institution year must be 20 characters or fewer.';
  }

  final tutoringModule = data['tutoringModule'];
  if (tutoringModule is String && tutoringModule.trim().length > 255) {
    errors['tutoringModule'] =
        'Tutoring module must be 255 characters or fewer.';
  }

  final proofOfRegistrationUrl = data['proofOfRegistrationUrl'];
  if (proofOfRegistrationUrl is! String ||
      proofOfRegistrationUrl.trim().isEmpty) {
    errors['proofOfRegistrationUrl'] = 'This field is required.';
  } else if (!_isHttpUrl(proofOfRegistrationUrl)) {
    errors['proofOfRegistrationUrl'] = 'Enter a valid HTTP or HTTPS URL.';
  }

  final profilePhotoUrl = data['profilePhotoUrl'];
  if (!_isOptionalHttpUrl(profilePhotoUrl)) {
    errors['profilePhotoUrl'] = 'Enter a valid HTTP or HTTPS URL.';
  }

  if (data['termsAccepted'] != true) {
    errors['termsAccepted'] =
        'Terms of Service and Privacy Policy must be accepted.';
  }

  return errors;
}

String? _optionalUrl(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

bool _isOptionalHttpUrl(dynamic value) =>
    value == null ||
    value is String && (value.trim().isEmpty || _isHttpUrl(value));

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      value.trim().length <= 500;
}
