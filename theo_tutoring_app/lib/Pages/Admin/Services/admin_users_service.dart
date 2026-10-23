import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/admin_user_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

class AdminUsersService {
  AdminUsersService({
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
      throw Exception('Sign in is required to manage administrators.');
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

  Uri get _uri => Uri.parse('$apiBaseUrl/admin/users');

  Future<AdminUsersResult> fetchAdmins() async {
    final response = await _client
        .get(_uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _failure(response);
    return AdminUsersResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// The password is sent once over the request to the backend, which passes
  /// it to Firebase Authentication; it is not kept anywhere in the app.
  Future<AdminAccount> createAdmin({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final response = await _client
        .post(
          _uri,
          headers: await _headers(),
          body: jsonEncode({
            'name': name,
            'email': email,
            'password': password,
            'role': role,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 201) throw _failure(response);
    return AdminAccount.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
