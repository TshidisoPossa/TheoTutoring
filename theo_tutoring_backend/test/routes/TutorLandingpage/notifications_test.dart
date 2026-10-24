import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/notifications.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/notifications/[id]/read.dart'
    as read_route;
import '../../../routes/TutorLandingpage/notifications/index.dart'
    as list_route;
import '../../../routes/TutorLandingpage/notifications/read-all.dart'
    as read_all_route;
import '../../../routes/TutorLandingpage/notifications/unread-count.dart'
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
    when(() => context.read<TutorSession>()).thenReturn(
      const TutorSession('uid-1', 5),
    );
    when(() => context.read<NotificationStore>()).thenReturn(store);
  });

  group('GET /TutorLandingpage/notifications', () {
    test('returns the notifications and the unread count', () async {
      request('GET', '/TutorLandingpage/notifications');
      when(() => store.list('uid-1', limit: any(named: 'limit'))).thenAnswer(
        (_) async => [
          AppNotification(
            id: 'a',
            type: NotificationType.newMessage,
            title: 'New message',
            body: 'You have a new message from Lerato.',
            read: false,
            createdAt: DateTime.now().toUtc(),
          ),
        ],
      );
      when(() => store.unreadCount('uid-1')).thenAnswer((_) async => 3);

      final response = await list_route.onRequest(context);
      expect(response.statusCode, 200);
      final body = await response.json() as Map<String, dynamic>;
      expect(body['unreadCount'], 3);
      expect(body['count'], 1);
      final card = (body['notifications'] as List).single as Map;
      expect(card['id'], 'a');
      expect(card['title'], 'New message');
      expect(card['section'], 'today');
    });

    test('rejects a bad limit', () async {
      request('GET', '/TutorLandingpage/notifications?limit=0');
      final response = await list_route.onRequest(context);
      expect(response.statusCode, 400);
      verifyNever(() => store.list(any(), limit: any(named: 'limit')));
    });

    test('only GET is allowed', () async {
      request('POST', '/TutorLandingpage/notifications');
      expect((await list_route.onRequest(context)).statusCode, 405);
    });
  });

  test('GET unread-count returns the bell number', () async {
    request('GET', '/TutorLandingpage/notifications/unread-count');
    when(() => store.unreadCount('uid-1')).thenAnswer((_) async => 4);

    final response = await count_route.onRequest(context);
    expect(await response.json(), {'unreadCount': 4});
  });

  test('POST read-all marks everything read', () async {
    request('POST', '/TutorLandingpage/notifications/read-all');
    when(() => store.markAllRead('uid-1')).thenAnswer((_) async => 3);
    when(() => store.unreadCount('uid-1')).thenAnswer((_) async => 0);

    final response = await read_all_route.onRequest(context);
    expect(await response.json(), {'updated': 3, 'unreadCount': 0});
  });

  group('POST /TutorLandingpage/notifications/{id}/read', () {
    test('marks the tutor own notification read', () async {
      request('POST', '/TutorLandingpage/notifications/abc/read');
      when(() => store.markRead('uid-1', 'abc')).thenAnswer((_) async => true);
      when(() => store.unreadCount('uid-1')).thenAnswer((_) async => 2);

      final response = await read_route.onRequest(context, 'abc');
      expect(response.statusCode, 200);
      expect(await response.json(), {
        'id': 'abc',
        'read': true,
        'unreadCount': 2,
      });
    });

    test('404 when it does not exist', () async {
      request('POST', '/TutorLandingpage/notifications/nope/read');
      when(
        () => store.markRead('uid-1', 'nope'),
      ).thenAnswer((_) async => false);

      final response = await read_route.onRequest(context, 'nope');
      expect(response.statusCode, 404);
    });

    test('400 for an invalid id', () async {
      request('POST', '/TutorLandingpage/notifications/x/read');
      final response = await read_route.onRequest(context, '..');
      expect(response.statusCode, 400);
      verifyNever(() => store.markRead(any(), any()));
    });
  });
}
