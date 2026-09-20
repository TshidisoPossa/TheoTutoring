import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';

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
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Only POST requests are supported.'},
    );
  }

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

  final errors = validateStudentRegistration(decodedBody);
  if (errors.isNotEmpty) {
    return Response.json(statusCode: 422, body: {'errors': errors});
  }

  return Response.json(
    statusCode: 201,
    body: {
      'message': 'Student registration received.',
      'student': {
        for (final field in _requiredFields)
          if (field != 'password' && field != 'confirmPassword')
            field: (decodedBody[field] as String).trim(),
      },
    },
  );
}

Map<String, String> validateStudentRegistration(Map<String, dynamic> data) {
  final errors = <String, String>{};

  for (final field in _requiredFields) {
    if (data[field] is! String || (data[field] as String).trim().isEmpty) {
      errors[field] = 'This field is required.';
    }
  }

  final email = data['email'];
  if (email is String && email.trim().isNotEmpty &&
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
    errors['email'] = 'Enter a valid email address.';
  }

  final password = data['password'];
  if (password is String && password.length < 8) {
    errors['password'] = 'Password must be at least 8 characters.';
  }

  if (password is String &&
      data['confirmPassword'] is String &&
      password != data['confirmPassword']) {
    errors['confirmPassword'] = 'Passwords do not match.';
  }

  if (data['termsAccepted'] != true) {
    errors['termsAccepted'] = 'Terms of Service and Privacy Policy must be accepted.';
  }

  return errors;
}