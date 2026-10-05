// This page has no screen or widgets, only the code that fetches data from your Dart Frog backend
// It fetches the summary and calls Get and returns dashboard summarywith the stat cards, the pending counts and Recent Activity
//It calls the backend as Get()

import 'dart:convert';

import '../models/dashboard_models.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminDashboardService {
  // Use your existing backend base URL.
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

  Future<DashboardSummary> fetchSummary() async =>
      DashboardSummary.fromJson(await _get('/admin/dashboard'));

  Future<List<ChartPoint>> fetchChart(String range) async {
    final json = await _get('/admin/dashboard/chart?range=$range');
    return (json['points'] as List<dynamic>)
        .map((e) => ChartPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
