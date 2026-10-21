import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_api.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_confirmation.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_flow_context.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_payment_details.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_select_lesson.dart';
import 'package:theo_tutoring_app/models/tutor.dart';

BookingFlowContext _flow() {
  const subject = TutorSubject(subjectId: 4, subjectName: 'Mathematics');
  const tutor = Tutor(
    tutorId: 12,
    name: 'Example Tutor',
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

class _FakeApi implements BookingFlowApi {
  _FakeApi({
    this.failAvailability = false,
    this.failFirstPurchase = false,
    this.failFirstPaymentRequest = false,
    this.slots,
  });
  final bool failAvailability;
  final bool failFirstPurchase;
  final bool failFirstPaymentRequest;
  final List<AvailableBookingSlot>? slots;
  Map<String, Object>? submitted;
  final List<String> submittedKeys = [];
  final List<({String key, String method, String outcome})> paymentRequests =
      [];
  List<PaymentAttemptResult> paymentResponses = [];
  BookingApiException? paymentError;

  @override
  Future<List<AvailableBookingSlot>> availability({
    required int tutorId,
    required int subjectId,
    required String from,
    required String through,
  }) async {
    if (failAvailability) {
      throw const BookingApiException('Availability unavailable');
    }
    return slots ??
        [
          AvailableBookingSlot(
            date: _today(),
            startTime: '10:00',
            endTime: '11:00',
          ),
        ];
  }

  @override
  Future<BookingPurchaseResult> createPurchase(
    Map<String, Object> request,
  ) async {
    submitted = request;
    submittedKeys.add(request['idempotencyKey']! as String);
    if (failFirstPurchase && submittedKeys.length == 1) {
      throw const BookingApiException('Temporary failure');
    }
    return const BookingPurchaseResult(
      purchaseId: 42,
      purchaseStatus: 'Held',
      totalAmount: '250.00',
      holdExpiresAt: '2026-10-20T10:10:00Z',
      lessons: [
        {
          'date': '2026-10-20',
          'startTime': '10:00',
          'endTime': '11:00',
          'holdStatus': 'Active',
        },
      ],
    );
  }

  @override
  Future<PaymentAttemptResult> createPaymentAttempt({
    required int purchaseId,
    required String idempotencyKey,
    required String paymentMethod,
    required String simulatedOutcome,
  }) async {
    paymentRequests.add((
      key: idempotencyKey,
      method: paymentMethod,
      outcome: simulatedOutcome,
    ));
    if (failFirstPaymentRequest && paymentRequests.length == 1) {
      throw const BookingApiException('Temporary failure');
    }
    final error = paymentError;
    if (error != null) throw error;
    final index = paymentRequests.length - 1;
    if (index < paymentResponses.length) return paymentResponses[index];
    return const PaymentAttemptResult(
      paymentAttemptId: 51,
      attemptNumber: 1,
      paymentStatus: 'Successful',
      purchaseStatus: 'Paid',
      replayed: false,
      settled: true,
    );
  }

  @override
  void close() {}
}

String _today() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets('lesson choice continues to available slot selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BookingSelectLessonPage(flow: _flow())),
    );
    expect(find.text('Single lesson'), findsOneWidget);
    expect(find.text('Package'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Choose available times'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'loads a slot, submits idempotent manual request, and reports held status only',
    (tester) async {
      final api = _FakeApi(failFirstPurchase: true);
      await tester.pumpWidget(
        MaterialApp(
          home: BookingSelectLessonPage(flow: _flow(), api: api),
        ),
      );
      await tester.tap(find.text('Choose available times'));
      await tester.pumpAndSettle();
      expect(find.text('10:00–11:00'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      final submitButton = find.text('Submit booking request');
      await tester.ensureVisible(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      expect(find.text('Temporary failure'), findsOneWidget);
      await tester.ensureVisible(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      expect(api.submitted?['purchaseType'], 'Single');
      expect(api.submitted?['schedulingMode'], 'manual');
      expect(api.submitted?['tutorId'], 12);
      expect(api.submitted?['subjectId'], 4);
      expect(api.submitted?['idempotencyKey'], startsWith('booking-'));
      expect(api.submittedKeys, hasLength(2));
      expect(api.submittedKeys.first, api.submittedKeys.last);
      expect(find.textContaining('DEMO PAYMENT ONLY'), findsOneWidget);
      expect(find.text('Credit / debit card'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue to demo payment'));
      await tester.tap(find.text('Continue to demo payment'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Simulate successful payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simulate successful payment'));
      await tester.ensureVisible(find.text('Submit demo payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit demo payment'));
      await tester.pumpAndSettle();
      expect(find.text('Booking #42 · Paid'), findsOneWidget);
      expect(find.text('Your lessons are confirmed.'), findsOneWidget);
      expect(api.paymentRequests, hasLength(1));
      expect(api.paymentRequests.single.method, 'CreditDebitCard');
      expect(api.paymentRequests.single.outcome, 'success');
    },
  );

  testWidgets(
    'failed demo attempt retries with a new key and only confirms on success',
    (tester) async {
      final api = _FakeApi()
        ..paymentResponses = const [
          PaymentAttemptResult(
            paymentAttemptId: 51,
            attemptNumber: 1,
            paymentStatus: 'Failed',
            purchaseStatus: 'Held',
            replayed: false,
            settled: false,
          ),
          PaymentAttemptResult(
            paymentAttemptId: 52,
            attemptNumber: 2,
            paymentStatus: 'Successful',
            purchaseStatus: 'Paid',
            replayed: false,
            settled: true,
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: BookingPaymentDetailsPage(
            flow: _flow(),
            purchase: const BookingPurchaseResult(
              purchaseId: 42,
              purchaseStatus: 'Held',
              totalAmount: '250.00',
              holdExpiresAt: '2026-10-20T10:10:00Z',
              lessons: [],
            ),
            api: api,
            paymentMethod: 'PayPal',
          ),
        ),
      );
      await tester.ensureVisible(find.text('Simulate successful payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simulate successful payment'));
      await tester.ensureVisible(find.text('Submit demo payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit demo payment'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Demo payment failed.'), findsOneWidget);
      expect(find.text('Your lessons are confirmed.'), findsNothing);
      await tester.ensureVisible(find.text('Retry demo payment'));
      await tester.tap(find.text('Retry demo payment'));
      await tester.pumpAndSettle();
      expect(api.paymentRequests, hasLength(2));
      expect(api.paymentRequests[0].key, isNot(api.paymentRequests[1].key));
      expect(find.text('Your lessons are confirmed.'), findsOneWidget);
    },
  );

  testWidgets(
    'uncertain payment request retries with the same idempotency key',
    (tester) async {
      final api = _FakeApi(failFirstPaymentRequest: true);
      await tester.pumpWidget(
        MaterialApp(
          home: BookingPaymentDetailsPage(
            flow: _flow(),
            purchase: const BookingPurchaseResult(
              purchaseId: 42,
              purchaseStatus: 'Held',
              totalAmount: '250.00',
              holdExpiresAt: '2026-10-20T10:10:00Z',
              lessons: [],
            ),
            api: api,
            paymentMethod: 'EFT',
          ),
        ),
      );
      await tester.ensureVisible(find.text('Simulate successful payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simulate successful payment'));
      await tester.ensureVisible(find.text('Submit demo payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit demo payment'));
      await tester.pumpAndSettle();
      expect(find.text('Temporary failure'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry payment request'));
      await tester.tap(find.text('Retry payment request'));
      await tester.pumpAndSettle();
      expect(api.paymentRequests, hasLength(2));
      expect(api.paymentRequests.first.key, api.paymentRequests.last.key);
      expect(find.text('Your lessons are confirmed.'), findsOneWidget);
    },
  );

  testWidgets('expired hold error prevents payment retry or confirmation', (
    tester,
  ) async {
    final api = _FakeApi()
      ..paymentError = const BookingApiException(
        'One or more lesson holds have expired.',
        statusCode: 409,
        code: 'hold_expired',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: BookingPaymentDetailsPage(
          flow: _flow(),
          purchase: const BookingPurchaseResult(
            purchaseId: 42,
            purchaseStatus: 'Held',
            totalAmount: '250.00',
            holdExpiresAt: '2026-10-20T10:10:00Z',
            lessons: [],
          ),
          api: api,
          paymentMethod: 'EFT',
        ),
      ),
    );
    await tester.ensureVisible(find.text('Simulate successful payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simulate successful payment'));
    await tester.ensureVisible(find.text('Submit demo payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit demo payment'));
    await tester.pumpAndSettle();
    expect(find.text('One or more lesson holds have expired.'), findsOneWidget);
    expect(
      find.text('This reservation can no longer be paid.'),
      findsOneWidget,
    );
    expect(find.text('Your lessons are confirmed.'), findsNothing);
  });

  testWidgets('shows empty and availability error states', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookingSelectLessonPage(
          flow: _flow(),
          api: _FakeApi(slots: []),
        ),
      ),
    );
    await tester.tap(find.text('Choose available times'));
    await tester.pumpAndSettle();
    expect(
      find.text('No available times on this date. Choose another date.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: BookingSelectLessonPage(
          flow: _flow(),
          api: _FakeApi(failAvailability: true),
        ),
      ),
    );
    await tester.tap(find.text('Choose available times'));
    await tester.pumpAndSettle();
    expect(find.text('Availability unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'confirmation without a result never claims submission or confirmation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: BookingConfirmationPage(flow: _flow())),
      );
      expect(find.text('No booking has been submitted.'), findsOneWidget);
      expect(find.textContaining('Lessons are not confirmed.'), findsOneWidget);
    },
  );
}
