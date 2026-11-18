import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/services/app_navigator.dart';
import 'package:theo_tutoring_app/services/in_app_notifications.dart';

// In-app notification pop-ups: a banner at the top of the screen for each
// new unread notification, gone after a few seconds. The list is a fake.

Map<String, dynamic> _n(String id, String title, {bool read = false}) => {
  'id': id,
  'type': 'NewMessage',
  'title': title,
  'body': 'Body of $title',
  'read': read,
  'section': 'today',
  'minutesAgo': 0,
};

class _FakeList {
  List<Map<String, dynamic>> items = [];
  int calls = 0;

  Future<Map<String, dynamic>> fetch() async {
    calls++;
    return {
      'unreadCount': items.where((n) => n['read'] != true).length,
      'notifications': items,
    };
  }
}

Future<void> _pumpApp(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    navigatorKey: appNavigatorKey,
    home: const Scaffold(body: Text('Dashboard')),
  ),
);

Finder get _banner =>
    find.byKey(const ValueKey('in-app-notification-banner'));

void main() {
  final live = InAppNotifications.instance;
  tearDown(live.stop);

  testWidgets('old notifications never pop up; a new one does', (
    tester,
  ) async {
    await _pumpApp(tester);
    final list = _FakeList()..items = [_n('a', 'Old message')];
    var opened = 0;
    live.start(fetch: list.fetch, openPage: () => opened++);
    await tester.pump(); // the baseline check
    expect(_banner, findsNothing);
    expect(live.unreadCount.value, 1);

    list.items = [_n('b', 'Lesson booked'), ...list.items];
    await live.check();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // slides in

    expect(_banner, findsOneWidget);
    expect(find.text('Lesson booked'), findsOneWidget);
    expect(find.text('Body of Lesson booked'), findsOneWidget);
    expect(find.text('Old message'), findsNothing);
    expect(live.unreadCount.value, 2);
    live.stop(); // no timers left running
    await tester.pump();
  });

  testWidgets('the banner goes away by itself after a few seconds', (
    tester,
  ) async {
    await _pumpApp(tester);
    final list = _FakeList();
    live.start(fetch: list.fetch, openPage: () {});
    await tester.pump();

    list.items = [_n('b', 'Payment successful')];
    await live.check();
    await tester.pump();
    expect(_banner, findsOneWidget);

    await tester.pump(InAppNotifications.bannerDuration);
    await tester.pump();
    expect(_banner, findsNothing);
    live.stop(); // no timers left running
    await tester.pump();
  });

  testWidgets('tapping the banner opens the notifications page', (
    tester,
  ) async {
    await _pumpApp(tester);
    final list = _FakeList();
    var opened = 0;
    live.start(fetch: list.fetch, openPage: () => opened++);
    await tester.pump();

    list.items = [_n('b', 'New report')];
    await live.check();
    await tester.pump(); // starts the slide-in
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(_banner);
    await tester.pump();

    expect(opened, 1);
    expect(_banner, findsNothing);
    live.stop(); // no timers left running
    await tester.pump();
  });

  testWidgets('several new ones show one after another', (tester) async {
    await _pumpApp(tester);
    final list = _FakeList();
    live.start(fetch: list.fetch, openPage: () {});
    await tester.pump();

    // Newest first, as the server sends them
    list.items = [_n('c', 'Second'), _n('b', 'First')];
    await live.check();
    await tester.pump();
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsNothing);

    await tester.pump(InAppNotifications.bannerDuration);
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);

    await tester.pump(InAppNotifications.bannerDuration);
    await tester.pump();
    expect(_banner, findsNothing);
    live.stop(); // no timers left running
    await tester.pump();
  });

  testWidgets('read ones and ones arriving while the page is open do not '
      'pop up', (tester) async {
    await _pumpApp(tester);
    final list = _FakeList();
    live.start(fetch: list.fetch, openPage: () {});
    await tester.pump();

    list.items = [_n('b', 'Already read', read: true)];
    await live.check();
    await tester.pump();
    expect(_banner, findsNothing);

    live.pageOpened();
    list.items = [_n('c', 'Seen on the page'), ...list.items];
    await live.check();
    await tester.pump();
    expect(_banner, findsNothing);
    live.pageClosed();

    // Already listed on the page, so it does not pop up afterwards either
    await live.check();
    await tester.pump();
    expect(_banner, findsNothing);
    live.stop(); // no timers left running
    await tester.pump();
  });

  testWidgets('signing out stops the checks and the count', (tester) async {
    await _pumpApp(tester);
    final list = _FakeList()..items = [_n('a', 'Old')];
    live.start(fetch: list.fetch, openPage: () {});
    await tester.pump();
    expect(live.isRunning, isTrue);

    live.stop();
    final calls = list.calls;
    await tester.pump(InAppNotifications.pollInterval * 2);
    expect(live.isRunning, isFalse);
    expect(list.calls, calls);
    expect(live.unreadCount.value, 0);
    live.stop(); // no timers left running
    await tester.pump();
  });

  testWidgets('it checks again every few seconds while signed in', (
    tester,
  ) async {
    await _pumpApp(tester);
    final list = _FakeList();
    live.start(fetch: list.fetch, openPage: () {});
    await tester.pump();
    final calls = list.calls;

    list.items = [_n('b', 'Upcoming lesson')];
    await tester.pump(InAppNotifications.pollInterval);
    await tester.pump();
    expect(list.calls, calls + 1);
    expect(_banner, findsOneWidget);
    live.stop(); // no timers left running
    await tester.pump();
  });
}
