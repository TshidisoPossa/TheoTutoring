import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';

/// Thrown when a tutor page could not be loaded from the backend.
class TutorApiException implements Exception {
  const TutorApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode; // HTTP status, null if the server was not reached

  @override
  String toString() => message;
}

/// Loads the tutor dashboard (GET /TutorLandingpage/LandingPageScreen).
/// Active tutors get stats, today's schedule and reviews.
/// Pending tutors get `accountStatus: 'Pending'` and their `application`.
/// Pass [idToken] when it is already known (e.g. right after login).
Future<Map<String, dynamic>> fetchTutorDashboard({String? idToken}) {
  return _send(
    'GET',
    '/TutorLandingpage/LandingPageScreen',
    idToken: idToken,
    failMessage: 'Could not load your dashboard. Please try again.',
  );
}

/// Loads the Schedule page (GET /TutorLandingpage/schedule).
/// [tab] is upcoming | new | past | all, [date] is all | today | tomorrow |
/// week, and [subjectIds] limits it to those subjects (empty = all).
Future<Map<String, dynamic>> fetchTutorSchedule({
  String tab = 'upcoming',
  String date = 'all',
  List<int> subjectIds = const [],
}) {
  return _send(
    'GET',
    '/TutorLandingpage/schedule',
    query: {
      'tab': tab,
      'date': date,
      if (subjectIds.isNotEmpty) 'subjectId': subjectIds.join(','),
    },
    failMessage: 'Could not load your schedule. Please try again.',
  );
}

/// Loads one booking for the details page
/// (GET /TutorLandingpage/bookings/{id}).
Future<Map<String, dynamic>> fetchTutorBooking(int bookingId) {
  return _send(
    'GET',
    '/TutorLandingpage/bookings/$bookingId',
    failMessage: 'Could not load this session. Please try again.',
  );
}

/// The Decline button: moves the booking to a new time that the student
/// must confirm (POST /TutorLandingpage/bookings/{id}/postpone).
/// [date] is "2026-10-31", [startTime] and [endTime] are "16:00".
Future<Map<String, dynamic>> postponeTutorBooking(
  int bookingId, {
  required String date,
  required String startTime,
  required String endTime,
}) {
  return _send(
    'POST',
    '/TutorLandingpage/bookings/$bookingId/postpone',
    body: {'date': date, 'startTime': startTime, 'endTime': endTime},
    failMessage: 'Could not postpone this session. Please try again.',
  );
}

/// "I'm still using the app" (POST /TutorLandingpage/presence). Students
/// see "Available Now" on this tutor's profile while the pings keep coming.
Future<void> pingTutorPresence() {
  return _send(
    'POST',
    '/TutorLandingpage/presence',
    body: const {},
    failMessage: 'Could not update your availability.',
  );
}

/// Signed out: show the tutor offline straight away
/// (DELETE /TutorLandingpage/presence).
Future<void> clearTutorPresence() {
  return _send(
    'DELETE',
    '/TutorLandingpage/presence',
    failMessage: 'Could not update your availability.',
  );
}

/// The bell's page (GET /TutorLandingpage/notifications): `unreadCount` and
/// `notifications`, newest first. Each has id, type, title, body,
/// bookingId, read, createdAt, minutesAgo and section (today | yesterday |
/// earlier).
Future<Map<String, dynamic>> fetchTutorNotifications() {
  return _send(
    'GET',
    '/TutorLandingpage/notifications',
    failMessage: 'Could not load your notifications. Please try again.',
  );
}

/// The number on the bell (GET /TutorLandingpage/notifications/unread-count).
Future<int> fetchTutorUnreadCount() async {
  final body = await _send(
    'GET',
    '/TutorLandingpage/notifications/unread-count',
    failMessage: 'Could not load your notifications.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

/// Marks one notification read (POST /TutorLandingpage/notifications/{id}/read).
/// Returns the new unread count.
Future<int> markTutorNotificationRead(String id) async {
  final body = await _send(
    'POST',
    '/TutorLandingpage/notifications/$id/read',
    body: const {},
    failMessage: 'Could not update this notification.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

/// "Mark all as read" (POST /TutorLandingpage/notifications/read-all).
/// Returns the new unread count.
Future<int> markAllTutorNotificationsRead() async {
  final body = await _send(
    'POST',
    '/TutorLandingpage/notifications/read-all',
    body: const {},
    failMessage: 'Could not mark your notifications as read.',
  );
  return (body['unreadCount'] as num?)?.toInt() ?? 0;
}

/// Loads the Profile page (GET /TutorLandingpage/Profile).
Future<Map<String, dynamic>> fetchTutorProfile() {
  return _send(
    'GET',
    '/TutorLandingpage/Profile',
    failMessage: 'Could not load your profile. Please try again.',
  );
}

/// Saves the availability grid (PUT /TutorLandingpage/Profile/availability).
/// [availability] is e.g. {"Monday": ["Morning", "Evening"]}; days left out
/// have no availability.
Future<Map<String, dynamic>> saveTutorAvailability(
  Map<String, List<String>> availability,
) {
  return _send(
    'PUT',
    '/TutorLandingpage/Profile/availability',
    body: {'availability': availability},
    failMessage: 'Could not save your availability. Please try again.',
  );
}

/// Changes one date in the availability calendar
/// (PUT /TutorLandingpage/Profile/availability-dates). [mode] is 'usual'
/// (back to the weekly hours), 'off' (day off) or 'custom' with [times]
/// such as [{"startTime": "09:00", "endTime": "12:00"}]. The response holds
/// the updated `availabilityCalendar`.
Future<Map<String, dynamic>> saveTutorDateAvailability({
  required String date,
  required String mode,
  List<Map<String, String>> times = const [],
}) {
  return _send(
    'PUT',
    '/TutorLandingpage/Profile/availability-dates',
    body: {
      'date': date,
      'mode': mode,
      if (mode == 'custom') 'times': times,
    },
    failMessage: 'Could not save this date. Please try again.',
  );
}

/// Saves the About Me text (PUT /TutorLandingpage/Profile/about).
/// The backend uses the registration bio rule (20 to 300 characters).
Future<Map<String, dynamic>> saveTutorAbout(String about) {
  return _send(
    'PUT',
    '/TutorLandingpage/Profile/about',
    body: {'about': about},
    failMessage: 'Could not save your About Me. Please try again.',
  );
}

/// Replaces the subjects the tutor teaches
/// (PUT /TutorLandingpage/Profile/subjects). [subjectIds] is the full list.
Future<Map<String, dynamic>> saveTutorSubjects(List<int> subjectIds) {
  return _send(
    'PUT',
    '/TutorLandingpage/Profile/subjects',
    body: {'subjectIds': subjectIds},
    failMessage: 'Could not save your subjects. Please try again.',
  );
}

/// Every subject on the platform (GET /subjects), for "+ Add Subject".
Future<List<Map<String, dynamic>>> fetchAllSubjects() async {
  final body = await _send(
    'GET',
    '/subjects',
    failMessage: 'Could not load the subjects. Please try again.',
  );
  return (body['subjects'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();
}

/// Saves a profile photo already uploaded to Cloudinary
/// (PUT /TutorLandingpage/Profile/photo).
Future<Map<String, dynamic>> saveTutorPhoto(String profilePhotoUrl) {
  return _send(
    'PUT',
    '/TutorLandingpage/Profile/photo',
    body: {'profilePhotoUrl': profilePhotoUrl},
    failMessage: 'Could not update your photo. Please try again.',
  );
}

// Sends one request to a /TutorLandingpage route with the Firebase ID token
// and returns the JSON object it sends back. Errors become a
// TutorApiException with the server's message when it gave one.
Future<Map<String, dynamic>> _send(
  String method,
  String path, {
  required String failMessage,
  Map<String, String>? query,
  Map<String, dynamic>? body,
  String? idToken,
}) async {
  final token =
      idToken ?? await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null || token.isEmpty) {
    throw const TutorApiException(
      'You are signed out. Please log in again.',
      statusCode: 401,
    );
  }

  final uri = Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);
  final headers = {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    if (body != null) 'Content-Type': 'application/json',
  };

  final http.Response response;
  try {
    final request = switch (method) {
      'POST' => http.post(uri, headers: headers, body: jsonEncode(body)),
      'PUT' => http.put(uri, headers: headers, body: jsonEncode(body)),
      'DELETE' => http.delete(uri, headers: headers),
      _ => http.get(uri, headers: headers),
    };
    response = await request.timeout(const Duration(seconds: 15));
  } on Exception {
    throw const TutorApiException(
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
    throw TutorApiException(switch (response.statusCode) {
      401 => 'Your session could not be verified. Please sign in again.',
      403 => 'This account does not have an active tutor profile.',
      // 400 / 404 / 409 carry a message written for the tutor
      _ when serverMessage is String && serverMessage.isNotEmpty =>
        serverMessage,
      404 => 'No tutor profile was found for this account.',
      _ => failMessage,
    }, statusCode: response.statusCode);
  }

  if (decoded is Map<String, dynamic>) return decoded;
  throw const TutorApiException(
    'The server returned an invalid response. Please try again.',
  );
}
