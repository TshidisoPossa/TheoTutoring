import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';

/// Thrown when a tutor page could not be loaded from the backend.
class TutorApiException implements Exception {
  const TutorApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode; // HTTP status, null if the server was not reached

  @override
  String toString() => message;
}

/// Loads the tutor dashboard (GET /TutorLandingpage/LandingPageScreen).
/// Active tutors get stats, requests, today's schedule and reviews.
/// Pending tutors get `accountStatus: 'Pending'` and their `application`.
/// Pass [idToken] when it is already known (e.g. right after login).
Future<Map<String, dynamic>> fetchTutorDashboard({String? idToken}) async {
  final token =
      idToken ?? await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null || token.isEmpty) {
    throw const TutorApiException(
      'You are signed out. Please log in again.',
      statusCode: 401,
    );
  }

  final http.Response response;
  try {
    response = await http
        .get(
          Uri.parse('$apiBaseUrl/TutorLandingpage/LandingPageScreen'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));
  } on Exception {
    throw const TutorApiException(
      'Could not connect to the server. Please try again.',
    );
  }

  if (response.statusCode != 200) {
    throw TutorApiException(switch (response.statusCode) {
      401 => 'Your session could not be verified. Please sign in again.',
      403 => 'This account does not have an active tutor profile.',
      404 => 'No tutor profile was found for this account.',
      _ => 'Could not load your dashboard. Please try again.',
    }, statusCode: response.statusCode);
  }

  try {
    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic>) return body;
  } on FormatException {
    // falls through to the error below
  }
  throw const TutorApiException(
    'The server returned an invalid response. Please try again.',
  );
}
