import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';

import '../../lib/database.dart';

const _requiredFields = <String>[
  'fullName',
  'email',
  'password',
  'confirmPassword',
  'phone',
  'address',
  'institutionYear',
  'course',
  'tutoringModule',
];

Future<Response> onRequest(RequestContext context) async {
  // Only allow POST requests
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Only POST requests are supported.'},
    );
  }

  // Read JSON body
  late final dynamic decodedBody;

  try {
    decodedBody = jsonDecode(await context.request.body());
  } on FormatException {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Request body must be valid JSON.'},
    );
  }

  if (decodedBody is! Map<String, dynamic>) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Request body must be a JSON object.'},
    );
  }

  // Validate the submitted information
  final errors = validateStudentRegistration(decodedBody);

  if (errors.isNotEmpty) {
    return Response.json(
      statusCode: 422,
      body: {'errors': errors},
    );
  }

  // Clean the submitted values
  final fullName = (decodedBody['fullName'] as String).trim();
  final email = (decodedBody['email'] as String).trim().toLowerCase();
  final password = decodedBody['password'] as String;
  final phone = (decodedBody['phone'] as String).trim();
  final address = (decodedBody['address'] as String).trim();
  final course = (decodedBody['course'] as String).trim();
  final tutoringModule =
      (decodedBody['tutoringModule'] as String).trim();

  final institutionYear = int.tryParse(
    (decodedBody['institutionYear'] as String).trim(),
  );

  if (institutionYear == null ||
      institutionYear < 1 ||
      institutionYear > 4) {
    return Response.json(
      statusCode: 422,
      body: {
        'errors': {
          'institutionYear': 'Year must be between 1 and 4.',
        },
      },
    );
  }

  try {
    // Connect to MySQL
    final connection = await getConnection();

    // Check whether the email already exists
    final existingUser = await connection.execute(
      'SELECT UserId FROM User WHERE Email = :email',
      {
        'email': email,
      },
    );

    if (existingUser.rows.isNotEmpty) {
      return Response.json(
        statusCode: 409,
        body: {
          'error': 'An account with this email already exists.',
        },
      );
    }

    // Hash the password before storing it
    final hashedPassword = BCrypt.hashpw(
      password,
      BCrypt.gensalt(),
    );

    // Create the user account
    final userResult = await connection.execute(
      '''
      INSERT INTO User (
        Name,
        Email,
        Password,
        PhoneNum,
        Role,
        AccountStatus
      )
      VALUES (
        :name,
        :email,
        :password,
        :phone,
        'student',
        'Active'
      )
      ''',
      {
        'name': fullName,
        'email': email,
        'password': hashedPassword,
        'phone': phone,
      },
    );

    final userId = userResult.lastInsertID;

    // Create the student's profile
    final studentResult = await connection.execute(
      '''
      INSERT INTO StudentProfile (
        Address,
        InstitutionYear,
        Course,
        Subject_of_interest,
        UserID
      )
      VALUES (
        :address,
        :institutionYear,
        :course,
        :tutoringModule,
        :userId
      )
      ''',
      {
        'address': address,
        'institutionYear': institutionYear,
        'course': course,
        'tutoringModule': tutoringModule,
        'userId': userId,
      },
    );

    final studentId = studentResult.lastInsertID;

    // Registration successful
    return Response.json(
      statusCode: 201,
      body: {
        'message': 'Student registered successfully.',
        'userId': userId,
        'studentId': studentId,
        'student': {
          'fullName': fullName,
          'email': email,
          'phone': phone,
          'address': address,
          'institutionYear': institutionYear,
          'course': course,
          'tutoringModule': tutoringModule,
        },
      },
    );
  } catch (e) {
    print('Student registration error: $e');

    return Response.json(
      statusCode: 500,
      body: {
        'error': 'An unexpected error occurred during registration.',
      },
    );
  }
}

Map<String, String> validateStudentRegistration(
  Map<String, dynamic> data,
) {
  final errors = <String, String>{};

  // Required fields
  for (final field in _requiredFields) {
    if (data[field] is! String ||
        (data[field] as String).trim().isEmpty) {
      errors[field] = 'This field is required.';
    }
  }

  // Email validation
  final email = data['email'];

  if (email is String &&
      email.trim().isNotEmpty &&
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
          .hasMatch(email.trim())) {
    errors['email'] = 'Enter a valid email address.';
  }

  // Password validation
  final password = data['password'];

  if (password is String && password.length < 8) {
    errors['password'] = 'Password must be at least 8 characters.';
  }

  // Confirm password
  if (password is String &&
      data['confirmPassword'] is String &&
      password != data['confirmPassword']) {
    errors['confirmPassword'] = 'Passwords do not match.';
  }

  // Terms and conditions
  if (data['termsAccepted'] != true) {
    errors['termsAccepted'] =
        'Terms of Service and Privacy Policy must be accepted.';
  }

  return errors;
}
