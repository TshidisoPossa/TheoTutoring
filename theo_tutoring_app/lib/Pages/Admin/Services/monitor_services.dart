import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/monitor_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

class AdminMonitorService {
  AdminMonitorService({
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
      throw Exception('Sign in is required to access platform monitoring.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
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

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw _failure(response);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// The admin's name and the current platform counts.
  Future<MonitorSnapshot> fetchSnapshot() async => MonitorSnapshot.fromJson(
    await _get(Uri.parse('$apiBaseUrl/admin/monitor')),
  );

  /// Pass the previous page's `nextCursor` as [before] to load older entries.
  Future<AuditLogPage> fetchAuditLog({String? before, int limit = 20}) async =>
      AuditLogPage.fromJson(
        await _get(
          Uri.parse('$apiBaseUrl/admin/monitor/audit-log')
              .replace(queryParameters: {'limit': '$limit', 'before': ?before}),
        ),
      );
}
