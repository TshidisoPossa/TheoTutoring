import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/Tutapplication.dart';

class AdminApplicationsService {
  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<ApplicationsResult> fetchApplications() async {
    final response = await http
        .get(
          Uri.parse('$apiBaseUrl/admin/applications'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }
    return ApplicationsResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> reviewApplication({
    required String applicationId,
    required String decision,
    String? feedback,
  }) async {
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/admin/applications/review'),
          headers: await _headers(),
          body: jsonEncode({
            'applicationId': applicationId,
            'decision': decision,
            'feedback': feedback,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      String message = 'Request failed (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] != null) {
          message = body['error'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }
  }
}
