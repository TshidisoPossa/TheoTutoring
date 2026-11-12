import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_subjects_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/admin_subject_models.dart';
import 'package:theo_tutoring_app/config/api.dart';

/// One service per test, wired to its own [MockClient]. Records every request
/// and how often the token provider was asked.
class _Harness {
  _Harness(
    http.Response Function(http.Request request) respond, {
    String? token = 'firebase-token',
  }) {
    service = AdminSubjectsService(
      client: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
      tokenProvider: () async {
        tokenRequests++;
        return token;
      },
    );
    addTearDown(service.dispose);
  }

  late final AdminSubjectsService service;
  final requests = <http.Request>[];
  int tokenRequests = 0;

  http.Request get only {
    expect(requests, hasLength(1));
    return requests.single;
  }
}

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status);

Uri _url(String path) => Uri.parse('$apiBaseUrl$path');

Matcher _exceptionWith(String message) => isA<Exception>().having(
  (e) => e.toString(),
  'message',
  'Exception: $message',
);

final _signInRequired = _exceptionWith(
  'Sign in is required to manage subjects.',
);

void _expectAdminRequest(http.Request request, String method, String path) {
  expect(request.method, method);
  expect(request.url, _url(path));
  expect(request.headers['Authorization'], 'Bearer firebase-token');
}

/// A client that only records whether it was closed.
class _CloseTrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'subjects': []}))),
        200,
      );

  @override
  void close() => closed = true;
}

void main() {
  group('fetchSubjects', () {
    test('GETs the public catalogue without any token', () async {
      final h = _Harness((_) => _json({'subjects': []}, 200));

      await h.service.fetchSubjects();

      expect(h.only.method, 'GET');
      expect(h.only.url, _url('/subjects'));
      expect(h.only.headers.containsKey('Authorization'), isFalse);
      expect(h.tokenRequests, 0);
    });

    test('works even when nobody is signed in', () async {
      final h = _Harness((_) => _json({'subjects': []}, 200), token: null);

      final result = await h.service.fetchSubjects();

      expect(result.subjects, isEmpty);
      expect(h.requests, hasLength(1));
    });

    test('parses subjects into AdminSubject objects', () async {
      final h = _Harness(
        (_) => _json({
          'subjects': [
            {'subjectId': 1, 'subjectName': 'Mathematics'},
            {'subjectId': 2.0, 'subjectName': 'Physics'},
            {'subjectId': 3, 'subjectName': null},
          ],
        }, 200),
      );

      final result = await h.service.fetchSubjects();

      expect(result, isA<AdminSubjectsResult>());
      expect(
        result.subjects.map((s) => (s.subjectId, s.subjectName)).toList(),
        [(1, 'Mathematics'), (2, 'Physics'), (3, '')],
      );
    });

    test('treats a response with no subjects key as an empty list', () async {
      final h = _Harness((_) => _json(<String, Object>{}, 200));

      expect((await h.service.fetchSubjects()).subjects, isEmpty);
    });

    test('a non-200 response throws the backend error message', () async {
      final h = _Harness(
        (_) => _json({'error': 'Subjects are temporarily unavailable.'}, 500),
      );

      await expectLater(
        h.service.fetchSubjects(),
        throwsA(_exceptionWith('Subjects are temporarily unavailable.')),
      );
    });

    test(
      'a non-200 response without a JSON error reports the status',
      () async {
        final h = _Harness(
          (_) => http.Response('<html>Bad gateway</html>', 502),
        );

        await expectLater(
          h.service.fetchSubjects(),
          throwsA(_exceptionWith('Request failed (502).')),
        );
      },
    );

    test('malformed JSON in a 200 response throws', () async {
      final h = _Harness((_) => http.Response('{"subjects": [', 200));

      await expectLater(h.service.fetchSubjects(), throwsFormatException);
    });

    test('an invalid response structure throws instead of returning '
        'partial data', () async {
      for (final body in <Object>[
        ['not', 'an', 'object'],
        {'subjects': 'Mathematics'},
        {
          'subjects': [
            {'subjectName': 'No id'},
          ],
        },
      ]) {
        final h = _Harness((_) => _json(body, 200));
        await expectLater(
          h.service.fetchSubjects(),
          throwsA(isA<TypeError>()),
          reason: jsonEncode(body),
        );
      }
    });
  });

  group('createSubject', () {
    test('POSTs the name with the Firebase bearer token', () async {
      final h = _Harness(
        (_) => _json({'subjectId': 9, 'subjectName': 'Biology'}, 201),
      );

      final created = await h.service.createSubject('Biology');

      _expectAdminRequest(h.only, 'POST', '/admin/subjects');
      expect(h.only.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(h.only.body), {'subjectName': 'Biology'});
      expect((created.subjectId, created.subjectName), (9, 'Biology'));
    });

    test('a 409 duplicate name exposes the backend message', () async {
      final h = _Harness(
        (_) => _json({'error': 'A subject with that name exists.'}, 409),
      );

      await expectLater(
        h.service.createSubject('Physics'),
        throwsA(_exceptionWith('A subject with that name exists.')),
      );
    });

    test('a 200 instead of 201 is treated as a failure', () async {
      final h = _Harness(
        (_) => _json({'subjectId': 9, 'subjectName': 'Biology'}, 200),
      );

      await expectLater(
        h.service.createSubject('Biology'),
        throwsA(_exceptionWith('Request failed (200).')),
      );
    });

    for (final token in [null, '']) {
      test(
        'does not send without a token (${token == null ? 'null' : 'empty'})',
        () async {
          final h = _Harness((_) => _json({}, 201), token: token);

          await expectLater(
            h.service.createSubject('Biology'),
            throwsA(_signInRequired),
          );
          expect(h.requests, isEmpty);
        },
      );
    }
  });

  group('renameSubject', () {
    test('PATCHes /admin/subjects/{id} with the token and new name', () async {
      final h = _Harness(
        (_) => _json({'subjectId': 7, 'subjectName': 'Applied Physics'}, 200),
      );

      final renamed = await h.service.renameSubject(7, 'Applied Physics');

      _expectAdminRequest(h.only, 'PATCH', '/admin/subjects/7');
      expect(h.only.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(h.only.body), {'subjectName': 'Applied Physics'});
      expect((renamed.subjectId, renamed.subjectName), (7, 'Applied Physics'));
    });

    test('exposes 404 and 409 backend messages', () async {
      for (final (status, message) in [
        (404, 'Subject not found.'),
        (409, 'A subject with that name exists.'),
      ]) {
        final h = _Harness((_) => _json({'error': message}, status));
        await expectLater(
          h.service.renameSubject(7, 'Chemistry'),
          throwsA(_exceptionWith(message)),
          reason: '$status',
        );
      }
    });

    test('does not send without a token', () async {
      final h = _Harness((_) => _json({}, 200), token: null);

      await expectLater(
        h.service.renameSubject(7, 'Chemistry'),
        throwsA(_signInRequired),
      );
      expect(h.requests, isEmpty);
    });
  });

  group('deleteSubject', () {
    test('DELETEs /admin/subjects/{id} with the token', () async {
      final h = _Harness((_) => _json({'deleted': true, 'subjectId': 5}, 200));

      await h.service.deleteSubject(5);

      _expectAdminRequest(h.only, 'DELETE', '/admin/subjects/5');
      expect(h.only.body, isEmpty);
    });

    test('a 409 subject-in-use response exposes the backend message', () async {
      const inUse =
          'Subject is in use by tutors or bookings and cannot be deleted.';
      final h = _Harness((_) => _json({'error': inUse}, 409));

      await expectLater(
        h.service.deleteSubject(5),
        throwsA(_exceptionWith(inUse)),
      );
    });

    test('a 404 exposes the backend message', () async {
      final h = _Harness((_) => _json({'error': 'Subject not found.'}, 404));

      await expectLater(
        h.service.deleteSubject(5),
        throwsA(_exceptionWith('Subject not found.')),
      );
    });

    test('does not send without a token', () async {
      final h = _Harness((_) => _json({}, 200), token: '');

      await expectLater(h.service.deleteSubject(5), throwsA(_signInRequired));
      expect(h.requests, isEmpty);
    });
  });

  group('client lifecycle', () {
    test('dispose closes a client the service created itself', () async {
      final service = AdminSubjectsService(tokenProvider: () async => 't');
      service.dispose();

      // A closed client refuses requests before opening any connection.
      await expectLater(
        service.fetchSubjects(),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('dispose leaves an injected client open', () async {
      final client = _CloseTrackingClient();
      addTearDown(client.close);
      final service = AdminSubjectsService(
        client: client,
        tokenProvider: () async => 't',
      );

      service.dispose();

      expect(client.closed, isFalse);
      expect((await service.fetchSubjects()).subjects, isEmpty);
    });
  });
}
