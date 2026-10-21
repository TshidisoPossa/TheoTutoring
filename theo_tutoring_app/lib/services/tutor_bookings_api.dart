import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';

class TutorBooking {
  const TutorBooking({
    required this.bookingId,
    required this.status,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.subject,
    required this.studentName,
    this.note,
    this.link,
  });

  final int bookingId;
  final String status;
  final String date;
  final String startTime;
  final String endTime;
  final String subject;
  final String studentName;
  final String? note;
  final String? link;

  factory TutorBooking.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['bookingId'] is! int ||
        value['status'] is! String ||
        value['date'] is! String ||
        value['startTime'] is! String ||
        value['endTime'] is! String ||
        value['subject'] is! String ||
        value['studentName'] is! String) {
      throw const FormatException('Tutor booking response is invalid.');
    }
    return TutorBooking(
      bookingId: value['bookingId'] as int,
      status: value['status'] as String,
      date: value['date'] as String,
      startTime: value['startTime'] as String,
      endTime: value['endTime'] as String,
      subject: value['subject'] as String,
      studentName: value['studentName'] as String,
      note: value['note'] is String ? value['note'] as String : null,
      link: value['link'] is String ? value['link'] as String : null,
    );
  }
}

class TutorBookingsException implements Exception {
  const TutorBookingsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract interface class TutorBookingsSource {
  Future<List<TutorBooking>> bookings();
}

class TutorBookingsApi implements TutorBookingsSource {
  TutorBookingsApi({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken;

  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  static Future<String?> _firebaseToken() =>
      FirebaseAuth.instance.currentUser?.getIdToken() ??
      Future<String?>.value();

  @override
  Future<List<TutorBooking>> bookings() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const TutorBookingsException('Sign in as a tutor to see bookings.');
    }
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$apiBaseUrl/TutorLandingpage/bookings'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const TutorBookingsException(
        'Bookings could not be loaded. Check your connection and retry.',
      );
    }
    if (response.statusCode == 401) {
      throw const TutorBookingsException(
        'Your session has expired. Sign in again.',
        statusCode: 401,
      );
    }
    if (response.statusCode == 403) {
      throw const TutorBookingsException(
        'Bookings are available once your tutor account is active.',
        statusCode: 403,
      );
    }
    if (response.statusCode != 200) {
      throw TutorBookingsException(
        'Bookings are temporarily unavailable. Please try again.',
        statusCode: response.statusCode,
      );
    }
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['bookings'] is! List) {
        throw const FormatException('Tutor bookings response is invalid.');
      }
      return [
        for (final item in body['bookings'] as List)
          TutorBooking.fromJson(item),
      ];
    } on FormatException {
      throw const TutorBookingsException(
        'Bookings response was invalid. Please try again.',
      );
    }
  }

  void close() => _client.close();
}
