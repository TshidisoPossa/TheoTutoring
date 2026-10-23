import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:theo_tutoring_backend/env.dart';

/// Thrown when the Firebase service account is missing, unreadable or
/// rejected by Google (a server configuration problem).
class FirebaseAdminException implements Exception {
  /// Creates the exception.
  const FirebaseAdminException(this.message);

  /// What is wrong (for the server log).
  final String message;

  @override
  String toString() => 'FirebaseAdminException: $message';
}

/// Signs the backend in to Google APIs (Firestore, Cloud Messaging) with the
/// Firebase service-account key. Dart has no official Firebase Admin SDK, so
/// this does the OAuth "JWT bearer" exchange itself.
///
/// The key file is downloaded from Firebase console > Project settings >
/// Service accounts, kept OUT of git, and its path set in
/// FIREBASE_SERVICE_ACCOUNT_FILE (or GOOGLE_APPLICATION_CREDENTIALS).
class FirebaseAdmin {
  FirebaseAdmin._(this.projectId, this._clientEmail, this._privateKey);

  /// Loads the service account named in the environment.
  /// Throws a [FirebaseAdminException] if it is missing or cannot be read.
  factory FirebaseAdmin.fromEnvironment() {
    final path =
        env['FIREBASE_SERVICE_ACCOUNT_FILE'] ??
        env['GOOGLE_APPLICATION_CREDENTIALS'];
    if (path == null || path.isEmpty) {
      throw const FirebaseAdminException(
        'FIREBASE_SERVICE_ACCOUNT_FILE is not set',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      throw const FirebaseAdminException(
        'Could not read the Firebase service account file',
      );
    }

    final clientEmail = json['client_email'];
    final privateKey = json['private_key'];
    final projectId = json['project_id'] ?? env['FIREBASE_PROJECT_ID'];
    if (clientEmail is! String ||
        privateKey is! String ||
        projectId is! String) {
      throw const FirebaseAdminException(
        'The Firebase service account file is incomplete',
      );
    }
    return FirebaseAdmin._(projectId, clientEmail, privateKey);
  }

  static FirebaseAdmin? _instance;

  /// One shared instance so the access token is cached across requests.
  // ignore: prefer_constructors_over_static_methods
  static FirebaseAdmin get instance =>
      _instance ??= FirebaseAdmin.fromEnvironment();

  /// Firebase project the key belongs to.
  final String projectId;
  final String _clientEmail;
  final String _privateKey;

  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _scopes = [
    'https://www.googleapis.com/auth/datastore', // Firestore
    'https://www.googleapis.com/auth/firebase.messaging', // Cloud Messaging
    'https://www.googleapis.com/auth/identitytoolkit', // Admin account creation
  ];

  String? _accessToken;
  DateTime _accessTokenExpiry = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns a Google OAuth access token, reusing the cached one until a
  /// minute before it expires.
  Future<String> accessToken() async {
    if (_accessToken != null && DateTime.now().isBefore(_accessTokenExpiry)) {
      return _accessToken!;
    }

    final String assertion;
    try {
      assertion =
          JWT(
            {
              'scope': _scopes.join(' '),
            },
            issuer: _clientEmail,
            audience: Audience.one(_tokenUrl),
          ).sign(
            RSAPrivateKey(_privateKey),
            algorithm: JWTAlgorithm.RS256,
            expiresIn: const Duration(hours: 1),
          );
    } catch (_) {
      throw const FirebaseAdminException(
        'The Firebase service account private key is invalid',
      );
    }

    final response = await http.post(
      Uri.parse(_tokenUrl),
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
      },
    );
    if (response.statusCode != 200) {
      throw const FirebaseAdminException(
        'Google rejected the Firebase service account',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    _accessToken = body['access_token'] as String;
    _accessTokenExpiry = DateTime.now().add(
      Duration(seconds: expiresIn - 60),
    );
    return _accessToken!;
  }
}
