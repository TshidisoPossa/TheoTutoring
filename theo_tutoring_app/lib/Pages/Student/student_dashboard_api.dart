import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';

class StudentDashboardApi {
  StudentDashboardApi({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<Map<String, dynamic>> fetch() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const StudentDashboardException('Please sign in again.');
    }

    final response = await _client
        .get(
          Uri.parse('$apiBaseUrl/students/dashboard'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error'] as String? ?? 'Dashboard could not be loaded.'
          : 'Dashboard could not be loaded.';
      throw StudentDashboardException(message);
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['upcomingSessions'] is! List ||
        decoded['tutors'] is! List) {
      throw const FormatException('Student dashboard response is invalid.');
    }
    return decoded;
  }
}

class StudentDashboardException implements Exception {
  const StudentDashboardException(this.message);

  final String message;

  @override
  String toString() => message;
}
