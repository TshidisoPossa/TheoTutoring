import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_dashboard.dart';

// Shape from GET /TutorLandingpage/LandingPageScreen (MySQL sends numbers
// back as text).
Map<String, dynamic> _session(
  String id,
  String subject,
  String start,
  String end,
  String student, {
  String? note,
  String? link,
  String minutes = '45',
}) => {
  'Booking_id': id,
  'SubjectID': id,
  'Subject': subject,
  'StartTime': start,
  'EndTime': end,
  'Note': note,
  'Link': link,
  'StudentName': student,
  'MinutesUntilStart': minutes,
};

final _dashboard = {
  'tutor': {'name': 'Amahle Tshabalala'},
  'accountStatus': 'Active',
  'activeStudents': 14,
  'upcomingToday': 2,
  'averageRating': 4.5,
  'todaysSchedule': [
    _session('2', 'Advanced Essay Writing', '15:00:00', '16:00:00',
        'Sarah Jenkins', link: 'https://zoom.us/j/1'),
    _session('3', 'Intro to Python', '17:30:00', '18:30:00', 'David Kim',
        note: 'Topic: Functions & Loops', minutes: '150'),
  ],
  'latestReviews': [],
};

Future<void> _pump(WidgetTester tester, Map<String, dynamic> data) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: TutorDashboard(initialData: data)));
  await tester.pump();
}

void main() {
  testWidgets('stat cards show the backend numbers', (tester) async {
    await _pump(tester, _dashboard);
    expect(find.text('Active Students'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('Upcoming Today'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets("Today's Schedule summarises today's sessions", (tester) async {
    await _pump(tester, _dashboard);
    expect(find.text('2 sessions'), findsOneWidget);
    expect(find.text('3:00 PM – 4:00 PM'), findsOneWidget);
    expect(find.text('In 45 min'), findsOneWidget);
    expect(find.text('In 2.5 hrs'), findsOneWidget);
    expect(find.text('Advanced Essay Writing'), findsOneWidget);
    expect(find.text('with Sarah Jenkins', findRichText: true), findsOneWidget);
    // Footer: where the session is, or the student's note
    expect(find.text('Zoom Meeting'), findsOneWidget);
    expect(find.text('Topic: Functions & Loops'), findsOneWidget);
  });

  testWidgets('no sessions today shows the empty card', (tester) async {
    await _pump(tester, {
      ..._dashboard,
      'upcomingToday': 0,
      'todaysSchedule': [],
    });
    expect(find.text('0 sessions'), findsOneWidget);
    expect(find.text('No sessions today'), findsOneWidget);
  });
}
