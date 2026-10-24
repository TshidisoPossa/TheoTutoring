import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/notifications.dart';

const _root = 'projects/demo/databases/(default)/documents';

Map<String, dynamic> _doc(
  String id, {
  bool read = false,
  String createdAt = '2026-10-19T08:00:00.123456789Z',
  Map<String, dynamic>? bookingId,
}) => {
  'name': '$_root/notifications/uid-1/items/$id',
  'fields': {
    'type': {'stringValue': 'NewMessage'},
    'title': {'stringValue': 'New message'},
    'body': {'stringValue': 'You have a new message from Lerato.'},
    'bookingId': bookingId ?? {'nullValue': null},
    'read': {'booleanValue': read},
    'createdAt': {'timestampValue': createdAt},
  },
};

void main() {
  late List<http.Request> requests;

  NotificationStore storeReplying(
    http.Response Function(http.Request request) reply,
  ) {
    requests = [];
    return NotificationStore(
      projectId: 'demo',
      accessToken: () async => 'token-123',
      client: MockClient((request) async {
        requests.add(request);
        return reply(request);
      }),
    );
  }

  group('AppNotification', () {
    test('reads a Firestore document', () {
      final n = AppNotification.fromFirestore(
        _doc('abc', bookingId: {'integerValue': '42'}),
      );
      expect(n.id, 'abc');
      expect(n.type, 'NewMessage');
      expect(n.title, 'New message');
      expect(n.bookingId, 42);
      expect(n.read, isFalse);
      expect(n.createdAt, DateTime.utc(2026, 10, 19, 8, 0, 0, 123, 456));
    });

    test('a null bookingId stays null', () {
      expect(AppNotification.fromFirestore(_doc('abc')).bookingId, isNull);
    });

    test('toJson adds minutesAgo and section', () {
      final n = AppNotification.fromFirestore(_doc('abc'));
      final json = n.toJson(now: n.createdAt.add(const Duration(minutes: 2)));
      expect(json['minutesAgo'], 2);
      expect(json['section'], 'today');
      expect(json['createdAt'], '2026-10-19T08:00:00.123456Z');
    });

    test('sectionFor groups by local date', () {
      final now = DateTime(2026, 10, 19, 9);
      expect(
        AppNotification.sectionFor(DateTime(2026, 10, 19, 0, 5), now),
        'today',
      );
      expect(
        AppNotification.sectionFor(DateTime(2026, 10, 18, 16, 20), now),
        'yesterday',
      );
      expect(
        AppNotification.sectionFor(DateTime(2026, 10, 17, 23), now),
        'earlier',
      );
      // first of the month: yesterday is the last day of last month
      expect(
        AppNotification.sectionFor(
          DateTime(2026, 9, 30, 22),
          DateTime(2026, 10, 1, 8),
        ),
        'yesterday',
      );
    });
  });

  group('NotificationStore', () {
    test('list queries the user items newest first', () async {
      final store = storeReplying(
        (_) => http.Response(
          jsonEncode([
            {'document': _doc('a')},
            {'document': _doc('b', read: true)},
          ]),
          200,
        ),
      );
      final list = await store.list('uid-1', limit: 20);

      expect(list.map((n) => n.id), ['a', 'b']);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer token-123');
      expect(
        request.url.path,
        '/v1/$_root/notifications/uid-1:runQuery',
      );
      final query = (jsonDecode(request.body) as Map)['structuredQuery'] as Map;
      expect(query['from'], [
        {'collectionId': 'items'},
      ]);
      expect(query['limit'], 20);
      expect((query['orderBy'] as List).single, {
        'field': {'fieldPath': 'createdAt'},
        'direction': 'DESCENDING',
      });
    });

    test('list of an empty collection is empty', () async {
      final store = storeReplying(
        (_) => http.Response(
          jsonEncode([
            {'readTime': '2026-10-19T08:00:00Z'},
          ]),
          200,
        ),
      );
      expect(await store.list('uid-1'), isEmpty);
    });

    test('unreadCount reads the count aggregation', () async {
      final store = storeReplying(
        (_) => http.Response(
          jsonEncode([
            {
              'result': {
                'aggregateFields': {
                  'unread': {'integerValue': '3'},
                },
              },
            },
          ]),
          200,
        ),
      );
      expect(await store.unreadCount('uid-1'), 3);
      expect(requests.single.url.path, endsWith(':runAggregationQuery'));
    });

    test('markRead only updates an existing document', () async {
      final store = storeReplying((_) => http.Response('{}', 200));
      expect(await store.markRead('uid-1', 'abc'), isTrue);

      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, '/v1/$_root/notifications/uid-1/items/abc');
      expect(request.url.queryParameters, {
        'updateMask.fieldPaths': 'read',
        'currentDocument.exists': 'true',
      });
    });

    test('markRead returns false when Firestore says 404', () async {
      final store = storeReplying((_) => http.Response('{}', 404));
      expect(await store.markRead('uid-1', 'missing'), isFalse);
    });

    test('markAllRead commits one write per unread document', () async {
      final store = storeReplying(
        (request) => request.url.path.endsWith(':runQuery')
            ? http.Response(
                jsonEncode([
                  {'document': _doc('a')},
                  {'document': _doc('b')},
                ]),
                200,
              )
            : http.Response('{}', 200),
      );
      expect(await store.markAllRead('uid-1'), 2);

      expect(requests, hasLength(2)); // one query, one commit
      expect(requests[1].url.path, '/v1/$_root:commit');
      final writes = (jsonDecode(requests[1].body) as Map)['writes'] as List;
      expect(writes, hasLength(2));
      expect((writes.first as Map)['updateMask'], {
        'fieldPaths': ['read'],
      });
    });

    test('markAllRead with nothing unread does not commit', () async {
      final store = storeReplying(
        (_) => http.Response(jsonEncode([<String, dynamic>{}]), 200),
      );
      expect(await store.markAllRead('uid-1'), 0);
      expect(requests, hasLength(1));
    });

    test('create writes an unread notification', () async {
      final store = storeReplying(
        (request) => http.Response(
          jsonEncode({
            'name': '$_root/notifications/uid-1/items/new-id',
            'fields': (jsonDecode(request.body) as Map)['fields'],
          }),
          200,
        ),
      );
      final n = await store.create(
        uid: 'uid-1',
        type: NotificationType.upcomingSession,
        title: 'Upcoming lesson',
        body: "You're tutoring Lesego in Maths in an hour.",
        bookingId: 7,
      );
      expect(n.id, 'new-id');
      expect(n.read, isFalse);
      expect(n.bookingId, 7);
      expect(requests.single.url.path, '/v1/$_root/notifications/uid-1/items');
    });

    test('createOnce saves under the given id', () async {
      final store = storeReplying((_) => http.Response('{}', 200));
      final created = await store.createOnce(
        id: 'review-12',
        uid: 'uid-1',
        type: NotificationType.newReview,
        title: 'New review',
        body: 'Lerato Dube gave your Maths lesson 5 stars.',
        createdAt: DateTime.utc(2026, 10, 20, 14, 8),
      );
      expect(created, isTrue);
      final request = requests.single;
      expect(request.url.path, '/v1/$_root/notifications/uid-1/items');
      expect(request.url.queryParameters['documentId'], 'review-12');
      final fields = (jsonDecode(request.body) as Map)['fields'] as Map;
      expect(fields['createdAt'], {
        'timestampValue': '2026-10-20T14:08:00.000Z',
      });
      expect(fields['read'], {'booleanValue': false});
    });

    test('createOnce returns false when the id already exists', () async {
      final store = storeReplying(
        (_) => http.Response('{"error":{"status":"ALREADY_EXISTS"}}', 409),
      );
      expect(
        await store.createOnce(
          id: 'upcoming-41-hour',
          uid: 'uid-1',
          type: NotificationType.upcomingSession,
          title: 'Upcoming lesson',
          body: "You're tutoring Lesego in Maths in an hour.",
        ),
        isFalse,
      );
    });

    test('createOnce rejects an id that is not a document id', () {
      final store = storeReplying((_) => http.Response('{}', 200));
      expect(
        () => store.createOnce(
          id: '../x',
          uid: 'uid-1',
          type: NotificationType.newReview,
          title: 't',
          body: 'b',
        ),
        throwsArgumentError,
      );
    });

    test('create rejects an unknown type', () {
      final store = storeReplying((_) => http.Response('{}', 200));
      expect(
        () => store.create(uid: 'u', type: 'Spam', title: 't', body: 'b'),
        throwsArgumentError,
      );
    });

    test('Firestore errors become NotificationServiceException', () {
      final store = storeReplying((_) => http.Response('denied', 403));
      expect(
        store.list('uid-1'),
        throwsA(
          isA<NotificationServiceException>().having(
            (e) => e.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });

    test('isValidId rejects path tricks', () {
      expect(NotificationStore.isValidId('aB3_x-9'), isTrue);
      expect(NotificationStore.isValidId(''), isFalse);
      expect(NotificationStore.isValidId('..'), isFalse);
      expect(NotificationStore.isValidId('a%2Fb'), isFalse);
    });
  });
}
