import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_api.dart';
import 'package:theo_tutoring_app/Pages/Student/student_lesson.dart';
import 'package:theo_tutoring_app/Pages/Student/student_lessons_api.dart';
import 'package:theo_tutoring_app/Pages/Student/student_reschedule.dart';

// Reschedule in My Schedule: a paid lesson moves to another free hour with
// the same tutor and subject, without paying again. The lessons API and the
// tutor's free hours are fakes.

Map<String, dynamic> _lesson(int id, String status) => {
  'bookingId': id,
  'status': status,
  'subject': 'Calculus',
  'tutorName': 'Amahle Tshabalala',
  'tutorId': 4,
  'subjectId': 9,
  'tutorPhoto': null,
  'date': '2026-11-20',
  'startTime': '15:00',
  'endTime': '16:00',
  'cancellationReason': null,
};

class _FakeLessonsApi extends StudentLessonsApi {
  _FakeLessonsApi(this.lessons);

  List<Map<String, dynamic>> lessons;
  final moves = <Map<String, Object>>[];
  Object? refuse; // thrown by reschedule when set
  int fetches = 0;

  @override
  Future<Map<String, dynamic>> fetch() async {
    fetches++;
    return {'upcoming': lessons, 'cancelled': <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> reschedule(
    int bookingId, {
    required String date,
    required String startTime,
  }) async {
    moves.add({'bookingId': bookingId, 'date': date, 'startTime': startTime});
    if (refuse case final error?) throw error;
    return {'bookingId': bookingId, 'date': date, 'startTime': startTime};
  }
}

class _FakeAvailability implements BookingFlowApi {
  final requests = <Map<String, Object>>[];
  List<AvailableBookingSlot> slots = const [
    AvailableBookingSlot(
      date: '2026-11-21',
      startTime: '09:00',
      endTime: '10:00',
    ),
    AvailableBookingSlot(
      date: '2026-11-21',
      startTime: '10:00',
      endTime: '11:00',
    ),
    AvailableBookingSlot(
      date: '2026-11-23',
      startTime: '14:00',
      endTime: '15:00',
    ),
  ];

  @override
  Future<BookingAvailability> availability({
    required int tutorId,
    required int subjectId,
    required String from,
    required String through,
  }) async {
    requests.add({
      'tutorId': tutorId,
      'subjectId': subjectId,
      'from': from,
      'through': through,
    });
    return BookingAvailability(slots: slots);
  }

  @override
  Future<BookingPurchaseResult> createPurchase(Map<String, Object> request) =>
      throw UnimplementedError();

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

Future<void> _pump(
  WidgetTester tester,
  _FakeLessonsApi api,
  _FakeAvailability availability,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StudentLessonsPage(api: api, availabilityApi: availability),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapReschedule(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Lesson options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Reschedule'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Reschedule shows the tutor\'s free times for that subject', (
    tester,
  ) async {
    final availability = _FakeAvailability();
    await _pump(tester, _FakeLessonsApi([_lesson(7, 'Confirmed')]), availability);
    await _tapReschedule(tester);

    expect(find.byType(StudentReschedulePage), findsOneWidget);
    expect(find.text('Now: Fri 20 Nov, 15:00–16:00'), findsOneWidget);
    expect(
      find.text('Your payment stays with this lesson. Nothing extra is '
          'charged.'),
      findsOneWidget,
    );
    expect(availability.requests.single['tutorId'], 4);
    expect(availability.requests.single['subjectId'], 9);
    // Days with free hours, the first one picked with its times
    expect(find.text('Sat 21 Nov'), findsOneWidget);
    expect(find.text('Mon 23 Nov'), findsOneWidget);
    expect(find.text('09:00–10:00'), findsOneWidget);
    expect(find.text('14:00–15:00'), findsNothing);
    // Nothing to save until a time is chosen
    expect(find.text('Choose a new time'), findsOneWidget);
  });

  testWidgets('choosing a time moves the lesson and reloads My Schedule', (
    tester,
  ) async {
    final api = _FakeLessonsApi([_lesson(7, 'Confirmed')]);
    await _pump(tester, api, _FakeAvailability());
    final fetchesBefore = api.fetches;
    await _tapReschedule(tester);

    await tester.tap(find.text('Mon 23 Nov'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14:00–15:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Mon 23 Nov, 14:00'));
    await tester.pumpAndSettle();

    expect(api.moves, [
      {'bookingId': 7, 'date': '2026-11-23', 'startTime': '14:00'},
    ]);
    expect(find.byType(StudentReschedulePage), findsNothing);
    expect(api.fetches, greaterThan(fetchesBefore)); // list reloaded
    expect(find.textContaining('Lesson moved to Mon 23 Nov, 14:00'),
        findsOneWidget);
  });

  testWidgets('a refused move shows the server message and stays open', (
    tester,
  ) async {
    final api = _FakeLessonsApi([_lesson(7, 'Confirmed')])
      ..refuse = const StudentLessonsException(
        'That time is no longer available. Please choose another one.',
      );
    final availability = _FakeAvailability();
    await _pump(tester, api, availability);
    await _tapReschedule(tester);

    await tester.tap(find.text('09:00–10:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Sat 21 Nov, 09:00'));
    await tester.pumpAndSettle();

    expect(
      find.text('That time is no longer available. Please choose another '
          'one.'),
      findsOneWidget,
    );
    expect(find.byType(StudentReschedulePage), findsOneWidget);
    expect(availability.requests.length, 2); // free times reloaded
  });

  testWidgets('an unpaid lesson cannot be rescheduled', (tester) async {
    final availability = _FakeAvailability();
    await _pump(tester, _FakeLessonsApi([_lesson(7, 'Pending')]), availability);
    await _tapReschedule(tester);

    expect(find.byType(StudentReschedulePage), findsNothing);
    expect(find.textContaining('Only paid, confirmed lessons'), findsOneWidget);
    expect(availability.requests, isEmpty);
  });

  testWidgets('a tutor with no free times says so', (tester) async {
    final availability = _FakeAvailability()..slots = const [];
    await _pump(
      tester,
      _FakeLessonsApi([_lesson(7, 'Confirmed')]),
      availability,
    );
    await _tapReschedule(tester);

    expect(find.textContaining('has no free times'), findsOneWidget);
    expect(find.text('Choose a new time'), findsOneWidget);
  });
}
