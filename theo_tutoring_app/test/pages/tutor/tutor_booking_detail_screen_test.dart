import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_booking_detail.dart';

// Shape from GET /TutorLandingpage/bookings/{id} (lib/booking_tutor.dart)
Map<String, dynamic> _detail({
  String? note,
  String? university,
  double? rating,
  int reviewCount = 0,
  Map<String, dynamic>? recurring,
  bool canCancel = false,
}) => {
  'tutor': {'name': 'Amahle Tshabalala'},
  'booking': {
    'bookingId': 41,
    'reference': 'REQ-41',
    'status': 'Confirmed',
    'subject': 'Calculus',
    'date': '2026-10-27',
    'startTime': '16:00',
    'endTime': '17:00',
    'durationMinutes': 60,
    'note': note,
    'receivedMinutesAgo': 180,
    'canCancel': canCancel,
  },
  'student': {
    'name': 'Emma Roberts',
    'year': '2',
    'course': 'BSc Computer Science',
    'verified': true,
    'university': university,
    'rating': rating,
    'reviewCount': reviewCount,
  },
  'recurring': recurring,
};

Future<void> _pump(WidgetTester tester, Map<String, dynamic> data) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: TutorBookingDetailScreen(
        bookingId: 41,
        loadBooking: (_) async => data,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the note, university and rating', (tester) async {
    await _pump(
      tester,
      _detail(
        note: 'Looking for help with derivatives.',
        university: 'University of Johannesburg',
        rating: 4.5,
        reviewCount: 2,
        recurring: {
          'frequency': 'Weekly',
          'weekday': 'Tuesday',
          'startTime': '16:00',
          'endTime': '17:00',
          'sessions': [
            {'bookingId': 41, 'date': '2026-10-27', 'status': 'Confirmed'},
            {'bookingId': 42, 'date': '2026-11-03', 'status': 'Confirmed'},
          ],
          'totalSessions': 2,
          'totalMinutes': 120,
        },
      ),
    );
    expect(find.text('STUDENT NOTE'), findsOneWidget);
    expect(find.text('"Looking for help with derivatives."'), findsOneWidget);
    expect(find.text('UNIVERSITY'), findsOneWidget);
    expect(find.text('University of Johannesburg'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('from 2 reviews of you'), findsOneWidget);
    expect(find.text('Every Tuesday (Weekly)'), findsOneWidget);
    expect(
      find.text('There are no recurring bookings currently.'),
      findsNothing,
    );
  });

  testWidgets('says when there is no note, university, rating or series', (
    tester,
  ) async {
    await _pump(tester, _detail());
    expect(find.text('STUDENT NOTE'), findsOneWidget);
    expect(find.text('No note from the student.'), findsOneWidget);
    expect(find.text('Not provided'), findsOneWidget);
    expect(find.text('No rating from this student yet'), findsOneWidget);
    expect(
      find.text('There are no recurring bookings currently.'),
      findsOneWidget,
    );
  });

  group('Cancel and Reschedule', () {
    late List<String> sent;
    late bool? popped;

    // Opens the page from a button, like the Schedule page does, so the
    // test can see it close with `true` (the schedule reloads).
    Future<void> open(WidgetTester tester, {bool fail = false}) async {
      sent = [];
      popped = null;
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<Map<String, dynamic>> request(String what, int id) async {
        sent.add('$what $id');
        if (fail) throw Exception('Could not cancel this session.');
        return {'status': 'Cancelled'};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TutorBookingDetailScreen(
                        bookingId: 41,
                        loadBooking: (_) async => _detail(canCancel: true),
                        cancelBooking: (id) => request('cancel', id),
                        rescheduleBooking: (id) => request('reschedule', id),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('both buttons show side by side', (tester) async {
      await open(tester);
      final reschedule = tester.getCenter(
        find.byKey(const Key('booking-reschedule')),
      );
      final cancel = tester.getCenter(find.byKey(const Key('booking-cancel')));
      expect(reschedule.dy, cancel.dy);
      expect(reschedule.dx, lessThan(cancel.dx));
    });

    testWidgets('no buttons once the session cannot be cancelled', (
      tester,
    ) async {
      await _pump(tester, _detail());
      expect(find.byKey(const Key('booking-cancel')), findsNothing);
      expect(find.byKey(const Key('booking-reschedule')), findsNothing);
    });

    testWidgets('Cancel asks "are you sure" first', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('booking-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Are you sure you want to cancel the meeting with Emma Roberts? '
          'The student will be notified.',
        ),
        findsOneWidget,
      );

      // "No" keeps the session
      await tester.tap(find.text('No, keep it'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(find.byType(TutorBookingDetailScreen), findsOneWidget);

      // "Yes" cancels it and closes the page
      await tester.tap(find.byKey(const Key('booking-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, cancel'));
      await tester.pumpAndSettle();
      expect(sent, ['cancel 41']);
      expect(popped, isTrue);
      expect(
        find.text('Session cancelled. The student has been notified.'),
        findsOneWidget,
      );
    });

    testWidgets('Reschedule explains it, then lets the student rebook', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('booking-reschedule')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Pressing this button will allow the student to book another '
          'session.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Reschedule'));
      await tester.pumpAndSettle();
      expect(sent, ['reschedule 41']);
      expect(popped, isTrue);
      expect(
        find.text('The student has been asked to book a new time.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed request keeps the page open', (tester) async {
      await open(tester, fail: true);
      await tester.tap(find.byKey(const Key('booking-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, cancel'));
      await tester.pumpAndSettle();
      expect(sent, ['cancel 41']);
      expect(popped, isNull);
      expect(find.byType(TutorBookingDetailScreen), findsOneWidget);
      expect(find.textContaining('Could not cancel'), findsOneWidget);
      // the buttons are back so the tutor can try again
      expect(find.byKey(const Key('booking-cancel')), findsOneWidget);
    });
  });
}
