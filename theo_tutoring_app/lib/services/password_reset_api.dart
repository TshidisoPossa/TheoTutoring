import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api.dart';

/// The email could not be checked (server down, network, bad response).
class PasswordResetCheckException implements Exception {
  const PasswordResetCheckException(this.message);
  final String message;
}

/// Asks the backend whether a Firebase account uses an email. Firebase's own
/// sendPasswordResetEmail cannot tell us: with email enumeration protection
/// on it reports success even when no account exists.
class PasswordResetApi {
  PasswordResetApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<bool> emailExists(String email) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$apiBaseUrl/auth/password-reset/check'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const PasswordResetCheckException(
        'Could not connect to the server. Please try again.',
      );
    }

    if (response.statusCode == 400) {
      throw const PasswordResetCheckException(
        'That email address looks invalid.',
      );
    }
    if (response.statusCode != 200) {
      throw const PasswordResetCheckException(
        'Could not check that email right now. Please try again.',
      );
    }

    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (body is! Map<String, dynamic> || body['exists'] is! bool) {
      throw const PasswordResetCheckException(
        'The server returned an invalid response. Please try again.',
      );
    }
    return body['exists'] as bool;
  }
}
