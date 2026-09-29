import 'dart:convert'; // for jsonDecode
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart'; // to verify the token
import 'package:http/http.dart'
    as http; // to download Google's public certificates

const _projectId =
    'YOUR_FIREBASE_PROJECT_ID'; // Firebase project ID from the Firebase console
const _certUrl =
    'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com'; // where Google publishes its signing certificates

//hecks that a request really comes from a signed-in user. Deliverable 3 has Firebase Authentication handling login, so the app
//sends the user's Firebase ID token with each request. The file's verifyFirebaseToken function does three things:

//How the code works

Map<String, String> _certs = {}; // cached certificates, keyed by key id (kid)
DateTime _certsExpiry = DateTime.fromMillisecondsSinceEpoch(
  0,
); // when the cache must be refreshed

Future<void> _refreshCerts() async {
  // downloads Google's current certificates
  final res = await http.get(Uri.parse(_certUrl)); // request the certificates
  if (res.statusCode != 200)
    throw Exception(
      'Could not fetch certificates',
    ); // fail if Google did not answer
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
    // any failure below means the token is rejected
    final kid =
        JWT.decode(idToken).header?['kid']
            as String?; // read which key signed the token
    if (kid == null) return null; // no key id, reject
    if (DateTime.now().isAfter(_certsExpiry) || !_certs.containsKey(kid)) {
      // cache stale or key unknown
      await _refreshCerts(); // download fresh certificates
    }
    final pem = _certs[kid]; // certificate for this key id
    if (pem == null) return null; // unknown key, reject
    final jwt = JWT.verify(
      // checks signature and expiry
      idToken, // the token sent by the app
      RSAPublicKey.cert(pem), // Google's public key
      issuer:
          'https://securetoken.google.com/$_projectId', // must be issued for our project
      audience: Audience.one(_projectId), // must be meant for our project
    );
    final uid = jwt.subject; // the 'sub' claim is the Firebase UID
    if (uid == null || uid.isEmpty)
      return null; // a valid token always has a UID
    return uid; // routes use this as User.UserId
  } catch (_) {
    // bad signature, expired, wrong project, network error
    return null; // treat every failure as unauthorised
  }
}
