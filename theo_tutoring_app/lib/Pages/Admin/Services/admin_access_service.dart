import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';

enum AdminAccessStatus { allowed, denied, unavailable }

class AdminAccessResult {
  const AdminAccessResult._(
    this.status, {
    this.adminName,
    this.adminId,
    this.roleKey,
    this.permissions = const [],
  });

  const AdminAccessResult.allowed(
    String adminName, {
    int? adminId,
    String? roleKey,
    List<String> permissions = const [],
  }) : this._(
         AdminAccessStatus.allowed,
         adminName: adminName,
         adminId: adminId,
         roleKey: roleKey,
         permissions: permissions,
       );

  const AdminAccessResult.denied() : this._(AdminAccessStatus.denied);

  const AdminAccessResult.unavailable() : this._(AdminAccessStatus.unavailable);

  final AdminAccessStatus status;
  final String? adminName;
  final int? adminId;
  final String? roleKey;
  final List<String> permissions;

  bool get isAllowed => status == AdminAccessStatus.allowed;
}

class AdminAccessService {
  AdminAccessService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<AdminAccessResult> checkCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _closeOwnedClient();
      return const AdminAccessResult.denied();
    }

    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        _closeOwnedClient();
        return const AdminAccessResult.denied();
      }
      final result = await checkToken(token);
      return result;
    } on Exception {
      _closeOwnedClient();
      return const AdminAccessResult.unavailable();
    }
  }

  Future<AdminAccessResult> checkToken(String token) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$apiBaseUrl/admin/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const AdminAccessResult.denied();
      }
      if (response.statusCode != 200) {
        return const AdminAccessResult.unavailable();
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body['adminId'] is! int ||
          body['adminName'] is! String ||
          (body['adminName'] as String).trim().isEmpty ||
          body['adminRole'] is! String ||
          body['permissions'] is! List ||
          (body['permissions'] as List).any((value) => value is! String)) {
        return const AdminAccessResult.unavailable();
      }
      return AdminAccessResult.allowed(
        (body['adminName'] as String).trim(),
        adminId: body['adminId'] as int,
        roleKey: (body['adminRole'] as String).trim(),
        permissions: (body['permissions'] as List).cast<String>(),
      );
    } on Exception {
      return const AdminAccessResult.unavailable();
    } finally {
      _closeOwnedClient();
    }
  }

  void _closeOwnedClient() {
    if (_ownsClient) _client.close();
  }
}
