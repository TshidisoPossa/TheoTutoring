import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Student/student_notifications.dart';

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
}) => {
  'id': id,
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
Future<List<int?>> _open(WidgetTester tester) async {
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
                  loadNotifications: () async => _page,
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
}
