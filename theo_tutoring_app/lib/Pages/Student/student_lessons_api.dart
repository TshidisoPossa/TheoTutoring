import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';

class StudentLessonsApi {
  StudentLessonsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const StudentLessonsException('Please sign in again.');
    }
    return token;
  }

  /// Cancels a lesson. The response has the refund the student will get
  /// (refundPercentage/refundAmount, null when the lesson was not paid).
  Future<Map<String, dynamic>> cancel(int bookingId, String reason) async {
    final token = await _token();
    final response = await _client
        .post(
          Uri.parse('$apiBaseUrl/students/lessons/$bookingId/cancel'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'reason': reason}),
        )
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error'] as String? ?? 'Lesson could not be cancelled.'
          : 'Lesson could not be cancelled.';
      throw StudentLessonsException(message);
    }
    return decoded;
  }

  /// Reports the lesson's tutor to the administrator.
  Future<void> report(int bookingId, String reason) async {
    final token = await _token();
    final response = await _client
        .post(
          Uri.parse('$apiBaseUrl/students/lessons/$bookingId/report'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'reason': reason}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 201) {
      final decoded = jsonDecode(response.body);
      throw StudentLessonsException(
        decoded is Map<String, dynamic>
            ? decoded['error'] as String? ?? 'Report could not be sent.'
            : 'Report could not be sent.',
      );
    }
  }

  Future<Map<String, dynamic>> fetch() async {
    final token = await _token();

    final response = await _client
        .get(
          Uri.parse('$apiBaseUrl/students/lessons'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error'] as String? ?? 'Lessons could not be loaded.'
          : 'Lessons could not be loaded.';
      throw StudentLessonsException(message);
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['upcoming'] is! List ||
        decoded['cancelled'] is! List) {
      throw const FormatException('Student lessons response is invalid.');
    }
    return decoded;
  }
}

class StudentLessonsException implements Exception {
  const StudentLessonsException(this.message);

  final String message;

  @override
  String toString() => message;
}
