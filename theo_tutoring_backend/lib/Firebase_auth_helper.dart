import 'dart:convert'; // for jsonEncode / jsonDecode
import 'package:theo_tutoring_backend/env.dart'; // for env
import 'package:http/http.dart' as http; // for the HTTP call to Firebase

// Verifies a Firebase ID token and returns the user's UID, or null if invalid
Future<String?> verifyFirebaseToken(String idToken) async {
  final apiKey = env['FIREBASE_API_KEY']; // read the key from .env
  if (apiKey == null) return null; // no key configured, cannot verify
  final res = await http.post(
    Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$apiKey', // Firebase lookup endpoint
    ),
    headers: {'Content-Type': 'application/json'}, // body is JSON
    body: jsonEncode({'idToken': idToken}), // send the token to Firebase
  );
  if (res.statusCode != 200) return null; // Firebase rejected the token
  final users =
      jsonDecode(res.body)['users'] as List?; // list of matching users
  if (users == null || users.isEmpty) return null; // nobody found
  return users.first['localId'] as String; // localId is the Firebase UID
}
