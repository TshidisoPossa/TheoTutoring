import 'dart:convert';
import 'dart:io';

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
  }
}
