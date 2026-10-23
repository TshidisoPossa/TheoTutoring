import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';
import 'student_lessons_api.dart';

/// Reports a tutor to the administrator from their profile (⋮ menu);
/// POST /students/tutors/{id}/report. Lesson reports go through
/// StudentLessonsApi.report.
class StudentReportsApi {
  StudentReportsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<void> reportTutor(int tutorId, String reason) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const StudentLessonsException('Please sign in again.');
    }
    final response = await _client
        .post(
          Uri.parse('$apiBaseUrl/students/tutors/$tutorId/report'),
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
}
