import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/admin_tutor_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

/// Raised when the roster endpoint itself is missing (GET returns 404).
class AdminTutorsUnavailable implements Exception {
  const AdminTutorsUnavailable();

  @override
  String toString() => 'Tutor management is not available on this server yet.';
}

class AdminTutorsService {
  AdminTutorsService({
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
      throw Exception('Sign in is required to manage tutors.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Only the genuinely missing roster endpoint means "unavailable"; a 404
  /// from an update (e.g. unknown tutor) carries the backend's own message.
  Exception _failure(
    http.Response response, {
    bool missingMeansUnavailable = false,
  }) {
    if (missingMeansUnavailable && response.statusCode == 404) {
      return const AdminTutorsUnavailable();
    }
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) {
        return Exception(body['error'].toString());
      }
    } catch (_) {}
    return Exception('Request failed (${response.statusCode})');
  }

  /// [status] is all | active | suspended | pending.
  Future<AdminTutorsPage> fetchTutors({
    String status = 'all',
    String search = '',
    int page = 1,
    int pageSize = 10,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/admin/tutors').replace(
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
    if (response.statusCode != 200) {
      throw _failure(response, missingMeansUnavailable: true);
    }
    return AdminTutorsPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// [reason] is required when suspending; it is shown to the tutor.
  Future<AdminTutor> updateStatus(
    int tutorId,
    TutorStatusChange status, {
    String? reason,
  }) async {
    final response = await _client
        .patch(
          Uri.parse('$apiBaseUrl/admin/tutors/$tutorId/status'),
          headers: await _headers(),
          body: jsonEncode({
            'status': status.apiValue,
            if (status == TutorStatusChange.suspended) 'reason': reason,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw _failure(response);
    return AdminTutor.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
