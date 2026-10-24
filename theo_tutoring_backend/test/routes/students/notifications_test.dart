import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/student_notifications.dart';

import '../../../routes/students/notifications/[id]/read.dart' as read_route;
import '../../../routes/students/notifications/index.dart' as list_route;
import '../../../routes/students/notifications/read-all.dart'
    as read_all_route;
import '../../../routes/students/notifications/unread-count.dart'
    as count_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockNotificationStore extends Mock implements NotificationStore {}

void main() {
  late _MockRequestContext context;
  late _MockNotificationStore store;

  void request(String method, String path) {
    when(() => context.request).thenReturn(
      Request(method, Uri.parse('http://localhost$path')),
    );
  }

  setUp(() {
    context = _MockRequestContext();
    store = _MockNotificationStore();
    when(() => context.read<StudentSession>()).thenReturn(
      const StudentSession('student-uid', 19),
    );
    when(() => context.read<NotificationStore>()).thenReturn(store);
  });

  group('GET /students/notifications', () {
    test('returns the notifications and the unread count', () async {
      request('GET', '/students/notifications');
      when(
        () => store.list('student-uid', limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => [
          AppNotification(
            id: 'paid-27',
            type: NotificationType.paymentReceived,
            title: 'Payment successful',
            body: 'Your payment of R250.00 went through.',
            bookingId: 41,
            read: false,
            createdAt: DateTime.now().toUtc(),
          ),
        ],
      );
      when(() => store.unreadCount('student-uid')).thenAnswer((_) async => 1);

      final response = await list_route.onRequest(context);
      expect(response.statusCode, 200);
      final body = await response.json() as Map<String, dynamic>;
      expect(body['unreadCount'], 1);
      final card = (body['notifications'] as List).single as Map;
      expect(card['id'], 'paid-27');
      expect(card['bookingId'], 41);
      expect(card['section'], 'today');
    });

    test('rejects a bad limit', () async {
      request('GET', '/students/notifications?limit=500');
      expect((await list_route.onRequest(context)).statusCode, 400);
    });

    test('only GET is allowed', () async {
      request('DELETE', '/students/notifications');
      expect((await list_route.onRequest(context)).statusCode, 405);
    });
  });

  test('GET unread-count returns the bell number', () async {
    request('GET', '/students/notifications/unread-count');
    when(() => store.unreadCount('student-uid')).thenAnswer((_) async => 2);
    final response = await count_route.onRequest(context);
    expect(await response.json(), {'unreadCount': 2});
  });

  test('POST read-all marks everything read', () async {
    request('POST', '/students/notifications/read-all');
    when(() => store.markAllRead('student-uid')).thenAnswer((_) async => 2);
    when(() => store.unreadCount('student-uid')).thenAnswer((_) async => 0);
    final response = await read_all_route.onRequest(context);
    expect(await response.json(), {'updated': 2, 'unreadCount': 0});
  });

  group('POST /students/notifications/{id}/read', () {
    test('marks the student own notification read', () async {
      request('POST', '/students/notifications/paid-27/read');
      when(
        () => store.markRead('student-uid', 'paid-27'),
      ).thenAnswer((_) async => true);
      when(() => store.unreadCount('student-uid')).thenAnswer((_) async => 0);
      final response = await read_route.onRequest(context, 'paid-27');
      expect(await response.json(), {
        'id': 'paid-27',
        'read': true,
        'unreadCount': 0,
      });
    });

    test('404 when it does not exist', () async {
      request('POST', '/students/notifications/nope/read');
      when(
        () => store.markRead('student-uid', 'nope'),
      ).thenAnswer((_) async => false);
      expect((await read_route.onRequest(context, 'nope')).statusCode, 404);
    });

    test('400 for an invalid id', () async {
      request('POST', '/students/notifications/x/read');
      expect((await read_route.onRequest(context, '../x')).statusCode, 400);
      verifyNever(() => store.markRead(any(), any()));
    });
  });
}
