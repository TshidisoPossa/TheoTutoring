import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';

// The admin bell (GET/POST /admin/notifications...): the same notification
// list students and tutors have, with admin events such as new tutor
// applications, reports and refunds to review.

class AdminNotificationsException implements Exception {
  const AdminNotificationsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The admin Notifications page: `unreadCount` and `notifications`.
Future<Map<String, dynamic>> fetchAdminNotifications() => _send(
  'GET',
  '/admin/notifications',
  failMessage: 'Could not load your notifications. Please try again.',
);

/// The number on the admin bell.
Future<int> fetchAdminUnreadCount() async {
  final body = await _send(
    'GET',
    '/admin/notifications/unread-count',
    failMessage: 'Could not load your notifications.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

/// Marks one notification read; returns the new unread count.
Future<int> markAdminNotificationRead(String id) async {
  final body = await _send(
    'POST',
    '/admin/notifications/$id/read',
    failMessage: 'Could not update this notification.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

/// "Mark all as read"; returns the new unread count.
Future<int> markAllAdminNotificationsRead() async {
  final body = await _send(
    'POST',
    '/admin/notifications/read-all',
    failMessage: 'Could not mark your notifications as read.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

Future<Map<String, dynamic>> _send(
  String method,
  String path, {
  required String failMessage,
}) async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null || token.isEmpty) {
    throw const AdminNotificationsException('Please sign in again.');
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
  } catch (_) {
    throw AdminNotificationsException(failMessage);
  }
  Object? body;
  try {
    body = jsonDecode(response.body);
  } on FormatException {
    body = null;
  }
  if (response.statusCode != 200 || body is! Map<String, dynamic>) {
    throw AdminNotificationsException(
      body is Map<String, dynamic> && body['error'] is String
          ? body['error'] as String
          : failMessage,
    );
  }
  return body;
}
