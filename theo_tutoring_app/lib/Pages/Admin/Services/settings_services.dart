import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/session_rate_models.dart';

class AdminSettingsService {
  // Use the same base URL as the other admin services.
  static const String _baseUrl = 'http://localhost:8080';
  final _dateFormat = DateFormat('yyyy-MM-dd');

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

  Future<SessionRateResult> fetchSessionRate() async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl/admin/session-rate'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _failure(response);
    return SessionRateResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SessionRate> setSessionRate(
    double amount,
    DateTime effectiveFrom,
  ) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/admin/session-rate'),
          headers: await _headers(),
          body: jsonEncode({
            'amount': amount,
            'effectiveFrom': _dateFormat.format(effectiveFrom),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _failure(response);
    }
    return SessionRate.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // Password changes go through Firebase Authentication; the backend never
  // sees passwords (documentation 4.1 and 12.1).
  Future<void> sendPasswordReset(String email) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email);

  Future<void> signOut() => FirebaseAuth.instance.signOut();
}
