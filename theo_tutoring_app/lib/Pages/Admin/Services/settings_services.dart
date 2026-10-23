import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';

class AdminSettingsService {
  AdminSettingsService({
    FirebaseAuth? auth,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _providedAuth = auth,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _tokenProvider = tokenProvider ?? _firebaseToken;

  final FirebaseAuth? _providedAuth;
  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function() _tokenProvider;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  static Future<String?> _firebaseToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  void dispose() {
    if (_ownsClient) _client.close();
  }

  // Password changes go through Firebase Authentication; the backend never
  // receives the password itself.
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> signOut() => _auth.signOut();

  Future<Map<String, dynamic>> fetchSessionRate() => _sessionRateRequest(
    (uri, {headers}) => _client.get(uri, headers: headers),
  );

  Future<Map<String, dynamic>> updateSessionRate(String amount) =>
      _sessionRateRequest(
        (uri, {headers}) => _client.put(
          uri,
          headers: headers,
          body: jsonEncode({'amount': amount}),
        ),
      );

  Future<Map<String, dynamic>> _sessionRateRequest(
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers})
    send,
  ) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in is required to access session rate settings.');
    }
    final response = await send(
      Uri.parse('$apiBaseUrl/admin/session-rate'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 15));
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception('Session rate request failed (${response.statusCode}).');
    }
    if (response.statusCode != 200) {
      final message = decoded is Map ? decoded['error'] : null;
      throw Exception(
        message?.toString() ??
            'Session rate request failed (${response.statusCode}).',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid session rate response.');
    }
    return decoded;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      throw ArgumentError('The new password must be at least 6 characters.');
    }
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw StateError('Sign in again before changing your password.');
    }

    await reauthenticateAndUpdatePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      reauthenticate: (password) async {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        await user.reauthenticateWithCredential(credential);
      },
      updatePassword: user.updatePassword,
    );
  }
}

/// Ensures a password update cannot happen before recent-login verification.
Future<void> reauthenticateAndUpdatePassword({
  required String currentPassword,
  required String newPassword,
  required Future<void> Function(String password) reauthenticate,
  required Future<void> Function(String password) updatePassword,
}) async {
  await reauthenticate(currentPassword);
  await updatePassword(newPassword);
}
