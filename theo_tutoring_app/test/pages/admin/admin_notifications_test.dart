import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_notifications.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_shell.dart';

// The admin Notifications page: the same list students and tutors have,
// with admin events that link to where the admin acts on them.

Map<String, dynamic> _n(String id, String type, String title) => {
  'id': id,
  'type': type,
  'title': title,
  'body': '$title body',
  'read': false,
  'section': 'today',
  'minutesAgo': 2,
};

Future<void> _pump(WidgetTester tester, {List<String>? marked}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        AdminRoutes.applications: (_) =>
            const Scaffold(body: Text('Applications page')),
        AdminRoutes.reports: (_) => const Scaffold(body: Text('Reports page')),
        AdminRoutes.refunds: (_) => const Scaffold(body: Text('Refunds page')),
      },
      home: AdminNotificationsScreen(
        loadNotifications: () async => {
          'unreadCount': 3,
          'notifications': [
            _n('a', 'ApplicationSubmitted', 'New tutor application'),
            _n('b', 'ReportSubmitted', 'New report'),
            _n('c', 'RefundRequested', 'Refund to review'),
          ],
        },
        markRead: (id) async {
          marked?.add(id);
          return 2;
        },
        markAllRead: () async => 0,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists admin notifications with links to act on them', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('New tutor application'), findsOneWidget);
    expect(find.text('New report'), findsOneWidget);
    expect(find.text('Refund to review'), findsOneWidget);
    expect(find.text('Review application'), findsOneWidget);
    expect(find.text('Review report'), findsOneWidget);
    expect(find.text('Review refund'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  for (final (link, page) in [
    ('Review application', 'Applications page'),
    ('Review report', 'Reports page'),
    ('Review refund', 'Refunds page'),
  ]) {
    testWidgets('$link marks it read and opens the right page', (
      tester,
    ) async {
      final marked = <String>[];
      await _pump(tester, marked: marked);
      await tester.tap(find.text(link));
      await tester.pumpAndSettle();
      expect(find.text(page), findsOneWidget);
      expect(marked, hasLength(1));
    });
  }
}
