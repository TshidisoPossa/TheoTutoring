import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Where NotificationStore sends its requests, checked with a fake HTTP
// client: no network, no service account (stores are built directly).

/// Answers every Firestore call NotificationStore makes and records it.
class _FakeFirestore {
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith(':runAggregationQuery')) {
      return _json([
        {
          'result': {
            'aggregateFields': {
              'unread': {'integerValue': '2'},
            },
          },
        },
      ]);
    }
    if (path.endsWith(':runQuery')) {
      // A runQuery with a filter is markAllRead's search for unread items.
      final query = jsonDecode(request.body) as Map<String, dynamic>;
      final structured = query['structuredQuery'] as Map<String, dynamic>;
      return _json(
        structured.containsKey('where')
            ? [
                {
                  'document': {'name': '${_itemsOf(path)}/n1'},
                },
              ]
            : <Object>[],
      );
    }
    if (path.endsWith(':commit')) return _json(<String, Object>{});
    if (request.method == 'PATCH') return _json(<String, Object>{});
    if (request.method == 'POST' && path.endsWith('/items')) {
      return _json({
        'name': '${path.substring('/v1/'.length)}/new1',
        'fields': <String, Object>{},
      });
    }
    return http.Response('unexpected ${request.method} $path', 404);
  });

  static String _itemsOf(String runQueryPath) =>
      '${runQueryPath.substring('/v1/'.length, runQueryPath.indexOf(':'))}'
      '/items';

  static http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200);
}

/// Calls every NotificationStore method once, in a fixed order.
Future<void> _useEveryMethod(NotificationStore store, String uid) async {
  await store.list(uid);
  await store.unreadCount(uid);
  await store.markRead(uid, 'n1');
  await store.markAllRead(uid);
  await store.create(
    uid: uid,
    type: NotificationType.newMessage,
    title: 'New message',
    body: 'You have a new message.',
  );
}

/// The paths (after /v1/) and queries of [_useEveryMethod], in order.
List<(String, Map<String, String>?)> _expectedCalls(
  String project,
  String uid,
) {
  final parent =
      'projects/$project/databases/(default)/documents/notifications/'
      '${Uri.encodeComponent(uid)}';
  return [
    ('$parent:runQuery', null),
    ('$parent:runAggregationQuery', null),
    (
      '$parent/items/n1',
      {'updateMask.fieldPaths': 'read', 'currentDocument.exists': 'true'},
    ),
    ('$parent:runQuery', null),
    ('projects/$project/databases/(default)/documents:commit', null),
    ('$parent/items', null),
  ];
}

SettingLookup _lookup(Map<String, String> values) =>
    (key) => values[key];

final _emulator = FirestoreEndpoint.resolve(
  processEnvironment: _lookup({
    firestoreEmulatorHostVariable: '127.0.0.1:8085',
    firestoreEmulatorProjectVariable: 'demo-theotutoring',
  }),
  dotEnvFile: _lookup(const {}),
);

/// Every store request checks the real settings first, so these tests need
/// this machine's settings to be valid; production-target tests also need
/// them to be production mode.
final Object _productionSkip = () {
  try {
    return FirestoreEndpoint.resolve().isEmulator
        ? 'Real settings are in Firestore emulator mode'
        : false;
  } on FirestoreEndpointException {
    return 'Real Firestore settings are invalid';
  }
}();

/// Requests to the emulator are allowed in both modes, so the emulator-store
/// test only needs the real settings to be valid.
final Object _invalidSettingsSkip = () {
  try {
    FirestoreEndpoint.resolve();
    return false;
  } on FirestoreEndpointException {
    return 'Real Firestore settings are invalid';
  }
}();

void main() {
  group('production store', () {
    test('defaults to production Firestore', () {
      final store = NotificationStore(
        projectId: 'theo-test',
        accessToken: () async => 'prod-token',
      );
      expect(store.baseUri, Uri.https('firestore.googleapis.com'));
    });

    test('every request uses the same URLs as before and the service-account '
        'token', () async {
      final fake = _FakeFirestore();
      final store = NotificationStore(
        projectId: 'theo-test',
        accessToken: () async => 'prod-token',
        client: fake.client,
      );

      await _useEveryMethod(store, 'uid-1');

      expect(fake.requests.map((r) => r.url), [
        // The pre-change formula, so any difference is a regression.
        for (final (path, query) in _expectedCalls('theo-test', 'uid-1'))
          Uri.https('firestore.googleapis.com', '/v1/$path', query),
      ]);
      for (final request in fake.requests) {
        expect(request.headers['Authorization'], 'Bearer prod-token');
      }
    });

    test('user ids are encoded exactly as before', () async {
      final fake = _FakeFirestore();
      final store = NotificationStore(
        projectId: 'theo-test',
        accessToken: () async => 'prod-token',
        client: fake.client,
      );

      await store.list('a b/c?d');

      expect(
        fake.requests.single.url,
        Uri.https(
          'firestore.googleapis.com',
          '/v1/projects/theo-test/databases/(default)/documents/'
              'notifications/${Uri.encodeComponent('a b/c?d')}:runQuery',
        ),
      );
    });
  }, skip: _productionSkip);

  group('emulator store', () {
    test('every request goes only to 127.0.0.1:8085 with the emulator '
        'token', () async {
      final fake = _FakeFirestore();
      final store = NotificationStore(
        projectId: _emulator.projectId!,
        accessToken: () async => _emulator.accessToken!,
        client: fake.client,
        baseUri: _emulator.baseUri,
      );

      await _useEveryMethod(store, 'uid-1');

      expect(fake.requests.map((r) => r.url), [
        for (final (path, query) in _expectedCalls(
          'demo-theotutoring',
          'uid-1',
        ))
          Uri.http('127.0.0.1:8085', '/v1/$path', query),
      ]);
      for (final request in fake.requests) {
        expect(request.url.scheme, 'http');
        expect(request.url.host, '127.0.0.1');
        expect(request.url.port, 8085);
        expect(request.headers['Authorization'], 'Bearer owner');
      }
    });
  }, skip: _invalidSettingsSkip);
}
