import 'dart:convert';
import 'dart:io';
<<<<<<< HEAD

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

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
=======

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart'; // to verify the token
import 'package:http/http.dart'
    as http; // to download Google's public certificates

final _projectId = Platform.environment['FIREBASE_PROJECT_ID'];
const _certUrl =
    'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

Map<String, String> _certs = {}; // cached certificates, keyed by key id (kid)
DateTime _certsExpiry = DateTime.fromMillisecondsSinceEpoch(
  0,
); // when the cache must be refreshed

Future<void> _refreshCerts() async {
  // downloads Google's current certificates
  final res = await http.get(Uri.parse(_certUrl)); // request the certificates
  if (res.statusCode != 200) {
    throw Exception(
      'Could not fetch certificates',
    );
  }
  final data =
      jsonDecode(res.body) as Map<String, dynamic>; // parse the JSON body
  _certs = data.map(
    (k, v) => MapEntry(k, v as String),
  ); // keep kid -> PEM certificate
  _certsExpiry = DateTime.now().add(
    const Duration(hours: 1),
  ); // reuse the cache for one hour
}

/// Returns the Firebase UID if the ID token is valid, otherwise null.
Future<String?> verifyFirebaseToken(String idToken) async {
  // main helper used by routes
  try {
    final projectId = _projectId;
    if (projectId == null || projectId.isEmpty) {
      return null;
    }

    final decoded = JWT.decode(idToken);
    final claims = decoded.payload;
    if (claims is! Map || claims['exp'] is! num) {
      return null;
    }
    final subject = claims['sub'];
    if (subject is! String || subject.isEmpty) {
      return null;
    }

    final kid = decoded.header?['kid'] as String?;
    if (kid == null) {
      return null;
    }
    if (DateTime.now().isAfter(_certsExpiry) || !_certs.containsKey(kid)) {
      await _refreshCerts();
    }
    final pem = _certs[kid];
    if (pem == null) {
      return null;
    }
    final jwt = JWT.verify(
      idToken,
      RSAPublicKey.cert(pem),
      issuer: 'https://securetoken.google.com/$projectId',
      audience: Audience.one(projectId),
    );
    final uid = jwt.subject;
    if (uid == null || uid.isEmpty) {
      return null;
    }
    return uid;
  } catch (_) {
    return null;
>>>>>>> dfeda233982bf193b99c751ad147d933d3e08d48
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

  final projectId = Platform.environment['FIREBASE_PROJECT_ID'];
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
