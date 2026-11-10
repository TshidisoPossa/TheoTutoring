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
  String? link,
  String status = 'Confirmed',
}) => {
  'tutor': {'name': 'Amahle Tshabalala'},
  'booking': {
    'bookingId': 41,
    'reference': 'REQ-41',
    'status': status,
    'link': link,
    'subject': 'Calculus',
    'date': '2026-10-27',
    'startTime': '16:00',
    'endTime': '17:00',
    'durationMinutes': 60,
    'note': note,
    'receivedMinutesAgo': 180,
    'canPostpone': false,
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

  group('Join session', () {
    bool joinEnabled(WidgetTester tester) {
      final button = find.ancestor(
        of: find.text('Join session'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(button, findsOneWidget);
      return tester.widget<ButtonStyleButton>(button).enabled;
    }

    testWidgets('is enabled for a Confirmed lesson with a link', (
      tester,
    ) async {
      await _pump(tester, _detail(link: 'https://meet.google.com/abc'));
      expect(joinEnabled(tester), isTrue);
      expect(find.text('Session link not added yet'), findsNothing);
    });

    testWidgets('is enabled for a Postponed lesson with a link', (
      tester,
    ) async {
      await _pump(
        tester,
        _detail(link: 'https://meet.google.com/abc', status: 'Postponed'),
      );
      expect(joinEnabled(tester), isTrue);
    });

    testWidgets('is disabled, and says so, when there is no link', (
      tester,
    ) async {
      await _pump(tester, _detail());
      expect(joinEnabled(tester), isFalse);
      expect(find.text('Session link not added yet'), findsOneWidget);
    });

    testWidgets('is disabled on a cancelled lesson', (tester) async {
      await _pump(
        tester,
        _detail(link: 'https://meet.google.com/abc', status: 'Cancelled'),
      );
      expect(joinEnabled(tester), isFalse);
    });
  });
}
