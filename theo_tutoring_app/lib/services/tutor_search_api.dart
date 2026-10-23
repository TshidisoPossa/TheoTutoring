import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api.dart';
import '../models/tutor.dart';
import '../models/tutor_profile_details.dart';

class TutorSearchApi {
  TutorSearchApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<TutorSearchPage> search({
    String query = '',
    int? subjectId,
    int page = 1,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/tutors').replace(
      queryParameters: {
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (subjectId != null) 'subjectId': '$subjectId',
        'page': '$page',
        'limit': '$limit',
      },
    );
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw TutorSearchException(
        response.statusCode == 400
            ? 'Search parameters are invalid.'
            : 'Tutors are temporarily unavailable. Please try again.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Tutor search response is invalid.');
    }
    return TutorSearchPage.fromJson(decoded);
  }

  /// The Tutor Profile page (GET /tutors/{id}).
  Future<TutorProfileDetails> profile(int tutorId) async {
    final response = await _client
        .get(
          Uri.parse('$apiBaseUrl/tutors/$tutorId'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw TutorSearchException(
        response.statusCode == 404
            ? 'This tutor is no longer available.'
            : 'This profile is temporarily unavailable. Please try again.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Tutor profile response is invalid.');
    }
    return TutorProfileDetails.fromJson(decoded);
  }

  Future<List<TutorSubject>> subjects() async {
    final response = await _client
        .get(
          Uri.parse('$apiBaseUrl/subjects'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw TutorSearchException(
        'Subjects are temporarily unavailable. Please try again.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['subjects'] is! List) {
      throw const FormatException('Subject response is invalid.');
    }
    return [
      for (final item in decoded['subjects'] as List)
        if (item is Map<String, dynamic>)
          TutorSubject.fromJson(item)
        else
          throw const FormatException('Subject response is invalid.'),
    ];
  }
}

class TutorSearchException implements Exception {
  const TutorSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}
