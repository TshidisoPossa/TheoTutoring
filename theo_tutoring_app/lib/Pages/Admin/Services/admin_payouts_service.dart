import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/admin_payout_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

/// GET /admin/payouts and the approve / mark-paid actions.
class AdminPayoutsService {
  AdminPayoutsService({
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
      throw Exception('Sign in is required to manage payouts.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Prefer the backend's own message (for example a 409 explaining why a
  // payout cannot change status) over a bare status code.
  Exception _failure(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) {
        return Exception(body['error'].toString());
      }
    } catch (_) {}
    return Exception('Request failed (${response.statusCode})');
  }

  /// [status] null lists every payout.
  Future<AdminPayoutsPage> fetchPayouts({
    PayoutStatus? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/admin/payouts').replace(
      queryParameters: {
        'status': status?.apiValue ?? 'all',
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _failure(response);
    return AdminPayoutsPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    final response = await _client
        .post(
          Uri.parse('$apiBaseUrl/admin/payouts/$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw _failure(response);
    return response;
  }

  /// Pending -> Approved.
  Future<void> approve(int payoutId) => _post('$payoutId/approve', const {});

  /// Approved -> Paid, with an optional external payment [reference] (up to
  /// 100 characters). Records the payment only; it transfers no money.
  Future<void> markPaid(int payoutId, {String? reference}) {
    final trimmed = reference?.trim() ?? '';
    return _post('$payoutId/mark-paid', {
      if (trimmed.isNotEmpty) 'reference': trimmed,
    });
  }

  /// Creates Pending payouts for every eligible finished lesson that has
  /// none yet. Safe to repeat. Returns the backend's message and count.
  Future<({int generated, String message})> generate() async {
    final response = await _post('generate', const {});
    final body = jsonDecode(response.body);
    final generated = body is Map && body['generated'] is num
        ? (body['generated'] as num).toInt()
        : 0;
    final message = body is Map && body['message'] is String
        ? body['message'] as String
        : '$generated payouts generated.';
    return (generated: generated, message: message);
  }
}
