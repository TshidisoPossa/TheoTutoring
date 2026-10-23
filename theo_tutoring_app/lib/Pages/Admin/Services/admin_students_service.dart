import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/admin_student_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

/// The Admin student endpoints are not on this backend yet (404).
class AdminStudentsUnavailable implements Exception {
  const AdminStudentsUnavailable();

  @override
  String toString() =>
      'Student management is not available on this server yet.';
}

class AdminStudentsService {
  AdminStudentsService({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _tokenProvider = tokenProvider ?? _currentFirebaseToken;

  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function() _tokenProvider;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw Exception('Sign in is required to manage students.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Exception _failure(http.Response response) {
    if (response.statusCode == 404) return const AdminStudentsUnavailable();
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) {
        return Exception(body['error'].toString());
      }
    } catch (_) {}
    return Exception('Request failed (${response.statusCode})');
  }

  /// [status] is all | active | suspended | pending.
  Future<AdminStudentsPage> fetchStudents({
    String status = 'all',
    String search = '',
    int page = 1,
    int pageSize = 10,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/admin/students').replace(
      queryParameters: {
        'status': status,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _failure(response);
    return AdminStudentsPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminStudent> updateStatus(
    int studentId,
    StudentStatusChange status,
  ) async {
    final response = await _client
        .patch(
          Uri.parse('$apiBaseUrl/admin/students/$studentId/status'),
          headers: await _headers(),
          body: jsonEncode({'status': status.apiValue}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw _failure(response);
    return AdminStudent.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
