import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../models/admin_review_models.dart';

Future<String?> _currentFirebaseToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return user.getIdToken();
}

/// The Admin review endpoints are not on this backend yet (404 on the list).
class AdminReviewsUnavailable implements Exception {
  const AdminReviewsUnavailable();

  @override
  String toString() => 'Reviews are not available on this server yet.';
}

/// Filters for the Reviews page.
class AdminReviewFilters {
  const AdminReviewFilters({
    this.search = '',
    this.rating,
    this.range = 'all',
    this.withComment = false,
    this.sort = 'newest',
  });

  final String search;

  /// 1-5, or null for every rating.
  final int? rating;

  /// all | 7d | 30d | 90d
  final String range;
  final bool withComment;

  /// newest | oldest | lowest | highest
  final String sort;

  AdminReviewFilters copyWith({
    String? search,
    int? Function()? rating,
    String? range,
    bool? withComment,
    String? sort,
  }) => AdminReviewFilters(
    search: search ?? this.search,
    rating: rating == null ? this.rating : rating(),
    range: range ?? this.range,
    withComment: withComment ?? this.withComment,
    sort: sort ?? this.sort,
  );

  bool get isDefault =>
      search.trim().isEmpty && rating == null && range == 'all' && !withComment;
}

class AdminReviewsService {
  AdminReviewsService({
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
      throw Exception('Sign in is required to view reviews.');
    }
    return {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
  }

  Exception _failure(http.Response response, {bool listCall = false}) {
    if (listCall && response.statusCode == 404) {
      return const AdminReviewsUnavailable();
    }
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) {
        return Exception(body['error'].toString());
      }
    } catch (_) {}
    return Exception('Request failed (${response.statusCode})');
  }

  Future<AdminReviewsPage> fetchReviews({
    AdminReviewFilters filters = const AdminReviewFilters(),
    int page = 1,
    int pageSize = 10,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/admin/reviews').replace(
      queryParameters: {
        if (filters.search.trim().isNotEmpty) 'search': filters.search.trim(),
        if (filters.rating != null) 'rating': '${filters.rating}',
        'range': filters.range,
        if (filters.withComment) 'withComment': 'true',
        'sort': filters.sort,
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw _failure(response, listCall: true);
    }
    return AdminReviewsPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminReview> fetchReview(int reviewId) async {
    final response = await _client
        .get(
          Uri.parse('$apiBaseUrl/admin/reviews/$reviewId'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw _failure(response);
    return AdminReview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
