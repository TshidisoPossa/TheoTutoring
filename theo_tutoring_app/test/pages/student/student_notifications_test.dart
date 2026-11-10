import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Student/student_notifications.dart';
import 'package:theo_tutoring_app/Pages/notifications_screen.dart';

// Shape from GET /students/notifications
Map<String, dynamic> _card(
  String id,
  String type,
  String title,
  String body, {
  bool read = false,
  String section = 'today',
  int minutesAgo = 5,
  int? bookingId,
  int? tutorId,
  int? subjectId,
}) => {
  'id': id,
  'tutorId': ?tutorId,
  'subjectId': ?subjectId,
  'type': type,
  'title': title,
  'body': body,
  'bookingId': bookingId,
  'read': read,
  'createdAt': '2026-10-23T14:20:00.000Z',
  'minutesAgo': minutesAgo,
  'section': section,
};

final _page = {
  'unreadCount': 2,
  'notifications': [
    _card('paid-27', 'PaymentReceived', 'Payment successful',
        'Your payment of R250.00 went through. Your Maths lesson with Thabo '
        'Mokoena on Tue 27 Oct, 14:00 is confirmed.',
        minutesAgo: 2, bookingId: 41),
    _card('upcoming-41-hour', 'UpcomingSession', 'Upcoming lesson',
        'Your Maths lesson with Thabo Mokoena starts in an hour.',
        minutesAgo: 10, bookingId: 41),
    _card('refund-9', 'RefundApproved', 'Refund approved',
        'Your refund of R125.00 (50%) for the Physics lesson was approved.',
        read: true, section: 'yesterday', bookingId: 50),
  ],
};

// Opens the bell page on top of a button, like the dashboard does, and
// records the tab it pops with.
Future<List<int?>> _open(
  WidgetTester tester, {
  Map<String, dynamic>? page,
  Widget Function(NotificationItem n)? rebookPage,
}) async {
  final popped = <int?>[];
  tester.view.physicalSize = const Size(400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => popped.add(
            await Navigator.push<int>(
              context,
              MaterialPageRoute(
                builder: (_) => StudentNotificationsScreen(
                  loadNotifications: () async => page ?? _page,
                  rebookPage: rebookPage,
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

void main() {
  testWidgets('shows payment, lesson and refund cards', (tester) async {
    await _open(tester);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('2 unread'), findsOneWidget);
    expect(find.text('Payment successful'), findsOneWidget);
    expect(find.text('Refund approved'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    // Lesson cards link to Lessons; refund cards do not
    expect(find.text('View my lessons'), findsOneWidget);
    expect(find.text('View upcoming lesson'), findsOneWidget);
  });

  testWidgets('a lesson link goes back to the Lessons tab', (tester) async {
    final popped = await _open(tester);
    await tester.tap(find.text('View upcoming lesson'));
    await tester.pumpAndSettle();
    expect(popped, [studentLessonsTab]);
    expect(find.byType(StudentNotificationsScreen), findsNothing);
  });

  testWidgets('a bottom-bar tap goes back with that tab', (tester) async {
    final popped = await _open(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(popped, [3]);
  });

  final tutorChanges = {
    'unreadCount': 2,
    'notifications': [
      _card('n1', 'BookingRescheduled', 'Session rescheduled',
          'Thabo needs to reschedule your Calculus session on Tue 17 Nov, '
          '13:00. Please book again at a time that suits you.',
          bookingId: 110, tutorId: 3, subjectId: 7),
      _card('n2', 'BookingCancelled', 'Session cancelled',
          'Thabo cancelled your Physics session on Wed 18 Nov, 10:00.',
          bookingId: 111),
    ],
  };

  testWidgets('a rescheduled lesson links to booking a new time', (
    tester,
  ) async {
    NotificationItem? opened;
    final popped = await _open(
      tester,
      page: tutorChanges,
      rebookPage: (n) {
        opened = n;
        return const Scaffold(body: Text('booking page'));
      },
    );
    expect(find.text('Session rescheduled'), findsOneWidget);
    expect(find.text('Session cancelled'), findsOneWidget);
    // the cancelled card links to the lessons, the rescheduled one to booking
    expect(find.text('View my lessons'), findsOneWidget);

    await tester.tap(find.text('Book a new time'));
    await tester.pumpAndSettle();
    expect(find.text('booking page'), findsOneWidget);
    expect(opened?.tutorId, 3);
    expect(opened?.subjectId, 7);
    expect(popped, isEmpty); // the bell page stays underneath
  });
}
