import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/admin_report_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

class AdminReportsService {
  AdminReportsService({
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

  Exception _failure(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) {
        return Exception(body['error'].toString());
      }
    } catch (_) {}
    return Exception('Request failed (${response.statusCode})');
  }

  /// [status] is one of the backend's status filters; [category] is null
  /// for every category.
  Future<AdminReportsPage> fetchReports({
    String status = 'all',
    String? category,
    int page = 1,
    int pageSize = 20,
  }) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw Exception('Sign in is required to view reports.');
    }
    final uri = Uri.parse('$apiBaseUrl/admin/reports').replace(
      queryParameters: {
        'status': status,
        if (category != null && category.isNotEmpty) 'category': category,
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _failure(response);
    return AdminReportsPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
