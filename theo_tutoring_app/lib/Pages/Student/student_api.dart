import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';

/// Thrown when a student page could not load its data from the backend.
class StudentApiException implements Exception {
  const StudentApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode; // HTTP status, null if the server was not reached

  @override
  String toString() => message;
}

/// The signed-in student (GET /StudentlandingPage/myprofile):
/// userId, studentId, name, email, role and accountStatus.
Future<Map<String, dynamic>> fetchStudentProfile() async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null || token.isEmpty) {
    throw const StudentApiException(
      'You are signed out. Please log in again.',
      statusCode: 401,
    );
  }

  final http.Response response;
  try {
    response = await http
        .get(
          Uri.parse('$apiBaseUrl/StudentlandingPage/myprofile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));
  } on Exception {
    throw const StudentApiException(
      'Could not connect to the server. Please try again.',
    );
  }

  if (response.statusCode != 200) {
    throw StudentApiException(switch (response.statusCode) {
      401 => 'Your session could not be verified. Please sign in again.',
      404 => 'No student profile was found for this account.',
      _ => 'Could not load your profile. Please try again.',
    }, statusCode: response.statusCode);
  }

  try {
    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic>) return body;
  } on FormatException {
    // falls through to the error below
  }
  throw const StudentApiException(
    'The server returned an invalid response. Please try again.',
  );
}
