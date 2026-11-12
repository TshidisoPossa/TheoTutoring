import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/admin_subject_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

class AdminSubjectsService {
  AdminSubjectsService({
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

  Uri get _catalogueUri => Uri.parse('$apiBaseUrl/subjects');

  Uri get _adminUri => Uri.parse('$apiBaseUrl/admin/subjects');

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();

    if (token == null || token.isEmpty) {
      throw Exception('Sign in is required to manage subjects.');
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

    return Exception('Request failed (${response.statusCode}).');
  }

  Future<AdminSubjectsResult> fetchSubjects() async {
    final response = await _client
        .get(_catalogueUri)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) throw _failure(response);

    return AdminSubjectsResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminSubject> createSubject(String name) async {
    final response = await _client
        .post(
          _adminUri,
          headers: await _headers(),
          body: jsonEncode({'subjectName': name}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) throw _failure(response);

    return AdminSubject.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminSubject> renameSubject(int id, String name) async {
    final response = await _client
        .patch(
          _adminUri.replace(path: '${_adminUri.path}/$id'),
          headers: await _headers(),
          body: jsonEncode({'subjectName': name}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) throw _failure(response);

    return AdminSubject.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteSubject(int id) async {
    final response = await _client
        .delete(
          _adminUri.replace(path: '${_adminUri.path}/$id'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) throw _failure(response);
  }
}
