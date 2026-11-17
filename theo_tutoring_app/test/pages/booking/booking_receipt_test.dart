import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_api.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_confirmation.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_flow_context.dart';
import 'package:theo_tutoring_app/models/tutor.dart';
import 'package:theo_tutoring_app/services/booking_receipt.dart';
import 'package:theo_tutoring_app/services/receipt_pdf.dart';

// Download Receipt after a successful payment: the receipt comes from the
// server (GET /StudentlandingPage/booking-purchases/{id}/receipt) and is
// turned into a PDF. The server and the share sheet are fakes.

/// The shape the backend returns (lib/booking_receipt.dart).
Map<String, dynamic> _receiptJson({
  int discountPercent = 0,
  List<Map<String, Object?>> refunds = const [],
}) => {
  'receiptNumber': 'TT-000016',
  'purchaseId': 16,
  'paymentAttemptId': 12,
  'paidAt': '2026-11-16 21:32',
  'purchaseStatus': 'Paid',
  'student': {'name': 'Lerato Dube', 'email': 'lerato@example.com'},
  'tutorName': 'Mariam Sprouse',
  'subject': 'Accounting',
  'purchaseType': discountPercent > 0 ? 'Package' : 'Single',
  'lessonCount': discountPercent > 0 ? 10 : 1,
  'ratePerLesson': '185.00',
  'subtotal': discountPercent > 0 ? '1850.00' : '185.00',
  'discountPercent': discountPercent,
  'discountAmount': discountPercent > 0 ? '185.00' : '0.00',
  'total': discountPercent > 0 ? '1665.00' : '185.00',
  'amountPaid': discountPercent > 0 ? '1665.00' : '185.00',
  'currency': 'ZAR',
  'paymentMethod': 'Credit/Debit card',
  'paymentMode': 'Demo',
  'paymentReference': null,
  'lessons': [
    {
      'bookingId': 17,
      'lessonNumber': 1,
      'date': '2026-11-20',
      'startTime': '18:00',
      'endTime': '19:00',
      'status': 'Confirmed',
      'price': '185.00',
    },
  ],
  'refunds': refunds,
};

BookingFlowContext _flow() {
  const subject = TutorSubject(subjectId: 4, subjectName: 'Accounting');
  const tutor = Tutor(
    tutorId: 12,
    name: 'Mariam Sprouse',
    profilePhoto: null,
    bio: null,
    experience: null,
    subjects: [subject],
    hourlyRate: null,
    averageRating: null,
    reviewCount: 0,
  );
  return BookingFlowContext(tutor: tutor, subject: subject);
}

const _paid = BookingPurchaseResult(
  purchaseId: 16,
  purchaseStatus: 'Paid',
  totalAmount: '185.00',
  holdExpiresAt: '2026-11-16T19:47:52Z',
  lessons: [
    {'date': '2026-11-20', 'startTime': '18:00', 'endTime': '19:00'},
  ],
);

const _success = PaymentAttemptResult(
  paymentAttemptId: 12,
  attemptNumber: 1,
  paymentStatus: 'Successful',
  purchaseStatus: 'Paid',
  replayed: false,
  settled: true,
);

bool _isPdf(Uint8List bytes) =>
    bytes.length > 4 && ascii.decode(bytes.sublist(0, 4)) == '%PDF';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('BookingReceipt', () {
    test('reads the backend receipt', () {
      final r = BookingReceipt.fromJson(_receiptJson());
      expect(r.receiptNumber, 'TT-000016');
      expect(r.purchaseId, 16);
      expect(r.paidAt, '2026-11-16 21:32');
      expect(r.studentName, 'Lerato Dube');
      expect(r.tutorName, 'Mariam Sprouse');
      expect(r.subject, 'Accounting');
      expect(r.total, '185.00');
      expect(r.amountPaid, '185.00');
      expect(r.paymentMethod, 'Credit/Debit card');
      expect(r.isDemo, isTrue);
      expect(r.lessons.single.date, '2026-11-20');
      expect(r.lessons.single.startTime, '18:00');
    });

    test('fetch sends the token to the receipt route', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode(_receiptJson()), 200);
      });
      final r = await fetchBookingReceipt(
        16,
        client: client,
        tokenProvider: () async => 'tok',
      );
      expect(sent.url.path, '/StudentlandingPage/booking-purchases/16/receipt');
      expect(sent.headers['Authorization'], 'Bearer tok');
      expect(r.receiptNumber, 'TT-000016');
    });

    test('a refused receipt shows the server message', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'This booking has not been paid, so there is no receipt '
                'yet.',
          }),
          409,
        ),
      );
      await expectLater(
        fetchBookingReceipt(16, client: client, tokenProvider: () async => 't'),
        throwsA(
          isA<BookingReceiptException>().having(
            (e) => e.message,
            'message',
            contains('has not been paid'),
          ),
        ),
      );
    });
  });

  group('receipt PDF', () {
    test('builds a PDF for a single lesson', () async {
      final bytes = await buildReceiptPdf(
        BookingReceipt.fromJson(_receiptJson()),
      );
      expect(_isPdf(bytes), isTrue);
    });

    test('builds a PDF with a package discount and a refund', () async {
      final bytes = await buildReceiptPdf(
        BookingReceipt.fromJson(
          _receiptJson(
            discountPercent: 10,
            refunds: [
              {'bookingId': 17, 'amount': '166.50', 'percentage': 100,
                'status': 'Approved'},
            ],
          ),
        ),
      );
      expect(_isPdf(bytes), isTrue);
    });

    test('names the file after the receipt number', () {
      expect(
        receiptFileName(BookingReceipt.fromJson(_receiptJson())),
        'TheoTutoring-receipt-TT-000016.pdf',
      );
      expect(receiptDateTime('2026-11-16 21:32'), '16 Nov 2026, 21:32');
    });
  });

  group('confirmation page', () {
    setUp(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(800, 1600);
      view.devicePixelRatio = 1;
    });
    tearDown(
      () => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
          .resetPhysicalSize(),
    );

    testWidgets('a paid booking says it is confirmed and paid', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BookingConfirmationPage(
            flow: _flow(),
            result: _paid,
            payment: _success,
          ),
        ),
      );
      expect(find.text('Booking Confirmed!'), findsOneWidget);
      expect(find.text('Total Paid'), findsOneWidget);
      expect(find.text('Total Due'), findsNothing);
      expect(find.text('Download Receipt'), findsOneWidget);
    });

    testWidgets('Download Receipt saves the PDF for that purchase', (
      tester,
    ) async {
      final loaded = <int>[];
      Uint8List? saved;
      String? name;
      await tester.pumpWidget(
        MaterialApp(
          home: BookingConfirmationPage(
            flow: _flow(),
            result: _paid,
            payment: _success,
            loadReceipt: (id) async {
              loaded.add(id);
              return BookingReceipt.fromJson(_receiptJson());
            },
            saveReceipt: (bytes, fileName) async {
              saved = bytes;
              name = fileName;
            },
          ),
        ),
      );
      final button = find.text('Download Receipt');
      await tester.ensureVisible(button);
      // The PDF is built outside the widget clock
      await tester.runAsync(() async {
        await tester.tap(button);
        for (var i = 0; i < 50 && saved == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await tester.pump();

      expect(loaded, [16]);
      expect(saved, isNotNull);
      expect(_isPdf(saved!), isTrue);
      expect(name, 'TheoTutoring-receipt-TT-000016.pdf');
    });

    testWidgets('a receipt that cannot load shows why', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BookingConfirmationPage(
            flow: _flow(),
            result: _paid,
            payment: _success,
            loadReceipt: (_) async => throw const BookingReceiptException(
              'Could not reach the server. Check your connection and try '
              'again.',
            ),
            saveReceipt: (_, _) async => fail('nothing should be saved'),
          ),
        ),
      );
      final button = find.text('Download Receipt');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
    });
  });
}
