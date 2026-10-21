import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:theo_tutoring_backend/env.dart';

/// The signed-in user, taken from a verified Firebase ID token.
class FirebaseUser {
  const FirebaseUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
}

/// Thrown when the sign-in token is missing, invalid or expired.
class AuthTokenException implements Exception {
  const AuthTokenException(this.message);
  final String message;
}

const _certsUrl =
    'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

Map<String, String> _certs = {};
DateTime _certsExpiry = DateTime.fromMillisecondsSinceEpoch(0);

/// Loads Google's public signing keys and caches them for as long as
/// Google's Cache-Control header allows.
Future<Map<String, String>> _getCerts() async {
  if (_certs.isNotEmpty && DateTime.now().isBefore(_certsExpiry)) {
    return _certs;
  }

  final response = await http.get(Uri.parse(_certsUrl));
  if (response.statusCode != 200) {
    throw StateError('Could not load Firebase signing keys');
  }

  _certs = (jsonDecode(response.body) as Map<String, dynamic>)
      .cast<String, String>();

  final maxAge = RegExp(
    r'max-age=(\d+)',
  ).firstMatch(response.headers['cache-control'] ?? '')?.group(1);
  _certsExpiry = DateTime.now().add(
    Duration(seconds: int.tryParse(maxAge ?? '') ?? 3600),
  );

  return _certs;
}

/// Verifies a Firebase ID token from an "Authorization: Bearer <token>"
/// header and returns the signed-in user.
Future<FirebaseUser> verifyFirebaseToken(String? authHeader) async {
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    throw const AuthTokenException('You must be signed in.');
  }

  final token = authHeader.substring(7).trim();

  final projectId = env['FIREBASE_PROJECT_ID'];
  if (projectId == null || projectId.isEmpty) {
    throw StateError('FIREBASE_PROJECT_ID is not set');
  }

  final JWT unverified;
  try {
    unverified = JWT.decode(token);
  } catch (_) {
    throw const AuthTokenException('Invalid sign-in token.');
  }

  final header = unverified.header ?? const <String, dynamic>{};
  if (header['alg'] != 'RS256') {
    throw const AuthTokenException('Invalid sign-in token.');
  }

  final certs = await _getCerts();
  final pem = certs[header['kid']];
  if (pem == null) {
    throw const AuthTokenException('Invalid sign-in token.');
  }

  final JWT verified;
  try {
    verified = JWT.verify(
      token,
      RSAPublicKey.cert(pem),
      audience: Audience.one(projectId),
      issuer: 'https://securetoken.google.com/$projectId',
    );
  } on JWTExpiredException {
    throw const AuthTokenException(
      'Your session has expired. Please sign in again.',
    );
  } on JWTException {
    throw const AuthTokenException('Invalid sign-in token.');
  }

  final payload = verified.payload as Map<String, dynamic>;
  final uid = payload['sub'];
  if (uid is! String || uid.isEmpty || uid.length > 128) {
    throw const AuthTokenException('Invalid sign-in token.');
  }

  return FirebaseUser(
    uid: uid,
    email: (payload['email'] as String?)?.trim().toLowerCase(),
    emailVerified: payload['email_verified'] == true,
  );
}
