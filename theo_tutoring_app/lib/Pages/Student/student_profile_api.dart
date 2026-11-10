import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';

/// What GET /students/profile returns for the Profile tab.
class StudentProfileData {
  const StudentProfileData({
    required this.name,
    required this.email,
    required this.photo,
    required this.institution,
    this.subjectsOfInterest = const [],
  });

  factory StudentProfileData.fromJson(Map<String, dynamic> json) =>
      StudentProfileData(
        name: json['name'] as String?,
        email: json['email'] as String?,
        photo: json['photo'] as String?,
        institution: json['institution'] as String?,
        subjectsOfInterest: _strings(json['subjectsOfInterest']),
      );

  final String? name;
  final String? email;
  final String? photo; // Cloudinary URL, null if none was uploaded
  final String? institution; // null for older accounts
  final List<String> subjectsOfInterest;

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];
}

/// What PATCH /students/profile answers: the saved profile and a message.
class StudentProfileSaved {
  const StudentProfileSaved({required this.profile, required this.message});

  final StudentProfileData profile;
  final String message;
}

class StudentProfileApi {
  StudentProfileApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<StudentProfileData> fetch() async {
    final body = await _send(
      'GET',
      '/students/profile',
      failMessage: 'Profile could not be loaded.',
    );
    return StudentProfileData.fromJson(body);
  }

  /// Saves only the fields in [changes] (names as in the backend:
  /// name, photo, institution, subjectsOfInterest).
  Future<StudentProfileSaved> update(Map<String, Object?> changes) async {
    final body = await _send(
      'PATCH',
      '/students/profile',
      body: changes,
      failMessage: 'Your profile could not be saved. Please try again.',
    );
    return StudentProfileSaved(
      profile: StudentProfileData.fromJson(body),
      message: body['message'] as String? ?? 'Your profile has been saved.',
    );
  }

  /// Subject names from the catalogue (GET /subjects), for the chips.
  Future<List<String>> fetchSubjects() async {
    final body = await _send(
      'GET',
      '/subjects',
      failMessage: 'Subjects could not be loaded.',
      signedIn: false,
    );
    return [
      for (final subject in body['subjects'] as List<dynamic>? ?? [])
        if (subject is Map<String, dynamic> &&
            subject['subjectName'] is String)
          subject['subjectName'] as String,
    ];
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    required String failMessage,
    bool signedIn = true,
  }) async {
    final headers = {'Accept': 'application/json'};
    if (signedIn) {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        throw const StudentProfileException('Please sign in again.');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) headers['Content-Type'] = 'application/json';

    final request = http.Request(method, Uri.parse('$apiBaseUrl$path'))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 15)),
    );
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error'] as String? ?? failMessage
          : failMessage;
      throw StudentProfileException(message);
    }
    if (decoded is! Map<String, dynamic>) {
      throw StudentProfileException(failMessage);
    }
    return decoded;
  }
}

class StudentProfileException implements Exception {
  const StudentProfileException(this.message);

  final String message;

  @override
  String toString() => message;
}
