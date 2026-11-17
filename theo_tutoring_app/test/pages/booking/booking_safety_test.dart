import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_api.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_confirmation.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_flow_context.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_payment_details.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_schedule.dart';
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
  Future<BookingAvailability> availability({
    required int tutorId,
    required int subjectId,
    required String from,
    required String through,
  }) async {
    if (failAvailability) {
      throw const BookingApiException('Availability unavailable');
    }
    return BookingAvailability(
      hourlyRate: '250.00',
      slots:
          slots ??
          [
            AvailableBookingSlot(
              date: _today(),
              startTime: '10:00',
              endTime: '11:00',
            ),
          ],
    );
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

const _heldPurchase = BookingPurchaseResult(
  purchaseId: 42,
  purchaseStatus: 'Held',
  totalAmount: '250.00',
  holdExpiresAt: '2026-10-20T10:10:00Z',
  lessons: [],
);

Future<void> _fillCard(
  WidgetTester tester, {
  String number = '4242424242424242',
  String expiry = '1299',
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Example Student');
  await tester.enterText(fields.at(1), number);
  await tester.enterText(fields.at(2), expiry);
  await tester.enterText(fields.at(3), '123');
  await tester.pump();
}

Future<void> _tapPay(WidgetTester tester) async {
  await tester.tap(find.text('Pay R250.00 Now'));
  await tester.pumpAndSettle();
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
      expect(find.text('10:00 AM'), findsOneWidget);
      await tester.ensureVisible(find.text('10:00 AM'));
      await tester.tap(find.text('10:00 AM'));
      await tester.pump();
      final submitButton = find.text('Send Booking Request');
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
      expect(api.submitted?.containsKey('note'), isFalse);
      expect(api.submittedKeys, hasLength(2));
      expect(api.submittedKeys.first, api.submittedKeys.last);
      expect(find.text('Lesson Details'), findsOneWidget);
      expect(find.text('Session (1 hour)'), findsOneWidget);
      await _fillCard(tester);
      await _tapPay(tester);
      expect(find.text('Booking Confirmed!'), findsOneWidget);
      expect(api.paymentRequests, hasLength(1));
      expect(api.paymentRequests.single.method, 'CreditDebitCard');
      expect(api.paymentRequests.single.outcome, 'success');
    },
  );

  testWidgets(
    'failed payment attempt retries with a new key and only confirms on success',
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
            purchase: _heldPurchase,
            api: api,
          ),
        ),
      );
      await _fillCard(tester);
      await _tapPay(tester);
      expect(find.textContaining('Payment failed.'), findsOneWidget);
      expect(find.text('Booking Confirmed!'), findsNothing);
      await _tapPay(tester);
      expect(api.paymentRequests, hasLength(2));
      expect(api.paymentRequests[0].key, isNot(api.paymentRequests[1].key));
      expect(find.text('Booking Confirmed!'), findsOneWidget);
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
            purchase: _heldPurchase,
            api: api,
          ),
        ),
      );
      await _fillCard(tester);
      await _tapPay(tester);
      expect(find.text('Temporary failure'), findsOneWidget);
      await _tapPay(tester);
      expect(api.paymentRequests, hasLength(2));
      expect(api.paymentRequests.first.key, api.paymentRequests.last.key);
      expect(find.text('Booking Confirmed!'), findsOneWidget);
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
          purchase: _heldPurchase,
          api: api,
        ),
      ),
    );
    await _fillCard(tester);
    await _tapPay(tester);
    expect(find.text('One or more lesson holds have expired.'), findsOneWidget);
    expect(
      find.textContaining('This reservation can no longer be paid.'),
      findsOneWidget,
    );
    expect(find.text('Booking Confirmed!'), findsNothing);
  });

  testWidgets('invalid card details never reach the payment API', (
    tester,
  ) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: BookingPaymentDetailsPage(
          flow: _flow(),
          purchase: _heldPurchase,
          api: api,
        ),
      ),
    );
    await _tapPay(tester);
    expect(find.text('Enter the name on the card.'), findsOneWidget);
    await _fillCard(tester, number: '4242424242424241', expiry: '0120');
    await _tapPay(tester);
    expect(find.text('Enter a valid card number.'), findsOneWidget);
    expect(find.text('This card has expired.'), findsOneWidget);
    expect(api.paymentRequests, isEmpty);
    expect(find.text('4242 4242 4242 4241'), findsOneWidget);
    expect(find.text('01/20'), findsOneWidget);
  });

  testWidgets('order summary shows the package discount from the purchase', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookingPaymentDetailsPage(
          flow: _flow(),
          purchase: const BookingPurchaseResult(
            purchaseId: 43,
            purchaseStatus: 'Held',
            totalAmount: '675.00',
            subtotal: '750.00',
            discountPercent: 10,
            discountAmount: '75.00',
            holdExpiresAt: '2026-10-20T10:10:00Z',
            lessons: [
              {'date': '2026-10-20', 'startTime': '10:00', 'endTime': '11:00'},
              {'date': '2026-10-21', 'startTime': '10:00', 'endTime': '11:00'},
              {'date': '2026-10-22', 'startTime': '10:00', 'endTime': '11:00'},
            ],
          ),
          api: _FakeApi(),
        ),
      ),
    );
    expect(find.text('Sessions (3 × 1 hour)'), findsOneWidget);
    expect(find.text('R750.00'), findsOneWidget);
    expect(find.text('Package discount (10%)'), findsOneWidget);
    expect(find.text('−R75.00'), findsOneWidget);
    expect(find.text('R675.00'), findsOneWidget);
    expect(find.text('Pay R675.00 Now'), findsOneWidget);
  });

  testWidgets(
    'calendar only lets the student pick dates the tutor is available',
    (tester) async {
      // Dates in next month, so they are always ahead and on one calendar page.
      final now = DateTime.now();
      final first = DateTime(now.year, now.month + 1, 2);
      final unavailable = DateTime(now.year, now.month + 1, 3);
      final second = DateTime(now.year, now.month + 1, 5);
      String key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
      final api = _FakeApi(
        slots: [
          AvailableBookingSlot(
            date: key(first),
            startTime: '09:00',
            endTime: '10:00',
          ),
          AvailableBookingSlot(
            date: key(first),
            startTime: '13:00',
            endTime: '14:00',
          ),
          AvailableBookingSlot(
            date: key(second),
            startTime: '15:00',
            endTime: '16:00',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BookingSchedulePage(flow: _flow(), api: api),
        ),
      );
      await tester.pumpAndSettle();

      // Opens on the first available date and shows its times.
      expect(find.text(DateFormat('MMMM y').format(first)), findsOneWidget);
      expect(
        find.text('Available Times on ${DateFormat('MMM d').format(first)}'),
        findsOneWidget,
      );
      expect(find.text('09:00 AM'), findsOneWidget);
      expect(find.text('01:00 PM'), findsOneWidget);
      expect(find.text('03:00 PM'), findsNothing);
      expect(find.text('1 Hour Session'), findsOneWidget);
      expect(find.text('R250.00'), findsOneWidget);

      InkWell day(DateTime d) =>
          tester.widget<InkWell>(find.byKey(ValueKey('day-${key(d)}')));
      expect(day(first).onTap, isNotNull);
      expect(day(second).onTap, isNotNull);
      expect(day(unavailable).onTap, isNull);

      await tester.ensureVisible(find.byKey(ValueKey('day-${key(second)}')));
      await tester.tap(find.byKey(ValueKey('day-${key(second)}')));
      await tester.pumpAndSettle();
      expect(find.text('09:00 AM'), findsNothing);
      await tester.ensureVisible(find.text('03:00 PM'));
      await tester.tap(find.text('03:00 PM'));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const ValueKey('booking-note')));
      await tester.enterText(
        find.byKey(const ValueKey('booking-note')),
        '  Focus on proofs  ',
      );
      await tester.tap(find.text('Send Booking Request'));
      await tester.pumpAndSettle();

      expect(api.submitted?['note'], 'Focus on proofs');
      expect(api.submitted?['lessons'], [
        {'date': key(second), 'startTime': '15:00', 'endTime': '16:00'},
      ]);
      expect(find.text('Lesson Details'), findsOneWidget);
    },
  );

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
      find.text('No available times in the next 90 days.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send Booking Request'),
          )
          .onPressed,
      isNull,
    );
    // A new key gives a fresh navigator (the schedule page has no back arrow).
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
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
