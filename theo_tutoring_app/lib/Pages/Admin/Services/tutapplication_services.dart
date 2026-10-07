import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/Tutapplication.dart';

class AdminApplicationsService {
  // Use the same base URL as admin_dashboard_services.dart.
  static const String _baseUrl = 'http://localhost:8080';

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
          Uri.parse('$_baseUrl/admin/applications'),
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
}
