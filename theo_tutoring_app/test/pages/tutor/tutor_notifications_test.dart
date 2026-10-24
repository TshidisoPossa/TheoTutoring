import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_notifications.dart';

// Shape from GET /TutorLandingpage/notifications
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
  'unreadCount': 3,
  'notifications': [
    _card('booked-27', 'BookingConfirmed', 'New lesson booked',
        'Lesego Mokoena booked a lesson in Maths for Tue 27 Oct, 14:00.',
        minutesAgo: 2, bookingId: 41),
    _card('upcoming-41-hour', 'UpcomingSession', 'Upcoming lesson',
        "You're tutoring Lesego Mokoena in Maths in an hour.",
        minutesAgo: 10, bookingId: 41),
    _card('review-12', 'NewReview', 'New review',
        'Lerato Dube gave your Maths lesson 5 stars: “Very patient.”',
        minutesAgo: 35, bookingId: 47),
    _card('x1', 'BookingCancelled', 'Session cancelled',
        'Sipho Ndlovu cancelled the Physics session on Mon 26 Oct, 10:00.',
        read: true, section: 'yesterday', bookingId: 50),
  ],
};

Future<void> _pump(WidgetTester tester, Map<String, dynamic> page) async {
  tester.view.physicalSize = const Size(400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: TutorNotificationsScreen(loadNotifications: () async => page),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('groups cards by day with the unread count', (tester) async {
    await _pump(tester, _page);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Tutor'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('3 unread'), findsOneWidget);
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(find.text('2 min ago'), findsOneWidget);
    // Only lesson cards link to the lesson
    expect(find.text('View booked lesson'), findsOneWidget);
    expect(find.text('View scheduled lesson'), findsOneWidget);
  });

  testWidgets('nothing unread hides Mark all as read', (tester) async {
    await _pump(tester, {
      'unreadCount': 0,
      'notifications': [
        _card('x1', 'BookingCancelled', 'Session cancelled', 'Cancelled.',
            read: true),
      ],
    });
    expect(find.text('Mark all as read'), findsNothing);
  });

  testWidgets('empty list explains what will show here', (tester) async {
    await _pump(tester, {'unreadCount': 0, 'notifications': []});
    expect(find.text('No notifications yet'), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    var calls = 0;
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TutorNotificationsScreen(
          loadNotifications: () async {
            if (calls++ == 0) throw Exception('offline');
            return _page;
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('a bottom-bar tap goes back with that tab', (tester) async {
    int? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.push<int>(
                context,
                MaterialPageRoute(
                  builder: (_) => TutorNotificationsScreen(
                    loadNotifications: () async => _page,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(popped, 1);
    expect(find.byType(TutorNotificationsScreen), findsNothing);
  });
}
