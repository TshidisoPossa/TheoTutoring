import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/financial_models.dart';

class AdminFinancialService {
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

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await http
        .get(Uri.parse('$_baseUrl$path'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<FinancialOverview> fetchOverview(
    DateTime from,
    DateTime to,
  ) async => FinancialOverview.fromJson(
    await _get(
      '/admin/financials?from=${_dateFormat.format(from)}&to=${_dateFormat.format(to)}',
    ),
  );

  Future<List<SubjectRevenue>> fetchRevenueBySubject(String period) async {
    final json = await _get(
      '/admin/financials/revenue-by-subject?period=$period',
    );
    return (json['subjects'] as List<dynamic>)
        .map((e) => SubjectRevenue.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> processBatch() async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/admin/payouts/process-batch'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }
  }
}
