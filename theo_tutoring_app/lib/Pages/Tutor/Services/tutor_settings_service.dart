import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'tutor_settings_models.dart';

class TutorSettingsService {
  static const String _baseUrl = 'http://localhost:8080';

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

  Future<TutorSettings> fetchSettings() async =>
      TutorSettings.fromJson(await _get('/tutor/settings'));

  Future<void> updateSettings(TutorSettings settings) async =>
      _put('/tutor/settings', settings.toJson());

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      _post('/tutor/settings/change-password', {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
}