import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';

/// One lesson on a receipt, as it is now (a moved lesson shows its new
/// time, a cancelled one says Cancelled).
class ReceiptLesson {
  const ReceiptLesson({
    required this.lessonNumber,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.price,
  });

  final int? lessonNumber;
  final String date; // "2026-11-20"
  final String startTime; // "18:00"
  final String endTime;
  final String status;
  final String price; // "185.00"
}

/// A refund recorded for one of the receipt's lessons.
class ReceiptRefund {
  const ReceiptRefund({
    required this.amount,
    required this.percentage,
    required this.status,
  });

  final String amount;
  final int percentage;
  final String status; // Pending, Approved, Processed
}

/// GET /StudentlandingPage/booking-purchases/{id}/receipt: what was saved
/// when the student paid (backend lib/booking_receipt.dart).
class BookingReceipt {
  const BookingReceipt({
    required this.receiptNumber,
    required this.purchaseId,
    required this.paidAt,
    required this.purchaseStatus,
    required this.studentName,
    required this.studentEmail,
    required this.tutorName,
    required this.subject,
    required this.purchaseType,
    required this.lessonCount,
    required this.ratePerLesson,
    required this.subtotal,
    required this.discountPercent,
    required this.discountAmount,
    required this.total,
    required this.amountPaid,
    required this.paymentMethod,
    required this.paymentMode,
    required this.lessons,
    this.paymentReference,
    this.refunds = const [],
  });

  final String receiptNumber; // "TT-000016"
  final int purchaseId;
  final String paidAt; // "2026-11-16 21:32", South African time
  final String purchaseStatus;
  final String studentName;
  final String studentEmail;
  final String tutorName;
  final String subject;
  final String purchaseType; // Single or Package
  final int lessonCount;
  final String ratePerLesson;
  final String subtotal;
  final int discountPercent;
  final String discountAmount;
  final String total;
  final String amountPaid;
  final String paymentMethod; // "Credit/Debit card"
  final String paymentMode; // "Demo": no real money moved
  final String? paymentReference;
  final List<ReceiptLesson> lessons;
  final List<ReceiptRefund> refunds;

  bool get isDemo => paymentMode == 'Demo';

  factory BookingReceipt.fromJson(Map<String, dynamic> json) {
    String text(Object? v, [String fallback = '']) =>
        v is String && v.trim().isNotEmpty ? v.trim() : fallback;
    final number = json['receiptNumber'];
    final id = json['purchaseId'];
    if (number is! String || id is! int || json['paidAt'] is! String) {
      throw const FormatException('The receipt is incomplete.');
    }
    final student = json['student'] is Map<String, dynamic>
        ? json['student'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return BookingReceipt(
      receiptNumber: number,
      purchaseId: id,
      paidAt: json['paidAt'] as String,
      purchaseStatus: text(json['purchaseStatus'], 'Paid'),
      studentName: text(student['name'], 'Student'),
      studentEmail: text(student['email']),
      tutorName: text(json['tutorName'], 'Tutor'),
      subject: text(json['subject'], 'Tutoring session'),
      purchaseType: text(json['purchaseType'], 'Single'),
      lessonCount: json['lessonCount'] is int ? json['lessonCount'] as int : 1,
      ratePerLesson: text(json['ratePerLesson'], '0.00'),
      subtotal: text(json['subtotal'], '0.00'),
      discountPercent: json['discountPercent'] is int
          ? json['discountPercent'] as int
          : 0,
      discountAmount: text(json['discountAmount'], '0.00'),
      total: text(json['total'], '0.00'),
      amountPaid: text(json['amountPaid'], '0.00'),
      paymentMethod: text(json['paymentMethod'], 'Card'),
      paymentMode: text(json['paymentMode']),
      paymentReference: json['paymentReference'] is String
          ? json['paymentReference'] as String
          : null,
      lessons: [
        for (final l in json['lessons'] as List? ?? const [])
          if (l is Map<String, dynamic>)
            ReceiptLesson(
              lessonNumber: l['lessonNumber'] is int
                  ? l['lessonNumber'] as int
                  : null,
              date: text(l['date']),
              startTime: text(l['startTime']),
              endTime: text(l['endTime']),
              status: text(l['status']),
              price: text(l['price'], '0.00'),
            ),
      ],
      refunds: [
        for (final r in json['refunds'] as List? ?? const [])
          if (r is Map<String, dynamic>)
            ReceiptRefund(
              amount: text(r['amount'], '0.00'),
              percentage: r['percentage'] is int ? r['percentage'] as int : 0,
              status: text(r['status']),
            ),
      ],
    );
  }
}

class BookingReceiptException implements Exception {
  const BookingReceiptException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Loads the signed-in student's receipt for purchase [purchaseId].
Future<BookingReceipt> fetchBookingReceipt(
  int purchaseId, {
  http.Client? client,
  Future<String?> Function()? tokenProvider,
}) async {
  final token =
      await (tokenProvider ??
          () async => FirebaseAuth.instance.currentUser?.getIdToken())();
  if (token == null || token.isEmpty) {
    throw const BookingReceiptException('Please sign in again.');
  }
  final http.Response response;
  final c = client ?? http.Client();
  try {
    response = await c
        .get(
          Uri.parse(
            '$apiBaseUrl/StudentlandingPage/booking-purchases/'
            '$purchaseId/receipt',
          ),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    throw const BookingReceiptException(
      'Could not reach the server. Check your connection and try again.',
    );
  } finally {
    if (client == null) c.close();
  }
  Object? body;
  try {
    body = jsonDecode(response.body);
  } on FormatException {
    body = null;
  }
  if (response.statusCode != 200 || body is! Map<String, dynamic>) {
    throw BookingReceiptException(
      body is Map<String, dynamic> && body['error'] is String
          ? body['error'] as String
          : 'The receipt could not be loaded. Please try again.',
    );
  }
  try {
    return BookingReceipt.fromJson(body);
  } on FormatException {
    throw const BookingReceiptException('The receipt could not be loaded.');
  }
}
