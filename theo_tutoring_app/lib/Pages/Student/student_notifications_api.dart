import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';

/// Thrown when the student's notifications could not be loaded or updated.
class StudentNotificationsException implements Exception {
  const StudentNotificationsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The bell's page (GET /students/notifications): `unreadCount` and
/// `notifications`, newest first.
Future<Map<String, dynamic>> fetchStudentNotifications() {
  return _send(
    'GET',
    '/students/notifications',
    failMessage: 'Could not load your notifications. Please try again.',
  );
}

/// The number on the bell (GET /students/notifications/unread-count).
Future<int> fetchStudentUnreadCount() async {
  final body = await _send(
    'GET',
    '/students/notifications/unread-count',
    failMessage: 'Could not load your notifications.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

/// Marks one notification read (POST /students/notifications/{id}/read).
/// Returns the new unread count.
Future<int> markStudentNotificationRead(String id) async {
  final body = await _send(
    'POST',
    '/students/notifications/$id/read',
    failMessage: 'Could not update this notification.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

/// "Mark all as read" (POST /students/notifications/read-all).
/// Returns the new unread count.
Future<int> markAllStudentNotificationsRead() async {
  final body = await _send(
    'POST',
    '/students/notifications/read-all',
    failMessage: 'Could not mark your notifications as read.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

// Sends one request with the Firebase ID token and returns the JSON object
// the server sends back, or throws with the server's message.
Future<Map<String, dynamic>> _send(
  String method,
  String path, {
  required String failMessage,
}) async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null || token.isEmpty) {
    throw const StudentNotificationsException('Please sign in again.');
  }
  final uri = Uri.parse('$apiBaseUrl$path');
  final headers = {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  final http.Response response;
  try {
    response = await (method == 'POST'
            ? http.post(uri, headers: headers)
            : http.get(uri, headers: headers))
        .timeout(const Duration(seconds: 15));
  } on Exception {
    throw const StudentNotificationsException(
      'Could not connect to the server. Please try again.',
    );
  }

  dynamic decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    decoded = null;
  }
  if (response.statusCode != 200) {
    final serverMessage = decoded is Map ? decoded['error'] : null;
    throw StudentNotificationsException(
      serverMessage is String && serverMessage.isNotEmpty
          ? serverMessage
          : failMessage,
    );
  }
  if (decoded is Map<String, dynamic>) return decoded;
  throw StudentNotificationsException(failMessage);
}
