import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/refund_models.dart';

class AdminRefundsService {
  // Use the same base URL as the other admin services.
  static const String _baseUrl = 'http://localhost:8080';

  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Prefer the backend's own error message (validation errors come back as
  // 400 with { "error": "..." }) over a bare status code.
  Exception _failure(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && (body['error'] ?? body['message']) != null) {
        return Exception((body['error'] ?? body['message']).toString());
      }
    } catch (_) {}
    return Exception('Request failed (${response.statusCode})');
  }

  Future<RefundCasesResult> fetchCases({
    CaseType? type,
    String status = 'all',
  }) async {
    final uri = Uri.parse('$_baseUrl/admin/refunds').replace(
      queryParameters: {'type': type?.apiValue ?? 'all', 'status': status},
    );
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _failure(response);
    return RefundCasesResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> _post(String path, [Map<String, dynamic>? body]) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(body ?? const {}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw _failure(response);
  }

  Future<void> approve(String caseId) =>
      _post('/admin/refunds/${Uri.encodeComponent(caseId)}/approve');

  Future<void> deny(String caseId, String reason) => _post(
    '/admin/refunds/${Uri.encodeComponent(caseId)}/deny',
    {'reason': reason},
  );

  Future<void> override(String caseId, double percentage, String reason) =>
      _post('/admin/refunds/${Uri.encodeComponent(caseId)}/override', {
        'refundPercentage': percentage,
        'reason': reason,
      });

  Future<void> resolve(String caseId, String note) => _post(
    '/admin/refunds/${Uri.encodeComponent(caseId)}/resolve',
    {'note': note},
  );
}
