import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/monitor_models.dart';

class AdminMonitorService {
  // Use the same base URL as the other admin services.
  static const String _baseUrl = 'http://localhost:8080';

  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// [range] is `live` (recent minutes) or `24h`.
  Future<MonitorSnapshot> fetchSnapshot(String range) async =>
      MonitorSnapshot.fromJson(
        await _get(
          Uri.parse(
            '$_baseUrl/admin/monitor',
          ).replace(queryParameters: {'range': range}),
        ),
      );

  /// Pass the previous page's `nextCursor` as [before] to load older entries.
  Future<AuditLogPage> fetchAuditLog({String? before, int limit = 20}) async =>
      AuditLogPage.fromJson(
        await _get(
          Uri.parse('$_baseUrl/admin/monitor/audit-log').replace(
            queryParameters: {
              'limit': '$limit',
              'before': ?before,
            },
          ),
        ),
      );
}
