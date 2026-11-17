import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_api.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_flow_context.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_payment_details.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_schedule.dart';
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
  _FakeApi(this.slots);
  final List<AvailableBookingSlot> slots;
  Map<String, Object>? submitted;

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
    submitted = request;
    return BookingPurchaseResult(
      purchaseId: 42,
      purchaseStatus: 'Held',
      totalAmount: '1250.00',
      holdExpiresAt: '2026-10-20T10:10:00Z',
      lessons: [
        for (final l in request['lessons']! as List)
          {...(l as Map<String, Object>), 'holdStatus': 'Active'},
      ],
    );
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

// The first Tuesday of next month, always ahead of now.
final DateTime _tue = () {
  final now = DateTime.now();
  var d = DateTime(now.year, now.month + 1, 1);
  while (d.weekday != DateTime.tuesday) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}();
DateTime _week(int n) => DateTime(_tue.year, _tue.month, _tue.day + 7 * n);
final DateTime _wed = DateTime(_tue.year, _tue.month, _tue.day + 1);

AvailableBookingSlot _slot(DateTime d, String start, String end) =>
    AvailableBookingSlot(date: _key(d), startTime: start, endTime: end);

// Tuesdays at 09:00 for five weeks, except week 2 (only 11:00 is free),
// plus a Wednesday 10:00 for choosing by hand.
List<AvailableBookingSlot> _slots() => [
  _slot(_tue, '09:00', '10:00'),
  _slot(_wed, '10:00', '11:00'),
  _slot(_week(1), '09:00', '10:00'),
  _slot(_week(2), '11:00', '12:00'),
  _slot(_week(3), '09:00', '10:00'),
  _slot(_week(4), '09:00', '10:00'),
];

Future<_FakeApi> _open(
  WidgetTester tester, {
  int lessons = 5,
  List<AvailableBookingSlot>? slots,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _FakeApi(slots ?? _slots());
  await tester.pumpWidget(
    MaterialApp(
      home: BookingSchedulePage(
        flow: _flow(),
        purchaseType: lessons == 1 ? 'Single' : 'Package',
        lessonCount: lessons,
        api: api,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
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

Future<void> _openDay(WidgetTester tester, DateTime day) async {
  final cell = find.byKey(ValueKey('day-${_key(day)}'));
  // Steps towards the day's month, whichever side of the shown one it is
  for (var i = 0; i < 4 && cell.evaluate().isEmpty; i++) {
    final shown = DateFormat('MMMM y').parse(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((s) => RegExp(r'^[A-Z][a-z]+ \d{4}$').hasMatch(s)),
    );
    final forward = DateTime(day.year, day.month).isAfter(shown);
    await tester.tap(find.byTooltip(forward ? 'Next month' : 'Previous month'));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(cell);
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

Future<void> _setWeeks(WidgetTester tester, int weeks) async {
  for (var i = 0; i < weeks; i++) {
    await tester.tap(find.byTooltip('More weekly lessons'));
    await tester.pump();
  }
}

Set<String> _lessonRows() => {
  for (final e in find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('lesson-');
  }).evaluate())
    ((e.widget.key! as ValueKey<String>).value.substring(7)),
};

FilledButton _proceed(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Proceed to payment'),
);

void main() {
  testWidgets('a single lesson is never offered weekly repeats', (
    tester,
  ) async {
    await _open(tester, lessons: 1);
    await _tapTime(tester, '09:00 AM');
    expect(find.text('Repeat weekly?'), findsNothing);
    expect(_proceed(tester).onPressed, isNotNull);
  });

  testWidgets('the offer appears after the first lesson, capped at the '
      'lessons left', (tester) async {
    await _open(tester);
    expect(find.text('Repeat weekly?'), findsNothing);
    await _tapTime(tester, '09:00 AM');

    expect(find.text('Repeat weekly?'), findsOneWidget);
    expect(find.textContaining('You have 4 lessons left'), findsOneWidget);
    expect(find.textContaining('Tuesdays at 09:00 AM'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('weekly-count'))).data,
        '0');
    await _setWeeks(tester, 6); // taps past the limit are ignored
    expect(tester.widget<Text>(find.byKey(const ValueKey('weekly-count'))).data,
        '4');
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add_circle_outline_rounded),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('choosing 2 adds only the next two Tuesdays', (tester) async {
    await _open(tester);
    await _tapTime(tester, '09:00 AM');
    await _setWeeks(tester, 2);
    await tester.tap(find.text('Add 2 lessons'));
    await tester.pumpAndSettle();

    // Weeks 3 and 4 are free at 09:00 but were not asked for
    expect(_lessonRows(), {'${_key(_tue)}|09:00', '${_key(_week(1))}|09:00'});
    // Week 2 has no 09:00, so it is flagged rather than reserved
    expect(
      find.byKey(ValueKey('weekly-unavailable-${_key(_week(2))}')),
      findsOneWidget,
    );
    expect(find.text('2 of 5 lessons selected'), findsOneWidget);
    expect(_proceed(tester).onPressed, isNull);
  });

  for (final (how, action) in [
    ('choosing 0', 'Continue'),
    ('skipping', 'Schedule manually'),
  ]) {
    testWidgets('$how adds nothing and the offer is not repeated', (
      tester,
    ) async {
      await _open(tester);
      await _tapTime(tester, '09:00 AM');
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(_lessonRows(), {'${_key(_tue)}|09:00'});

      // Removing and re-picking the first lesson, or picking more by hand,
      // does not bring the offer back
      await tester.tap(find.byTooltip('Remove lesson 1'));
      await tester.pumpAndSettle();
      await _tapTime(tester, '09:00 AM');
      expect(find.text('Repeat weekly?'), findsNothing);
      await _openDay(tester, _wed);
      await _tapTime(tester, '10:00 AM');
      expect(find.text('Repeat weekly?'), findsNothing);
      expect(find.text('2 of 5 lessons selected'), findsOneWidget);
    });
  }

  testWidgets('tapping outside the offer skips it', (tester) async {
    await _open(tester);
    await _tapTime(tester, '09:00 AM');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Repeat weekly?'), findsNothing);
    expect(_lessonRows(), {'${_key(_tue)}|09:00'});
  });

  testWidgets('an unavailable week is replaced by hand, then payment opens '
      'with all five lessons', (tester) async {
    final api = await _open(tester);
    await _tapTime(tester, '09:00 AM');
    await _setWeeks(tester, 4);
    await tester.tap(find.text('Add 4 lessons'));
    await tester.pumpAndSettle();

    final busy = find.byKey(ValueKey('weekly-unavailable-${_key(_week(2))}'));
    expect(busy, findsOneWidget);
    expect(find.text('4 of 5 lessons selected'), findsOneWidget);
    expect(_proceed(tester).onPressed, isNull); // incomplete package
    expect(api.submitted, isNull);

    // The 11:00 on that Tuesday instead
    await _openDay(tester, _week(2));
    await _tapTime(tester, '11:00 AM');
    expect(busy, findsNothing);
    expect(find.text('5 of 5 lessons selected'), findsOneWidget);
    expect(_proceed(tester).onPressed, isNotNull);

    await tester.tap(find.text('Proceed to payment'));
    await tester.pumpAndSettle();
    expect(api.submitted?['schedulingMode'], 'manual');
    expect(api.submitted?['purchaseType'], 'Package');
    expect(api.submitted?['lessons'], [
      {'date': _key(_tue), 'startTime': '09:00', 'endTime': '10:00'},
      {'date': _key(_week(1)), 'startTime': '09:00', 'endTime': '10:00'},
      {'date': _key(_week(2)), 'startTime': '11:00', 'endTime': '12:00'},
      {'date': _key(_week(3)), 'startTime': '09:00', 'endTime': '10:00'},
      {'date': _key(_week(4)), 'startTime': '09:00', 'endTime': '10:00'},
    ]);
    expect(find.byType(BookingPaymentDetailsPage), findsOneWidget);
  });

  testWidgets('changing or removing one weekly lesson leaves the others', (
    tester,
  ) async {
    await _open(tester);
    await _tapTime(tester, '09:00 AM');
    await _setWeeks(tester, 1);
    await tester.tap(find.text('Add 1 lesson'));
    await tester.pumpAndSettle();
    expect(_lessonRows(), {'${_key(_tue)}|09:00', '${_key(_week(1))}|09:00'});

    // Move lesson 2 to the Wednesday: a different date and time
    await tester.tap(find.byTooltip('Change lesson 2'));
    await tester.pumpAndSettle();
    expect(
      find.text('Tap a new time above to replace this lesson.'),
      findsOneWidget,
    );
    await _openDay(tester, _wed);
    await _tapTime(tester, '10:00 AM');
    expect(_lessonRows(), {'${_key(_tue)}|09:00', '${_key(_wed)}|10:00'});
    expect(find.text('2 of 5 lessons selected'), findsOneWidget);

    // Remove lesson 1 only
    await tester.tap(find.byTooltip('Remove lesson 1'));
    await tester.pumpAndSettle();
    expect(_lessonRows(), {'${_key(_wed)}|10:00'});

    // Tapping a chosen time still deselects it
    await _tapTime(tester, '10:00 AM');
    expect(_lessonRows(), isEmpty);
  });

  testWidgets('while changing a lesson, tapping another lesson\'s time keeps '
      'it (B1)', (tester) async {
    await _open(tester);
    await _tapTime(tester, '09:00 AM');
    await _setWeeks(tester, 1);
    await tester.tap(find.text('Add 1 lesson'));
    await tester.pumpAndSettle();
    final both = {'${_key(_tue)}|09:00', '${_key(_week(1))}|09:00'};

    // Change lesson 1, then tap lesson 2's (already chosen) time
    await tester.tap(find.byTooltip('Change lesson 1'));
    await tester.pumpAndSettle();
    await _openDay(tester, _week(1));
    await _tapTime(tester, '09:00 AM');
    expect(_lessonRows(), both); // nothing removed
    expect(
      find.textContaining('That time is already one of your lessons'),
      findsOneWidget,
    );
    expect(
      find.text('Tap a new time above to replace this lesson.'),
      findsOneWidget,
    ); // still waiting for a replacement

    // A free time replaces lesson 1 only
    await _openDay(tester, _wed);
    await _tapTime(tester, '10:00 AM');
    expect(_lessonRows(), {'${_key(_wed)}|10:00', '${_key(_week(1))}|09:00'});

    // Outside Change mode, tapping a chosen time still deselects it
    await _openDay(tester, _week(1));
    await _tapTime(tester, '09:00 AM');
    expect(_lessonRows(), {'${_key(_wed)}|10:00'});
  });

  testWidgets('each unavailable week\'s warning clears only when that week '
      'gets a lesson (B2)', (tester) async {
    // Weeks 2 and 3 have no 09:00, only 11:00
    await _open(
      tester,
      lessons: 6,
      slots: [
        _slot(_tue, '09:00', '10:00'),
        _slot(_wed, '10:00', '11:00'),
        _slot(_week(1), '09:00', '10:00'),
        _slot(_week(2), '11:00', '12:00'),
        _slot(_week(3), '11:00', '12:00'),
        _slot(_week(4), '09:00', '10:00'),
      ],
    );
    await _tapTime(tester, '09:00 AM');
    await _setWeeks(tester, 4);
    await tester.tap(find.text('Add 4 lessons'));
    await tester.pumpAndSettle();
    final week2 = find.byKey(ValueKey('weekly-unavailable-${_key(_week(2))}'));
    final week3 = find.byKey(ValueKey('weekly-unavailable-${_key(_week(3))}'));
    expect(week2, findsOneWidget);
    expect(week3, findsOneWidget);
    expect(find.text('3 of 6 lessons selected'), findsOneWidget);

    // An unrelated lesson (the first week) clears neither
    await _openDay(tester, _wed);
    await _tapTime(tester, '10:00 AM');
    expect(week2, findsOneWidget);
    expect(week3, findsOneWidget);

    // Removing and re-adding week 1's lesson clears neither
    await tester.tap(find.byTooltip('Remove lesson 3')); // week 1, 09:00
    await tester.pumpAndSettle();
    expect(_lessonRows().contains('${_key(_week(1))}|09:00'), isFalse);
    await _openDay(tester, _week(1));
    await _tapTime(tester, '09:00 AM');
    expect(week2, findsOneWidget);
    expect(week3, findsOneWidget);
    expect(find.text('4 of 6 lessons selected'), findsOneWidget);

    // Replace the second unavailable week first: only its warning goes
    await _openDay(tester, _week(3));
    await _tapTime(tester, '11:00 AM');
    expect(week3, findsNothing);
    expect(week2, findsOneWidget);

    // Then the first
    await _openDay(tester, _week(2));
    await _tapTime(tester, '11:00 AM');
    expect(week2, findsNothing);
    expect(find.text('6 of 6 lessons selected'), findsOneWidget);
    expect(_proceed(tester).onPressed, isNotNull);
  });

  // Six lessons; weeks 2 and 3 have no 09:00. After four weekly lessons:
  // three chosen (first, week 1, week 4), two warnings, three left.
  // Extra free times in the first two weeks, which no warning covers.
  Future<({Finder week2, Finder week3})> twoGaps(WidgetTester tester) async {
    await _open(
      tester,
      lessons: 6,
      slots: [
        _slot(_tue, '09:00', '10:00'),
        _slot(_tue, '13:00', '14:00'),
        _slot(_wed, '10:00', '11:00'),
        _slot(_week(1), '09:00', '10:00'),
        _slot(_week(1), '13:00', '14:00'),
        _slot(_week(2), '11:00', '12:00'),
        _slot(_week(3), '11:00', '12:00'),
        _slot(_week(4), '09:00', '10:00'),
      ],
    );
    await _tapTime(tester, '09:00 AM');
    await _setWeeks(tester, 4);
    await tester.tap(find.text('Add 4 lessons'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 6 lessons selected'), findsOneWidget);
    return (
      week2: find.byKey(ValueKey('weekly-unavailable-${_key(_week(2))}')),
      week3: find.byKey(ValueKey('weekly-unavailable-${_key(_week(3))}')),
    );
  }

  const actionable = 'Choose another time for this lesson.';
  const informational =
      'No lesson is currently available at 09:00 AM during this week.';

  testWidgets('more warnings than lessons left only say what is missing, and '
      'all clear once the package is full', (tester) async {
    final (:week2, :week3) = await twoGaps(tester);
    // Two warnings, three lessons left: both ask for a time
    expect(find.textContaining(actionable), findsNWidgets(2));
    expect(find.textContaining(informational), findsNothing);

    // Two lessons outside the flagged weeks: one left, two warnings
    await _openDay(tester, _wed);
    await _tapTime(tester, '10:00 AM');
    await _openDay(tester, _tue);
    await _tapTime(tester, '01:00 PM');
    expect(find.text('5 of 6 lessons selected'), findsOneWidget);
    expect(week2, findsOneWidget);
    expect(week3, findsOneWidget);
    expect(find.textContaining(actionable), findsNothing);
    expect(find.textContaining(informational), findsNWidgets(2));
    expect(
      find.textContaining(
        DateFormat('EEE d MMM').format(_week(2)),
        findRichText: false,
      ),
      findsWidgets,
    );
    expect(_proceed(tester).onPressed, isNull); // counts are unchanged

    // The last lesson, again outside the flagged weeks: nothing left to place
    await _openDay(tester, _week(1));
    await _tapTime(tester, '01:00 PM');
    expect(find.text('6 of 6 lessons selected'), findsOneWidget);
    expect(week2, findsNothing);
    expect(week3, findsNothing);
    expect(_proceed(tester).onPressed, isNotNull);
  });

  testWidgets('moving a lesson into a flagged week clears only that week\'s '
      'warning', (tester) async {
    final (:week2, :week3) = await twoGaps(tester);
    final before = _lessonRows();

    // Move lesson 2 (week 1, 09:00) to week 3's 11:00
    await tester.tap(find.byTooltip('Change lesson 2'));
    await tester.pumpAndSettle();
    await _openDay(tester, _week(3));
    await _tapTime(tester, '11:00 AM');

    expect(week3, findsNothing);
    expect(week2, findsOneWidget); // the unrelated week keeps its warning
    expect(_lessonRows(), {
      ...before.difference({'${_key(_week(1))}|09:00'}),
      '${_key(_week(3))}|11:00',
    });
    expect(find.text('3 of 6 lessons selected'), findsOneWidget);
  });

  testWidgets('moving a lesson outside the flagged weeks clears no warning', (
    tester,
  ) async {
    final (:week2, :week3) = await twoGaps(tester);
    await tester.tap(find.byTooltip('Change lesson 2'));
    await tester.pumpAndSettle();
    await _openDay(tester, _wed);
    await _tapTime(tester, '10:00 AM');
    expect(week2, findsOneWidget);
    expect(week3, findsOneWidget);
    expect(_lessonRows().contains('${_key(_wed)}|10:00'), isTrue);
  });

  testWidgets('Proceed to payment waits while a change is pending', (
    tester,
  ) async {
    final api = await _open(tester, lessons: 2);
    await _tapTime(tester, '09:00 AM');
    await _setWeeks(tester, 1);
    await tester.tap(find.text('Add 1 lesson'));
    await tester.pumpAndSettle();
    expect(_proceed(tester).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Change lesson 2'));
    await tester.pumpAndSettle();
    expect(_proceed(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('change-pending')), findsOneWidget);

    // Cancelling the change allows it again
    await tester.tap(find.byTooltip('Cancel change'));
    await tester.pumpAndSettle();
    expect(_proceed(tester).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('change-pending')), findsNothing);

    // So does finishing it; the new time is what gets sent
    await tester.tap(find.byTooltip('Change lesson 2'));
    await tester.pumpAndSettle();
    await _openDay(tester, _wed);
    await _tapTime(tester, '10:00 AM');
    expect(_proceed(tester).onPressed, isNotNull);
    await tester.tap(find.text('Proceed to payment'));
    await tester.pumpAndSettle();
    expect(api.submitted?['lessons'], [
      {'date': _key(_tue), 'startTime': '09:00', 'endTime': '10:00'},
      {'date': _key(_wed), 'startTime': '10:00', 'endTime': '11:00'},
    ]);
    expect(find.byType(BookingPaymentDetailsPage), findsOneWidget);
  });

  group('weekly dates on fixed calendars', () {
    test('keep the weekday across month, year and leap-day ends', () {
      for (final (from, weeks, expected) in [
        ('2030-12-31', 1, '2031-01-07'), // December into January
        ('2030-12-24', 2, '2031-01-07'),
        ('2031-01-28', 1, '2031-02-04'), // month end
        ('2031-04-29', 1, '2031-05-06'), // 30-day month
        ('2028-02-22', 1, '2028-02-29'), // leap year
        ('2029-02-22', 1, '2029-03-01'),
        ('2030-03-26', 4, '2030-04-23'),
      ]) {
        final result = addWeeksToDate(from, weeks);
        expect(result, expected, reason: '$from + $weeks weeks');
        expect(
          DateTime.parse(result).weekday,
          DateTime.parse(from).weekday,
          reason: 'same weekday as $from',
        );
      }
    });

    for (final (name, dates) in [
      (
        'December into January',
        ['2030-12-24', '2030-12-31', '2031-01-07', '2031-01-14'],
      ),
      (
        'January into February',
        ['2031-01-21', '2031-01-28', '2031-02-04', '2031-02-11'],
      ),
    ]) {
      testWidgets('weekly lessons from $name keep the day and time', (
        tester,
      ) async {
        final api = await _open(
          tester,
          lessons: 4,
          slots: [
            for (final d in dates)
              AvailableBookingSlot(
                date: d,
                startTime: '15:00',
                endTime: '16:00',
              ),
          ],
        );
        await _tapTime(tester, '03:00 PM');
        expect(find.textContaining('Tuesdays at 03:00 PM'), findsOneWidget);
        await _setWeeks(tester, 3);
        await tester.tap(find.text('Add 3 lessons'));
        await tester.pumpAndSettle();

        expect(_lessonRows(), {for (final d in dates) '$d|15:00'});
        for (final (i, d) in dates.indexed) {
          final label = DateFormat('EEE d MMM').format(DateTime.parse(d));
          expect(label, startsWith('Tue'));
          expect(
            find.text('Lesson ${i + 1} · $label · 03:00 PM'),
            findsOneWidget,
          );
        }
        await tester.tap(find.text('Proceed to payment'));
        await tester.pumpAndSettle();
        expect(api.submitted?['lessons'], [
          for (final d in dates)
            {'date': d, 'startTime': '15:00', 'endTime': '16:00'},
        ]);
      });
    }
  });

  testWidgets('the remaining lessons can all be picked by hand', (
    tester,
  ) async {
    final api = await _open(tester, lessons: 3);
    await _tapTime(tester, '09:00 AM');
    await tester.tap(find.text('Schedule manually'));
    await tester.pumpAndSettle();
    await _openDay(tester, _wed);
    await _tapTime(tester, '10:00 AM');
    expect(_proceed(tester).onPressed, isNull);
    await _openDay(tester, _week(2));
    await _tapTime(tester, '11:00 AM');
    expect(find.text('3 of 3 lessons selected'), findsOneWidget);

    await tester.tap(find.text('Proceed to payment'));
    await tester.pumpAndSettle();
    expect((api.submitted?['lessons'] as List), hasLength(3));
    expect(find.byType(BookingPaymentDetailsPage), findsOneWidget);
  });
}
