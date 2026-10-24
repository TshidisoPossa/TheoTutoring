import 'dart:convert';
import 'package:theo_tutoring_backend/env.dart';
import 'package:http/http.dart' as http;

// Verifies a Firebase ID token and returns the user's UID, or null if invalid
Future<String?> verifyFirebaseToken(String idToken) async {
  final apiKey = env['FIREBASE_API_KEY'];
  if (apiKey == null) return null;
  final res = await http.post(
    Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$apiKey',
    ),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'idToken': idToken}),
  );
  if (res.statusCode != 200) return null;
  final users =
      jsonDecode(res.body)['users'] as List?;
  if (users == null || users.isEmpty) return null;
  return users.first['localId'] as String; // localId is the Firebase UID
}
