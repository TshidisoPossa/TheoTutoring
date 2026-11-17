import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';

abstract interface class BookingFlowApi {
  Future<BookingAvailability> availability({
    required int tutorId,
    required int subjectId,
    required String from,
    required String through,
  });
  Future<BookingPurchaseResult> createPurchase(Map<String, Object> request);
  Future<PaymentAttemptResult> createPaymentAttempt({
    required int purchaseId,
    required String idempotencyKey,
    required String paymentMethod,
    required String simulatedOutcome,
  });
  void close();
}

/// Ends the student's own unpaid reservation early, so they can change their
/// lessons after going back from payment. Separate from [BookingFlowApi] so
/// existing implementations need not provide it.
abstract interface class BookingReleaseApi {
  /// POST /StudentlandingPage/booking-purchases/{id}/release. Returns the
  /// purchase status afterwards ('Cancelled', or 'Expired' if the holds had
  /// already run out); throws [BookingApiException] otherwise, e.g. with code
  /// `purchase_not_releasable` once it has been paid.
  Future<String> releasePurchase(int purchaseId);
}

class BookingApiException implements Exception {
  const BookingApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => message;
}

class AvailableBookingSlot {
  const AvailableBookingSlot({
    required this.date,
    required this.startTime,
    required this.endTime,
  });
  final String date;
  final String startTime;
  final String endTime;

  factory AvailableBookingSlot.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['date'] is! String ||
        value['startTime'] is! String ||
        value['endTime'] is! String) {
      throw const FormatException(
        'Availability response contains an invalid slot.',
      );
    }
    return AvailableBookingSlot(
      date: value['date'] as String,
      startTime: value['startTime'] as String,
      endTime: value['endTime'] as String,
    );
  }
}

/// The tutor's free 60-minute slots (from their weekly availability, minus
/// lessons already booked or held) and the platform rate for one lesson.
class BookingAvailability {
  const BookingAvailability({required this.slots, this.hourlyRate});
  final List<AvailableBookingSlot> slots;

  /// e.g. "180.00"; null if the response did not include it.
  final String? hourlyRate;
}

class BookingPurchaseResult {
  const BookingPurchaseResult({
    required this.purchaseId,
    required this.purchaseStatus,
    required this.totalAmount,
    required this.holdExpiresAt,
    required this.lessons,
    String? subtotal,
    this.discountPercent = 0,
    this.discountAmount = '0.00',
  }) : subtotal = subtotal ?? totalAmount;
  final int purchaseId;
  final String purchaseStatus;
  final String totalAmount;
  final String holdExpiresAt;
  final List<Map<String, dynamic>> lessons;

  /// Rate × lesson count before any package discount; the total is
  /// subtotal − discountAmount.
  final String subtotal;
  final int discountPercent;
  final String discountAmount;

  factory BookingPurchaseResult.fromJson(
    Object? value, {
    required int tutorId,
    required int subjectId,
  }) {
    if (value is! Map<String, dynamic> ||
        value['purchaseId'] is! int ||
        value['purchaseStatus'] is! String ||
        value['totalAmount'] is! String ||
        value['subtotal'] is! String ||
        value['discountPercent'] is! int ||
        value['discountAmount'] is! String ||
        value['holdExpiresAt'] is! String ||
        value['lessons'] is! List ||
        value['tutorId'] != tutorId ||
        value['subjectId'] != subjectId ||
        !const {
          'Draft',
          'Held',
          'PaymentPending',
          'Paid',
          'Cancelled',
          'Expired',
          'PartiallyRefunded',
          'Refunded',
        }.contains(value['purchaseStatus']) ||
        value['paymentOccurred'] != false ||
        value['lessonsConfirmed'] != false) {
      throw const FormatException('Booking response is incomplete or invalid.');
    }
    final lessons = value['lessons'] as List;
    if (lessons.isEmpty ||
        lessons.any(
          (e) =>
              e is! Map<String, dynamic> ||
              e['date'] is! String ||
              e['startTime'] is! String ||
              e['endTime'] is! String ||
              e['holdStatus'] is! String,
        )) {
      throw const FormatException('Booking response contains invalid lessons.');
    }
    return BookingPurchaseResult(
      purchaseId: value['purchaseId'] as int,
      purchaseStatus: value['purchaseStatus'] as String,
      totalAmount: value['totalAmount'] as String,
      holdExpiresAt: value['holdExpiresAt'] as String,
      lessons: lessons.cast<Map<String, dynamic>>(),
      subtotal: value['subtotal'] as String,
      discountPercent: value['discountPercent'] as int,
      discountAmount: value['discountAmount'] as String,
    );
  }
}

class PaymentAttemptResult {
  const PaymentAttemptResult({
    required this.paymentAttemptId,
    required this.attemptNumber,
    required this.paymentStatus,
    required this.purchaseStatus,
    required this.replayed,
    required this.settled,
  });

  final int paymentAttemptId;
  final int attemptNumber;
  final String paymentStatus;
  final String purchaseStatus;
  final bool replayed;
  final bool settled;

  bool get isSuccessful =>
      paymentStatus == 'Successful' && purchaseStatus == 'Paid' && settled;

  factory PaymentAttemptResult.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['paymentAttemptId'] is! int ||
        value['attemptNumber'] is! int ||
        value['paymentStatus'] is! String ||
        value['purchaseStatus'] is! String ||
        value['replayed'] is! bool ||
        value['settled'] is! bool) {
      throw const FormatException('Payment response is incomplete or invalid.');
    }
    final status = value['paymentStatus'] as String;
    final purchaseStatus = value['purchaseStatus'] as String;
    final settled = value['settled'] as bool;
    if ((status == 'Successful' && (purchaseStatus != 'Paid' || !settled)) ||
        (status == 'Failed' && (purchaseStatus != 'Held' || settled)) ||
        (status != 'Successful' && status != 'Failed')) {
      throw const FormatException('Payment response has an invalid status.');
    }
    return PaymentAttemptResult(
      paymentAttemptId: value['paymentAttemptId'] as int,
      attemptNumber: value['attemptNumber'] as int,
      paymentStatus: status,
      purchaseStatus: purchaseStatus,
      replayed: value['replayed'] as bool,
      settled: settled,
    );
  }
}

class HttpBookingFlowApi implements BookingFlowApi, BookingReleaseApi {
  HttpBookingFlowApi({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  static Future<String?> _firebaseToken() =>
      FirebaseAuth.instance.currentUser?.getIdToken() ??
      Future<String?>.value();

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty)
      throw const BookingApiException('Sign in as a student to book a lesson.');
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  @override
  Future<BookingAvailability> availability({
    required int tutorId,
    required int subjectId,
    required String from,
    required String through,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/StudentlandingPage/availability')
        .replace(
          queryParameters: {
            'tutorId': '$tutorId',
            'subjectId': '$subjectId',
            'from': from,
            'through': through,
          },
        );
    try {
      final response = await _client
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200)
        throw BookingApiException(
          _error(response, 'Available times could not be loaded.'),
        );
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['slots'] is! List)
        throw const FormatException('Availability response is invalid.');
      final rate = body['hourlyRate'];
      return BookingAvailability(
        hourlyRate: rate is String ? rate : null,
        slots: [
          for (final slot in body['slots'] as List)
            AvailableBookingSlot.fromJson(slot),
        ],
      );
    } on BookingApiException {
      rethrow;
    } on FormatException {
      throw const BookingApiException('Availability response is invalid.');
    } catch (_) {
      throw const BookingApiException(
        'Available times could not be loaded. Check your connection and retry.',
      );
    }
  }

  @override
  Future<BookingPurchaseResult> createPurchase(
    Map<String, Object> request,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$apiBaseUrl/StudentlandingPage/booking-purchases'),
            headers: await _headers(),
            body: jsonEncode(request),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 && response.statusCode != 201)
        throw BookingApiException(
          _error(response, 'Booking could not be submitted.'),
        );
      return BookingPurchaseResult.fromJson(
        jsonDecode(response.body),
        tutorId: request['tutorId']! as int,
        subjectId: request['subjectId']! as int,
      );
    } on BookingApiException {
      rethrow;
    } on FormatException {
      throw const BookingApiException('Booking response is invalid.');
    } catch (_) {
      throw const BookingApiException(
        'Booking result could not be confirmed. Retry with the same request.',
      );
    }
  }

  @override
  Future<PaymentAttemptResult> createPaymentAttempt({
    required int purchaseId,
    required String idempotencyKey,
    required String paymentMethod,
    required String simulatedOutcome,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(
              '$apiBaseUrl/StudentlandingPage/booking-purchases/'
              '$purchaseId/payment-attempts',
            ),
            headers: await _headers(),
            body: jsonEncode({
              'idempotencyKey': idempotencyKey,
              'paymentMethod': paymentMethod,
              'simulatedOutcome': simulatedOutcome,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw _apiException(
          response,
          'Payment attempt could not be completed.',
        );
      }
      return PaymentAttemptResult.fromJson(jsonDecode(response.body));
    } on BookingApiException {
      rethrow;
    } on FormatException {
      throw const BookingApiException('Payment response is invalid.');
    } catch (_) {
      throw const BookingApiException(
        'Payment result could not be confirmed. Retry using the same request.',
      );
    }
  }

  @override
  Future<String> releasePurchase(int purchaseId) async {
    try {
      final response = await _client
          .post(
            Uri.parse(
              '$apiBaseUrl/StudentlandingPage/booking-purchases/'
              '$purchaseId/release',
            ),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw _apiException(
          response,
          'Your reserved times could not be released.',
        );
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body['purchaseId'] != purchaseId ||
          (body['purchaseStatus'] != 'Cancelled' &&
              body['purchaseStatus'] != 'Expired')) {
        throw const FormatException('Release response is invalid.');
      }
      return body['purchaseStatus'] as String;
    } on BookingApiException {
      rethrow;
    } on FormatException {
      throw const BookingApiException('Release response is invalid.');
    } catch (_) {
      throw const BookingApiException(
        'Your reserved times could not be released. Check your connection '
        'and try again.',
      );
    }
  }

  BookingApiException _apiException(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        return BookingApiException(
          body['error'] is String ? body['error'] as String : fallback,
          statusCode: response.statusCode,
          code: body['code'] is String ? body['code'] as String : null,
        );
      }
    } on FormatException {
      // Non-JSON responses use the fallback message.
    }
    return BookingApiException(fallback, statusCode: response.statusCode);
  }

  String _error(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['error'] is String)
        return body['error'] as String;
    } catch (_) {
      /* use fallback */
    }
    return fallback;
  }

  @override
  void close() => _client.close();
}
