import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/admin_appeal_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

class AdminAppealsService {
  AdminAppealsService({
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
      throw Exception('Sign in is required to review appeals.');
    }
    return {
      'Accept': 'application/json',
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

  /// [status] is pending, approved, rejected, closed or all.
  Future<AdminAppealsPage> fetchAppeals({String status = 'pending'}) async {
    final response = await _client
        .get(
          Uri.parse(
            '$apiBaseUrl/admin/appeals',
          ).replace(queryParameters: {'status': status}),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _failure(response);
    return AdminAppealsPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminAppealDecisionResult> decide(
    int appealId, {
    required bool approve,
    String? note,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$apiBaseUrl/admin/appeals/$appealId/decision'),
          headers: await _headers(),
          body: jsonEncode({
            'decision': approve ? 'approve' : 'reject',
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw _failure(response);
    return AdminAppealDecisionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
