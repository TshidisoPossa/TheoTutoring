// Service layer for the Student Settings page.
// Matches the HTTP + Firebase Auth pattern used across the project
// (see admin_dashboard_services.dart, financial_services.dart).
// Wire the frontend by injecting this service into StudentSettings widget.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'student_settings_models.dart';

class StudentSettingsService {
  static const String _baseUrl = 'http://localhost:8080';

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await http
        .get(Uri.parse('$_baseUrl$path'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _put(String path, Map<String, dynamic> body) async {
    final response = await http
        .put(
          Uri.parse('$_baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Request failed (${response.statusCode})');
    }
  }

  // ── account settings ─────────────────────────────────────────────────────

  /// Loads the student's current settings (email, phone, notification prefs).
  Future<StudentSettings> fetchSettings() async =>
      StudentSettings.fromJson(await _get('/student/settings'));

  /// Saves updated email, phone and notification preferences.
  Future<void> updateSettings(StudentSettings settings) async =>
      _put('/student/settings', settings.toJson());

  /// Triggers a password-reset email via the backend.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      _post('/student/settings/change-password', {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });

  // ── payment methods ───────────────────────────────────────────────────────

  /// Returns the student's saved payment methods.
  Future<List<PaymentMethod>> fetchPaymentMethods() async {
    final json = await _get('/student/payment-methods');
    return (json['paymentMethods'] as List<dynamic>)
        .map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Adds a new payment method token (tokenised by payment provider on device).
  Future<void> addPaymentMethod(String paymentToken) async =>
      _post('/student/payment-methods', {'token': paymentToken});
}
