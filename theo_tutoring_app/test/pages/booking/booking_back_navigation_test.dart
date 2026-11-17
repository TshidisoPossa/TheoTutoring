import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_api.dart';
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

/// Records every reservation and release, like the server would see them.
class _FakeApi implements BookingFlowApi, BookingReleaseApi {
  _FakeApi(this.slots);
  final List<AvailableBookingSlot> slots;
  final List<Map<String, Object>> purchases = [];
  final List<int> released = [];
  BookingApiException? releaseError;

  @override
  Future<BookingAvailability> availability({
    required int tutorId,
    required int subjectId,
    required String from,
    required String through,
  }) async => BookingAvailability(hourlyRate: '250.00', slots: slots);

  @override
  Future<BookingPurchaseResult> createPurchase(
    Map<String, Object> request,
  ) async {
    purchases.add(request);
    return BookingPurchaseResult(
      purchaseId: 40 + purchases.length,
      purchaseStatus: 'Held',
      totalAmount: '750.00',
      holdExpiresAt: '2026-10-20T10:10:00Z',
      lessons: [
        for (final l in request['lessons']! as List)
          {...(l as Map<String, Object>), 'holdStatus': 'Active'},
      ],
    );
  }

  @override
  Future<String> releasePurchase(int purchaseId) async {
    released.add(purchaseId);
    if (releaseError != null) throw releaseError!;
    return 'Cancelled';
  }

  @override
  Future<PaymentAttemptResult> createPaymentAttempt({
    required int purchaseId,
    required String idempotencyKey,
    required String paymentMethod,
    required String simulatedOutcome,
  }) => throw UnimplementedError();

  @override
  void close() {}
}

String _key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

// Three weekdays early in next month, always ahead and on one calendar page
final DateTime _mon = () {
  final now = DateTime.now();
  var d = DateTime(now.year, now.month + 1, 1);
  while (d.weekday != DateTime.monday) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}();
final DateTime _tue = DateTime(_mon.year, _mon.month, _mon.day + 1);
final DateTime _wed = DateTime(_mon.year, _mon.month, _mon.day + 2);

List<AvailableBookingSlot> _slots() => [
  for (final d in [_mon, _tue, _wed]) ...[
    AvailableBookingSlot(date: _key(d), startTime: '09:00', endTime: '10:00'),
    AvailableBookingSlot(date: _key(d), startTime: '14:00', endTime: '15:00'),
  ],
];

Future<_FakeApi> _openSelect(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _FakeApi(_slots());
  await tester.pumpWidget(
    MaterialApp(
      home: BookingSelectLessonPage(flow: _flow(), api: api),
    ),
  );
  return api;
}

Future<void> _choosePackage(WidgetTester tester, int lessons) async {
  await tester.tap(find.text('Package'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('lesson-count')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('$lessons lessons').last);
  await tester.pumpAndSettle();
}

Future<void> _toSchedule(WidgetTester tester) async {
  await tester.tap(find.text('Choose available times'));
  await tester.pumpAndSettle();
  expect(find.byType(BookingSchedulePage), findsOneWidget);
}

Future<void> _openDay(WidgetTester tester, DateTime day) async {
  final cell = find.byKey(ValueKey('day-${_key(day)}'));
  await tester.ensureVisible(cell);
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

Future<void> _tapTime(WidgetTester tester, String label) async {
  final chip = find.descendant(
    of: find.byType(InkWell),
    matching: find.text(label),
  );
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Mon, Tue and Wed at 09:00, skipping the weekly offer.
Future<void> _pickThree(WidgetTester tester) async {
  await _openDay(tester, _mon);
  await _tapTime(tester, '09:00 AM');
  await tester.tap(find.text('Schedule manually'));
  await tester.pumpAndSettle();
  for (final d in [_tue, _wed]) {
    await _openDay(tester, d);
    await _tapTime(tester, '09:00 AM');
  }
}

Set<String> _lessonRows() => {
  for (final e in find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('lesson-');
  }).evaluate())
    ((e.widget.key! as ValueKey<String>).value.substring(7)),
};

Set<String> _at9(List<DateTime> days) => {
  for (final d in days) '${_key(d)}|09:00',
};

Future<void> _proceed(WidgetTester tester) async {
  final button = find.text('Proceed to payment');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(BookingPaymentDetailsPage), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('date selection has a back arrow to the lesson choice, which '
      'keeps the package', (tester) async {
    final api = await _openSelect(tester);
    await _choosePackage(tester, 3);
    await _toSchedule(tester);

    final arrow = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.arrow_back_rounded),
    );
    expect(arrow, findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    // Still the same header: title and profile photo
    expect(find.text('Lessons'), findsWidgets);
    expect(find.byTooltip('Profile'), findsOneWidget);

    await _back(tester);
    expect(find.byType(BookingSchedulePage), findsNothing);
    expect(find.byType(BookingSelectLessonPage), findsOneWidget);
    // The package choice is as it was: not a restart
    expect(find.text('3 lessons'), findsOneWidget);
    expect(api.purchases, isEmpty);
  });

  testWidgets('the chosen times come back after visiting the lesson choice', (
    tester,
  ) async {
    final api = await _openSelect(tester);
    await _choosePackage(tester, 3);
    await _toSchedule(tester);
    await _pickThree(tester);
    expect(_lessonRows(), _at9([_mon, _tue, _wed]));

    await _back(tester);
    await _toSchedule(tester);
    expect(_lessonRows(), _at9([_mon, _tue, _wed]));
    expect(find.text('3 of 3 lessons selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-notice')), findsNothing);
    expect(find.text('Repeat weekly?'), findsNothing);
    expect(api.purchases, isEmpty);

    // They can still be edited and then proceed
    await tester.tap(find.byTooltip('Change lesson 2'));
    await tester.pumpAndSettle();
    await _tapTime(tester, '02:00 PM'); // Tuesday 14:00
    await _proceed(tester);
    expect(api.purchases, hasLength(1));
    expect(api.purchases.single['lessons'], [
      {'date': _key(_mon), 'startTime': '09:00', 'endTime': '10:00'},
      {'date': _key(_tue), 'startTime': '14:00', 'endTime': '15:00'},
      {'date': _key(_wed), 'startTime': '09:00', 'endTime': '10:00'},
    ]);
  });

  testWidgets('a smaller package keeps the earliest times and says so', (
    tester,
  ) async {
    await _openSelect(tester);
    await _choosePackage(tester, 3);
    await _toSchedule(tester);
    await _pickThree(tester);

    await _back(tester);
    await _choosePackage(tester, 2);
    await _toSchedule(tester);
    expect(_lessonRows(), _at9([_mon, _tue]));
    expect(find.text('2 of 2 lessons selected'), findsOneWidget);
    expect(
      find.text('You now have 2 lessons, so only your first 2 times were kept.'),
      findsOneWidget,
    );

    // A single lesson keeps only the first
    await _back(tester);
    await tester.tap(find.text('Single lesson'));
    await tester.pumpAndSettle();
    await _toSchedule(tester);
    expect(
      find.text('You now have 1 lesson, so only your first 1 time was kept.'),
      findsOneWidget,
    );
    final chip = tester.widget<Material>(
      find
          .ancestor(of: find.text('09:00 AM'), matching: find.byType(Material))
          .first,
    );
    expect(chip.color, const Color(0xFF356AE6)); // Monday 09:00 still chosen
  });

  testWidgets('payment\'s back arrow returns to the held times without a new '
      'reservation', (tester) async {
    final api = await _openSelect(tester);
    await _choosePackage(tester, 3);
    await _toSchedule(tester);
    await _pickThree(tester);
    await _proceed(tester);

    // The payment page's existing arrow
    expect(find.byTooltip('Back'), findsOneWidget);
    await _back(tester);
    expect(find.byType(BookingPaymentDetailsPage), findsNothing);
    expect(find.byType(BookingSchedulePage), findsOneWidget);
    expect(_lessonRows(), _at9([_mon, _tue, _wed]));
    expect(find.text('Continue to Payment'), findsOneWidget);
    expect(find.text('Change lessons'), findsOneWidget);

    // Held times stay locked until released
    final remove = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.close_rounded).first,
    );
    expect(remove.onPressed, isNull);

    // Forward again reuses the same reservation
    await tester.tap(find.text('Continue to Payment'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingPaymentDetailsPage), findsOneWidget);
    expect(api.purchases, hasLength(1));
    expect(api.released, isEmpty);
  });

  testWidgets('Change lessons releases the reservation once, then a changed '
      'set is reserved anew', (tester) async {
    final api = await _openSelect(tester);
    await _choosePackage(tester, 3);
    await _toSchedule(tester);
    await _pickThree(tester);
    await _proceed(tester);
    await _back(tester);

    await tester.tap(find.text('Change lessons'));
    await tester.pumpAndSettle();
    expect(api.released, [41]);
    expect(
      find.text(
        'Your reserved times were released. You can change your lessons now.',
      ),
      findsOneWidget,
    );
    expect(find.text('Change lessons'), findsNothing);
    expect(find.text('Proceed to payment'), findsOneWidget);
    expect(_lessonRows(), _at9([_mon, _tue, _wed])); // nothing discarded

    // Change Wednesday to 14:00 and go to payment again
    await tester.tap(find.byTooltip('Change lesson 3'));
    await tester.pumpAndSettle();
    await _tapTime(tester, '02:00 PM');
    await _proceed(tester);
    expect(api.purchases, hasLength(2));
    expect(
      api.purchases[1]['idempotencyKey'],
      isNot(api.purchases[0]['idempotencyKey']),
    );
    expect(
      (api.purchases[1]['lessons']! as List).last,
      {'date': _key(_wed), 'startTime': '14:00', 'endTime': '15:00'},
    );
    expect(api.released, [41]); // no second release
  });

  testWidgets('a failed release keeps the times reserved and locked', (
    tester,
  ) async {
    final api = await _openSelect(tester);
    await _choosePackage(tester, 3);
    await _toSchedule(tester);
    await _pickThree(tester);
    await _proceed(tester);
    await _back(tester);

    api.releaseError = const BookingApiException(
      'This reservation has been paid or is being paid, so it cannot be '
      'changed here.',
      statusCode: 409,
      code: 'purchase_not_releasable',
    );
    await tester.tap(find.text('Change lessons'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be changed here'), findsOneWidget);
    expect(find.text('Continue to Payment'), findsOneWidget);
    expect(find.text('Change lessons'), findsOneWidget);
    expect(api.purchases, hasLength(1));
  });

  testWidgets('going back to the lesson choice with held times asks first, '
      'then releases them', (tester) async {
    final api = await _openSelect(tester);
    await _choosePackage(tester, 3);
    await _toSchedule(tester);
    await _pickThree(tester);
    await _proceed(tester);
    await _back(tester); // payment → dates

    // Stay: nothing changes
    await _back(tester);
    expect(find.text('Release your reserved times?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingSchedulePage), findsOneWidget);
    expect(api.released, isEmpty);

    // The system back gesture asks too
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Release your reserved times?'), findsOneWidget);
    await tester.tap(find.text('Release and go back'));
    await tester.pumpAndSettle();
    expect(api.released, [41]);
    expect(find.byType(BookingSelectLessonPage), findsOneWidget);
    expect(find.byType(BookingSchedulePage), findsNothing);

    // The times are still chosen on return, ready to reserve again
    await _toSchedule(tester);
    expect(_lessonRows(), _at9([_mon, _tue, _wed]));
    await _proceed(tester);
    expect(api.purchases, hasLength(2));
  });
}
