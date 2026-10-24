import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';

// Every request goes to a scripted fake HTTP client; nothing reaches the
// network. The real-settings guard is checked in a child process.

const _project = 'theo-test';
const _root = 'projects/$_project/databases/(default)/documents';
const _token = 'secret-token-123';
const _updateTime = '2026-10-24T09:41:00.123456789Z';

Uri _prod(String path, [Map<String, String>? query]) =>
    Uri.https('firestore.googleapis.com', '/v1/$path', query);

/// Answers requests from a handler and records them.
class _Fake {
  _Fake(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });

  Map<String, dynamic> body(int i) =>
      jsonDecode(requests[i].body) as Map<String, dynamic>;

  List<String> get operations => [
    for (final r in requests)
      '${r.method} ${r.url.path.substring(r.url.path.lastIndexOf('/') + 1)}',
  ];
}

http.Response _json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

http.Response _error(int code, String status, {String message = 'x'}) => _json({
  'error': {'code': code, 'status': status, 'message': message},
}, code);

Map<String, Object?> _doc(String path, Map<String, Object?> fields) => {
  'name': '$_root/$path',
  'fields': encodeFirestoreFields(fields),
  'createTime': _updateTime,
  'updateTime': _updateTime,
};

/// Answers the transaction calls; [onCommit] decides each commit.
http.Response Function(http.Request) _transactionServer({
  required http.Response Function(int commitNumber) onCommit,
  http.Response Function(int rollbackNumber)? onRollback,
}) {
  var begins = 0;
  var commits = 0;
  var rollbacks = 0;
  return (request) {
    final path = request.url.path;
    if (path.endsWith(':beginTransaction')) {
      begins++;
      return _json({'transaction': 'tx-$begins'});
    }
    if (path.endsWith(':commit')) return onCommit(++commits);
    if (path.endsWith(':rollback')) {
      return onRollback?.call(++rollbacks) ?? _json(<String, Object?>{});
    }
    if (path.endsWith(':batchGet')) {
      return _json([
        {'missing': '$_root/conversations/s1_t2'},
      ]);
    }
    return _error(404, 'NOT_FOUND');
  };
}

http.Response _committed(int writes) => _json({
  'commitTime': '2026-10-24T10:00:00.000001Z',
  'writeResults': [
    for (var i = 0; i < writes; i++) {'updateTime': _updateTime},
  ],
});

FirestoreRest _rest(
  _Fake fake, {
  Uri? baseUri,
  String token = _token,
  List<Duration>? sleeps,
  int maxAttempts = FirestoreRest.defaultMaxAttempts,
  Duration timeout = const Duration(seconds: 15),
  FirestoreEndpoint Function()? extraEndpointCheck,
  String project = _project,
}) => FirestoreRest(
  projectId: project,
  accessToken: () async => token,
  baseUri: baseUri,
  client: fake.client,
  maxAttempts: maxAttempts,
  requestTimeout: timeout,
  sleep: (delay) async => sleeps?.add(delay),
  random: () => 0, // exact waits; jitter is tested on its own
  extraEndpointCheck: extraEndpointCheck,
);

final _emulator = FirestoreEndpoint.resolve(
  processEnvironment: (key) => const {
    firestoreEmulatorHostVariable: '127.0.0.1:8085',
    firestoreEmulatorProjectVariable: 'demo-theotutoring',
  }[key],
  dotEnvFile: (_) => null,
);

/// Requests to production URLs need this machine's real settings to be
/// production mode (the real guard always runs).
final Object _productionSkip = () {
  try {
    return FirestoreEndpoint.resolve().isEmulator
        ? 'Real settings are in Firestore emulator mode'
        : false;
  } on FirestoreEndpointException {
    return 'Real Firestore settings are invalid';
  }
}();

void main() {
  group('value conversion', () {
    final sample = <String, Object?>{
      'none': null,
      'flag': true,
      'count': 9007199254740991,
      'negative': -3,
      'ratio': 0.25,
      'text': 'héllo',
      'when': DateTime.utc(2026, 10, 24, 9, 41, 0, 123, 456),
      'nested': {
        'sent': {'student': 2, 'tutor': 0},
      },
      'list': [
        1,
        'two',
        null,
        <String, Object?>{'x': false},
      ],
      'emptyMap': <String, Object?>{},
      'emptyList': <Object?>[],
    };

    test('round-trips every supported type', () {
      final decoded = decodeFirestoreFields(
        jsonDecode(jsonEncode(encodeFirestoreFields(sample))),
      );
      expect(decoded, sample);
    });

    test('integers are sent as strings, timestamps as UTC', () {
      expect(encodeFirestoreValue(42), {'integerValue': '42'});
      expect(
        encodeFirestoreValue(DateTime.parse('2026-10-24T11:41:00+02:00')),
        {'timestampValue': '2026-10-24T09:41:00.000Z'},
      );
    });

    test('special doubles survive', () {
      expect(
        decodeFirestoreValue(encodeFirestoreValue(double.infinity)),
        double.infinity,
      );
      expect(
        decodeFirestoreValue(encodeFirestoreValue(double.nan)),
        isA<double>().having((d) => d.isNaN, 'isNaN', isTrue),
      );
    });

    test('nanosecond timestamps decode (to microseconds)', () {
      expect(
        decodeFirestoreValue({'timestampValue': _updateTime}),
        DateTime.utc(2026, 10, 24, 9, 41, 0, 123, 456),
      );
    });

    test('integerValue may also arrive as a JSON number', () {
      expect(decodeFirestoreValue({'integerValue': 7}), 7);
    });

    final malformed = <String, Object?>{
      'not a map': 'x',
      'two keys': {'stringValue': 'a', 'integerValue': '1'},
      'bad integer': {'integerValue': 'abc'},
      'bad bool': {'booleanValue': 'true'},
      'non-UTC timestamp': {'timestampValue': '2026-10-24T09:41:00'},
      'bad timestamp': {'timestampValue': 'yesterday'},
      'bad map': {'mapValue': 'x'},
      'bad array': {
        'arrayValue': {'values': 'x'},
      },
      'unsupported bytes': {'bytesValue': 'AAAA'},
      'unsupported reference': {'referenceValue': 'projects/x'},
    };
    for (final MapEntry(key: name, value: json) in malformed.entries) {
      test('rejects $name', () {
        expect(
          () => decodeFirestoreValue(json),
          throwsA(isA<FirestoreFormatException>()),
        );
      });
    }

    test('rejects unsupported Dart values and nested arrays', () {
      expect(() => encodeFirestoreValue(Object()), throwsArgumentError);
      expect(
        () => encodeFirestoreValue([
          [1],
        ]),
        throwsArgumentError,
      );
      expect(
        () => encodeFirestoreValue({1: 'non-string key'}),
        throwsArgumentError,
      );
    });
  });

  group('paths', () {
    final fake = _Fake((_) => _json(<String, Object?>{}));

    for (final path in [
      '',
      'conversations',
      'conversations/s1_t2/messages',
      '../conversations/x',
      'conversations/..',
      'conversations/a b',
      'conversations/a%2Fb',
      'conversations/a.b',
      'conversations//x',
    ]) {
      test('rejects "$path" without sending anything', () async {
        final rest = _rest(fake);
        await expectLater(rest.get(path), throwsArgumentError);
        expect(fake.requests, isEmpty);
      });
    }

    test('accepts document paths used by chat', () {
      final rest = _rest(fake);
      expect(
        rest.documentName('conversations/s1_t2/messages/9-abc_DEF'),
        '$_root/conversations/s1_t2/messages/9-abc_DEF',
      );
      expect(
        rest.documentName('system/chatConfig'),
        '$_root/system/chatConfig',
      );
    });

    test('rejects invalid field paths in masks and transforms', () async {
      final rest = _rest(fake);
      await expectLater(
        rest.commit([
          const FirestoreWrite.update('a/b', {}, updateMask: ['bad path']),
        ]),
        throwsArgumentError,
      );
      await expectLater(
        rest.commit([
          const FirestoreWrite.update(
            'a/b',
            {},
            transforms: [FirestoreTransform.serverTime('x.`y`')],
          ),
        ]),
        throwsArgumentError,
      );
      expect(fake.requests, isEmpty);
    });
  });

  group('request shapes (production)', () {
    test('get: URL, token, transaction and decoded fields', () async {
      final fake = _Fake(
        (_) => _json(_doc('conversations/s1_t2', {'lastSeq': 3})),
      );
      final doc = await _rest(fake).get(
        'conversations/s1_t2',
        transaction: 'tx-1',
      );

      final request = fake.requests.single;
      expect(request.method, 'GET');
      expect(
        request.url,
        _prod('$_root/conversations/s1_t2', {'transaction': 'tx-1'}),
      );
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(doc!.path, 'conversations/s1_t2');
      expect(doc.fields, {'lastSeq': 3});
      expect(doc.updateTime, _updateTime);
    });

    test('get returns null for a missing document', () async {
      final fake = _Fake((_) => _error(404, 'NOT_FOUND'));
      expect(await _rest(fake).get('system/chatConfig'), isNull);
    });

    test('get rejects a different document than asked for', () async {
      final fake = _Fake((_) => _json(_doc('system/other', {})));
      await expectLater(
        _rest(fake).get('system/chatConfig'),
        throwsA(isA<FirestoreFormatException>()),
      );
    });

    test('batchGet: body, found and missing, every path answered', () async {
      final fake = _Fake(
        (_) => _json([
          {
            'found': _doc('system/chatConfig', {'enabled': true}),
          },
          {'missing': '$_root/conversations/s1_t2'},
          {'transaction': 'tx-1'},
        ]),
      );
      final docs = await _rest(fake).batchGet([
        'system/chatConfig',
        'conversations/s1_t2',
      ], transaction: 'tx-1');

      expect(fake.requests.single.url, _prod('$_root:batchGet'));
      expect(fake.body(0), {
        'documents': ['$_root/system/chatConfig', '$_root/conversations/s1_t2'],
        'transaction': 'tx-1',
      });
      expect(docs.keys, ['system/chatConfig', 'conversations/s1_t2']);
      expect(docs['system/chatConfig']!.fields, {'enabled': true});
      expect(docs['conversations/s1_t2'], isNull);
    });

    final badBatches = <String, Object?>{
      'not a list': {'found': 1},
      'a missing answer': [
        {'found': _doc('system/chatConfig', {})},
      ],
      'an unrequested document': [
        {'found': _doc('system/chatConfig', {})},
        {'found': _doc('system/other', {})},
      ],
      'an unrequested missing name': [
        {'found': _doc('system/chatConfig', {})},
        {'missing': '$_root/system/other'},
      ],
      'a document without updateTime': [
        {
          'found': {'name': '$_root/system/chatConfig'},
        },
        {'missing': '$_root/conversations/s1_t2'},
      ],
    };
    for (final MapEntry(key: name, value: body) in badBatches.entries) {
      test('batchGet rejects $name', () async {
        final fake = _Fake((_) => _json(body));
        await expectLater(
          _rest(fake).batchGet(['system/chatConfig', 'conversations/s1_t2']),
          throwsA(isA<FirestoreFormatException>()),
        );
      });
    }

    test('runQuery: parent URL, body, skips the empty-result row', () async {
      final fake = _Fake(
        (_) => _json([
          {
            'document': _doc('conversations/s1_t2/messages/9-a', {'seq': 1}),
          },
          {'readTime': _updateTime},
        ]),
      );
      final query = {
        'from': [
          {'collectionId': 'messages'},
        ],
        'limit': 100,
      };
      final docs = await _rest(fake).runQuery(
        query,
        parent: 'conversations/s1_t2',
        transaction: 'tx-1',
      );

      expect(
        fake.requests.single.url,
        _prod('$_root/conversations/s1_t2:runQuery'),
      );
      expect(fake.body(0), {'structuredQuery': query, 'transaction': 'tx-1'});
      expect(docs.single.path, 'conversations/s1_t2/messages/9-a');
    });

    test('runQuery on the root and an empty result', () async {
      final fake = _Fake(
        (_) => _json([
          {'readTime': _updateTime},
        ]),
      );
      expect(await _rest(fake).runQuery(const {}), isEmpty);
      expect(fake.requests.single.url, _prod('$_root:runQuery'));
      expect(fake.body(0).containsKey('transaction'), isFalse);
    });

    test('runQuery rejects documents outside the parent', () async {
      final fake = _Fake(
        (_) => _json([
          {'document': _doc('conversations/s9_t9/messages/x-y', {})},
        ]),
      );
      await expectLater(
        _rest(fake).runQuery(const {}, parent: 'conversations/s1_t2'),
        throwsA(isA<FirestoreFormatException>()),
      );
    });

    test('delete sends the precondition as query parameters', () async {
      final fake = _Fake((_) => _json(<String, Object?>{}));
      final rest = _rest(fake);
      await rest.delete(
        'chatOutbox/r_s1_t2_student',
        precondition: const FirestorePrecondition.updateTime(_updateTime),
      );
      await rest.delete(
        'chatOutbox/m_x',
        precondition: FirestorePrecondition.mustExist,
      );
      await rest.delete('chatOutbox/n_x');

      expect(fake.requests.map((r) => r.method), everyElement('DELETE'));
      expect(fake.requests.map((r) => r.url), [
        _prod('$_root/chatOutbox/r_s1_t2_student', {
          'currentDocument.updateTime': _updateTime,
        }),
        _prod('$_root/chatOutbox/m_x', {'currentDocument.exists': 'true'}),
        _prod('$_root/chatOutbox/n_x'),
      ]);
    });

    test('commit: writes, masks, transforms and preconditions', () async {
      final fake = _Fake((_) => _committed(3));
      final result = await _rest(fake).commit([
        const FirestoreWrite.update(
          'conversations/s1_t2/messages/9-abc',
          {'seq': 1, 'text': 'Hi'},
          transforms: [FirestoreTransform.serverTime('sentAt')],
          precondition: FirestorePrecondition.mustNotExist,
        ),
        const FirestoreWrite.update(
          'conversations/s1_t2',
          {'lastSeq': 1},
          updateMask: ['lastSeq', 'sent.student'],
          transforms: [FirestoreTransform.increment('sent.student', 1)],
          precondition: FirestorePrecondition.updateTime(_updateTime),
        ),
        const FirestoreWrite.delete(
          'chatOutbox/m_x',
          precondition: FirestorePrecondition.mustExist,
        ),
      ], transaction: 'tx-1');

      expect(fake.requests.single.url, _prod('$_root:commit'));
      expect(fake.body(0), {
        'writes': [
          {
            'update': {
              'name': '$_root/conversations/s1_t2/messages/9-abc',
              'fields': {
                'seq': {'integerValue': '1'},
                'text': {'stringValue': 'Hi'},
              },
            },
            'updateTransforms': [
              {'fieldPath': 'sentAt', 'setToServerValue': 'REQUEST_TIME'},
            ],
            'currentDocument': {'exists': false},
          },
          {
            'update': {
              'name': '$_root/conversations/s1_t2',
              'fields': {
                'lastSeq': {'integerValue': '1'},
              },
            },
            'updateMask': {
              'fieldPaths': ['lastSeq', 'sent.student'],
            },
            'updateTransforms': [
              {
                'fieldPath': 'sent.student',
                'increment': {'integerValue': '1'},
              },
            ],
            'currentDocument': {'updateTime': _updateTime},
          },
          {
            'delete': '$_root/chatOutbox/m_x',
            'currentDocument': {'exists': true},
          },
        ],
        'transaction': 'tx-1',
      });
      expect(result.commitTime, '2026-10-24T10:00:00.000001Z');
      expect(result.committedAt, DateTime.utc(2026, 10, 24, 10, 0, 0, 0, 1));
      expect(result.updateTimes, [_updateTime, _updateTime, _updateTime]);
    });

    test('commit rejects a malformed response', () async {
      for (final body in [
        <String, Object?>{},
        {'commitTime': 'soon', 'writeResults': <Object?>[]},
        {
          'commitTime': _updateTime,
          'writeResults': <Object?>[],
        }, // one write expected
      ]) {
        final fake = _Fake((_) => _json(body));
        await expectLater(
          _rest(fake).commit([const FirestoreWrite.delete('a/b')]),
          throwsA(isA<FirestoreFormatException>()),
          reason: '$body',
        );
      }
    });

    test('beginTransaction and rollback bodies', () async {
      final fake = _Fake(
        (request) => request.url.path.endsWith(':beginTransaction')
            ? _json({'transaction': 'tx-9'})
            : _json(<String, Object?>{}),
      );
      final rest = _rest(fake);
      expect(await rest.beginTransaction(), 'tx-9');
      expect(await rest.beginTransaction(retrying: 'tx-8'), 'tx-9');
      await rest.rollback('tx-9');

      expect(fake.body(0), {
        'options': {'readWrite': <String, Object?>{}},
      });
      expect(fake.body(1), {
        'options': {
          'readWrite': {'retryTransaction': 'tx-8'},
        },
      });
      expect(fake.requests[2].url, _prod('$_root:rollback'));
      expect(fake.body(2), {'transaction': 'tx-9'});
    });

    test('beginTransaction without an id is malformed', () async {
      final fake = _Fake((_) => _json({'transaction': ''}));
      await expectLater(
        _rest(fake).beginTransaction(),
        throwsA(isA<FirestoreFormatException>()),
      );
    });
  }, skip: _productionSkip);

  group('HTTP error mapping', () {
    final cases = <String, (http.Response, Matcher)>{
      '409 ABORTED': (
        _error(409, 'ABORTED'),
        isA<FirestoreConflict>().having((e) => e.isAborted, 'isAborted', true),
      ),
      '409 ALREADY_EXISTS': (
        _error(409, 'ALREADY_EXISTS'),
        isA<FirestoreConflict>().having((e) => e.isAborted, 'isAborted', false),
      ),
      '400 FAILED_PRECONDITION': (
        _error(400, 'FAILED_PRECONDITION'),
        isA<FirestoreConflict>(),
      ),
      '400 INVALID_ARGUMENT': (
        _error(400, 'INVALID_ARGUMENT'),
        isA<FirestoreBadRequest>(),
      ),
      '401': (_error(401, 'UNAUTHENTICATED'), isA<FirestorePermissionDenied>()),
      '403': (
        _error(403, 'PERMISSION_DENIED'),
        isA<FirestorePermissionDenied>(),
      ),
      '429': (_error(429, 'RESOURCE_EXHAUSTED'), isA<FirestoreUnavailable>()),
      '503': (_error(503, 'UNAVAILABLE'), isA<FirestoreUnavailable>()),
      '500 without JSON': (
        http.Response('<html>oops</html>', 500),
        isA<FirestoreUnavailable>().having((e) => e.status, 'status', isNull),
      ),
      '418': (http.Response('', 418), isA<FirestoreException>()),
      '200 that is not JSON': (
        http.Response('not json', 200),
        isA<FirestoreFormatException>(),
      ),
    };
    for (final MapEntry(key: name, value: (response, matcher))
        in cases.entries) {
      test(name, () async {
        final fake = _Fake((_) => response);
        await expectLater(
          _rest(fake).commit(const []),
          throwsA(matcher),
        );
      });
    }

    test('messages never include the token or response body', () async {
      final fake = _Fake(
        (_) => _error(403, 'PERMISSION_DENIED', message: 'body-sentinel'),
      );
      try {
        await _rest(fake).commit(const []);
        fail('expected an error');
      } on FirestoreException catch (e) {
        expect('$e', isNot(contains(_token)));
        expect('$e', isNot(contains('body-sentinel')));
        expect('$e', contains('HTTP 403 PERMISSION_DENIED'));
      }
    });

    test('an odd status name is not trusted', () async {
      final fake = _Fake((_) => _error(400, 'not a status <script>'));
      await expectLater(
        _rest(fake).commit(const []),
        throwsA(
          isA<FirestoreBadRequest>().having((e) => e.status, 'status', isNull),
        ),
      );
    });

    test('network errors are unavailable', () async {
      final fake = _Fake((_) => throw const SocketException('refused'));
      await expectLater(
        _rest(fake).commit(const []),
        throwsA(isA<FirestoreUnavailable>()),
      );
    });

    test('slow responses time out as unavailable', () async {
      final never = Completer<http.Response>();
      final fake = _Fake((_) => never.future);
      await expectLater(
        _rest(fake, timeout: const Duration(milliseconds: 10)).commit(const []),
        throwsA(isA<FirestoreUnavailable>()),
      );
    });

    test(
      'a token failure is unavailable; a setup failure passes through',
      () async {
        final fake = _Fake((_) => _json(<String, Object?>{}));
        final broken = FirestoreRest(
          projectId: _project,
          accessToken: () async => throw Exception('$_token leaked?'),
          client: fake.client,
        );
        final notSetUp = FirestoreRest(
          projectId: _project,
          accessToken: () async =>
              throw const FirebaseAdminException('not set up'),
          client: fake.client,
        );
        await expectLater(
          broken.commit(const []),
          throwsA(
            isA<FirestoreUnavailable>().having(
              (e) => '$e',
              'text',
              isNot(contains(_token)),
            ),
          ),
        );
        await expectLater(
          notSetUp.commit(const []),
          throwsA(isA<FirebaseAdminException>()),
        );
        expect(fake.requests, isEmpty);
      },
    );
  }, skip: _productionSkip);

  group('runTransaction', () {
    test('retry waits get bounded random jitter', () async {
      expect(
        FirestoreRest.jitteredBackoffFor(1, 0),
        FirestoreRest.backoffFor(1),
      );
      expect(
        FirestoreRest.jitteredBackoffFor(1, 0.999),
        const Duration(milliseconds: 99),
      );
      // Never more than one second.
      expect(
        FirestoreRest.jitteredBackoffFor(5, 0.999),
        const Duration(seconds: 1),
      );
      expect(
        FirestoreRest.jitteredBackoffFor(30, 0.5),
        const Duration(seconds: 1),
      );

      final fake = _Fake(
        _transactionServer(
          onCommit: (n) => n < 4 ? _error(409, 'ABORTED') : _committed(1),
        ),
      );
      final sleeps = <Duration>[];
      await FirestoreRest(
        projectId: _project,
        accessToken: () async => _token,
        client: fake.client,
        sleep: (d) async => sleeps.add(d),
        random: () => 0.5,
      ).runTransaction(
        (tx) => tx.commit([const FirestoreWrite.delete('a/b')]),
      );
      expect(sleeps, const [
        Duration(milliseconds: 75),
        Duration(milliseconds: 150),
        Duration(milliseconds: 300),
      ]);
    });

    test('commits once, inside the transaction, without a rollback', () async {
      final fake = _Fake(_transactionServer(onCommit: (_) => _committed(1)));
      final result = await _rest(fake).runTransaction((tx) async {
        final docs = await tx.batchGet(['conversations/s1_t2']);
        expect(docs['conversations/s1_t2'], isNull);
        await tx.commit([
          const FirestoreWrite.update(
            'conversations/s1_t2',
            {'lastSeq': 1},
            precondition: FirestorePrecondition.mustNotExist,
          ),
        ]);
        return 'done';
      });

      expect(result, 'done');
      expect(fake.operations, [
        'POST documents:beginTransaction',
        'POST documents:batchGet',
        'POST documents:commit',
      ]);
      expect(fake.body(1)['transaction'], 'tx-1');
      expect(fake.body(2)['transaction'], 'tx-1');
    });

    test('a body that does not commit is rolled back', () async {
      final fake = _Fake(_transactionServer(onCommit: (_) => _committed(0)));
      final value = await _rest(fake).runTransaction((tx) async => 7);
      expect(value, 7);
      expect(fake.operations.last, 'POST documents:rollback');
      expect(fake.body(1), {'transaction': 'tx-1'});
    });

    test('other errors are rolled back and not retried', () async {
      final fake = _Fake(_transactionServer(onCommit: (_) => _committed(0)));
      await expectLater(
        _rest(fake).runTransaction<void>(
          (tx) async => throw StateError('bug'),
        ),
        throwsStateError,
      );
      expect(fake.operations, [
        'POST documents:beginTransaction',
        'POST documents:rollback',
      ]);
    });

    test(
      'aborts and conflicts are retried with backoff and priority',
      () async {
        final responses = [
          _error(409, 'ABORTED'),
          _error(400, 'FAILED_PRECONDITION'),
          _error(404, 'NOT_FOUND'), // a failed "must exist" precondition
          _committed(1),
        ];
        final fake = _Fake(
          _transactionServer(onCommit: (n) => responses[n - 1]),
        );
        final sleeps = <Duration>[];
        var attempts = 0;
        final result = await _rest(fake, sleeps: sleeps).runTransaction((
          tx,
        ) async {
          attempts++;
          await tx.commit([const FirestoreWrite.delete('a/b')]);
          return attempts;
        });

        expect(result, 4);
        expect(sleeps, const [
          Duration(milliseconds: 50),
          Duration(milliseconds: 100),
          Duration(milliseconds: 200),
        ]);
        final begins = [
          for (var i = 0; i < fake.requests.length; i++)
            if (fake.requests[i].url.path.endsWith(':beginTransaction'))
              fake.body(i),
        ];
        expect(begins.map((b) => (b['options'] as Map)['readWrite']), [
          <String, Object?>{},
          {'retryTransaction': 'tx-1'},
          {'retryTransaction': 'tx-2'},
          {'retryTransaction': 'tx-3'},
        ]);
      },
    );

    test('gives up after maxAttempts and cleans up every attempt', () async {
      final fake = _Fake(
        _transactionServer(
          onCommit: (_) => _error(409, 'ABORTED'),
          onRollback: (_) => _error(400, 'INVALID_ARGUMENT'),
        ),
      );
      final sleeps = <Duration>[];
      var attempts = 0;
      await expectLater(
        _rest(fake, sleeps: sleeps, maxAttempts: 3).runTransaction((
          tx,
        ) async {
          attempts++;
          await tx.commit([const FirestoreWrite.delete('a/b')]);
        }),
        throwsA(
          isA<FirestoreRetryExhausted>().having(
            (e) => e.attempts,
            'attempts',
            3,
          ),
        ),
      );
      expect(attempts, 3);
      expect(sleeps, hasLength(2));
      // Each failed attempt is rolled back, even though rollback fails.
      expect(
        fake.operations.where((o) => o.endsWith(':rollback')),
        hasLength(3),
      );
    });

    test('an abort while reading is retried too', () async {
      var reads = 0;
      final fake = _Fake((request) {
        final path = request.url.path;
        if (path.endsWith(':beginTransaction')) {
          return _json({'transaction': 'tx-${++reads}'});
        }
        if (path.endsWith(':batchGet')) {
          return reads == 1
              ? _error(409, 'ABORTED')
              : _json([
                  {'missing': '$_root/system/chatConfig'},
                ]);
        }
        return _json(<String, Object?>{});
      });
      final doc = await _rest(fake, sleeps: []).runTransaction(
        (tx) async => (await tx.batchGet(['system/chatConfig'])).values.single,
      );
      expect(doc, isNull);
      expect(reads, 2);
    });

    test('non-retryable commit errors surface after one attempt', () async {
      final fake = _Fake(
        _transactionServer(onCommit: (_) => _error(403, 'PERMISSION_DENIED')),
      );
      var attempts = 0;
      await expectLater(
        _rest(fake).runTransaction((tx) async {
          attempts++;
          await tx.commit([const FirestoreWrite.delete('a/b')]);
        }),
        throwsA(isA<FirestorePermissionDenied>()),
      );
      expect(attempts, 1);
      expect(fake.operations.last, 'POST documents:rollback');
    });

    test('a transaction can only commit once and not be reused', () async {
      final fake = _Fake(_transactionServer(onCommit: (_) => _committed(0)));
      await _rest(fake).runTransaction((tx) async {
        await tx.commit(const []);
        expect(() => tx.commit(const []), throwsStateError);
        expect(() => tx.get('a/b'), throwsStateError);
      });
      expect(fake.operations.where((o) => o.endsWith(':commit')), hasLength(1));
      expect(fake.operations.where((o) => o.endsWith(':rollback')), isEmpty);
    });
  }, skip: _productionSkip);

  group('emulator target', () {
    test('an emulator client sends only to 127.0.0.1:8085 with the emulator '
        'token', () async {
      final fake = _Fake(
        (_) => _json(_docIn('demo-theotutoring', 'system/chatConfig')),
      );
      final rest = _rest(
        fake,
        baseUri: _emulator.baseUri,
        token: _emulator.accessToken!,
        project: _emulator.projectId!,
        extraEndpointCheck: () => _emulator,
      );
      await rest.get('system/chatConfig');

      final request = fake.requests.single;
      expect(
        request.url,
        Uri.http(
          '127.0.0.1:8085',
          '/v1/projects/demo-theotutoring/databases/(default)/documents/'
              'system/chatConfig',
        ),
      );
      expect(request.headers['Authorization'], 'Bearer owner');
    });

    test('in emulator mode a production-addressed client is refused before '
        'the token is asked for', () async {
      final fake = _Fake((_) => _json(<String, Object?>{}));
      var tokenRequested = false;
      final rest = FirestoreRest(
        projectId: 'demo-theotutoring',
        accessToken: () async {
          tokenRequested = true;
          return _token;
        },
        client: fake.client,
        extraEndpointCheck: () => _emulator,
      );
      for (final call in <Future<Object?> Function()>[
        () => rest.get('system/chatConfig'),
        () => rest.batchGet(['system/chatConfig']),
        () => rest.runQuery(const {}),
        () => rest.delete('chatOutbox/x'),
        rest.beginTransaction,
        () => rest.commit(const []),
        () => rest.rollback('tx'),
        () => rest.runTransaction((tx) async => null),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<FirebaseAdminException>().having(
              (e) => e.message,
              'message',
              contains('emulator mode is on'),
            ),
          ),
        );
      }
      expect(fake.requests, isEmpty);
      expect(tokenRequested, isFalse);
    });

    test(
      'the real settings guard applies to every client (child process)',
      () async {
        final steps = await _runRealSettingsProbe({
          firestoreEmulatorHostVariable: '127.0.0.1:8085',
          firestoreEmulatorProjectVariable: 'demo-theotutoring',
        });
        final emulatorUrl = Uri.http(
          '127.0.0.1:8085',
          '/v1/projects/demo-theotutoring/databases/(default)/documents/'
              'system/chatConfig',
        );
        expect(steps['fromEnvironment'], 'SENT $emulatorUrl emulator-token');
        expect(steps['productionClient'], 'REFUSED requests=0');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, skip: _invalidSettingsSkip);
}

Map<String, Object?> _docIn(String project, String path) => {
  'name': 'projects/$project/databases/(default)/documents/$path',
  'fields': <String, Object?>{},
  'updateTime': _updateTime,
};

final Object _invalidSettingsSkip = () {
  try {
    FirestoreEndpoint.resolve();
    return false;
  } on FirestoreEndpointException {
    return 'Real Firestore settings are invalid';
  }
}();

/// Runs a probe in a child process with [environment] added (the real
/// settings cannot change inside this process). The probe is written to a
/// temporary folder, uses only fake HTTP clients, and never prints a token
/// other than the emulator's fixed one.
Future<Map<String, String>> _runRealSettingsProbe(
  Map<String, String> environment,
) async {
  final dir = Directory.systemTemp.createTempSync('firestore_rest_probe');
  try {
    final probe = File('${dir.path}${Platform.pathSeparator}probe.dart')
      ..writeAsStringSync(_probeSource);
    final packages = File(
      '${Directory.current.path}/.dart_tool/package_config.json',
    ).absolute.path;
    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=$packages',
      probe.path,
    ], environment: environment);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return {
      for (final line in LineSplitter.split(result.stdout as String))
        if (line.contains(': '))
          line.substring(0, line.indexOf(': ')): line.substring(
            line.indexOf(': ') + 2,
          ),
    };
  } finally {
    dir.deleteSync(recursive: true);
  }
}

const _probeSource = r'''
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';

Future<void> main() async {
  final seen = <http.Request>[];
  final client = MockClient((request) async {
    seen.add(request);
    return http.Response('{"error":{"code":404,"status":"NOT_FOUND"}}', 404);
  });

  try {
    await FirestoreRest.fromEnvironment(client: client)
        .get('system/chatConfig');
    final r = seen.single;
    final auth = r.headers['Authorization'] == 'Bearer owner'
        ? 'emulator-token'
        : 'other-token';
    stdout.writeln('fromEnvironment: SENT ${r.url} $auth');
  } on FirebaseAdminException catch (e) {
    stdout.writeln('fromEnvironment: REFUSED ${e.message}');
  }

  seen.clear();
  try {
    await FirestoreRest(
      projectId: 'demo-theotutoring',
      accessToken: () async => 'owner',
      client: client,
    ).get('system/chatConfig');
    stdout.writeln('productionClient: SENT');
  } on FirebaseAdminException {
    stdout.writeln('productionClient: REFUSED requests=${seen.length}');
  }
}
''';
