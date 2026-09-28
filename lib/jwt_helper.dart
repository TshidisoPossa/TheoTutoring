import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

String generateToken(int userId, String role) {
  final jwt = JWT({'userId': userId, 'role': role});
  return jwt.sign(
    SecretKey(Platform.environment['JWT_SECRET'] ?? 'secret'),
    expiresIn: const Duration(days: 7),
  );
}

Map<String, dynamic>? verifyToken(String token) {
  try {
    final jwt = JWT.verify(
      token,
      SecretKey(Platform.environment['JWT_SECRET'] ?? 'secret'),
    );
    return jwt.payload as Map<String, dynamic>;
  } catch (e) {
    return null;
  }
}