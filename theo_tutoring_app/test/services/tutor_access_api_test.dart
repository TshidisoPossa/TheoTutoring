import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/services/tutor_access_api.dart';

const _token = 'real-looking.firebase.id-token';

TutorAccessApi _api(http.Response Function(http.Request) handler) =>
    TutorAccessApi(client: MockClient((r) async => handler(r)));

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  test(
    'asks the existing dashboard endpoint with the real Bearer token',
    () async {
      late http.Request seen;
      final result = await _api((request) {
        seen = request;
        return _json({'accountStatus': 'Active'});
      }).check(_token);

      expect(seen.method, 'GET');
      expect(seen.url.path, endsWith('/TutorLandingpage/LandingPageScreen'));
      expect(seen.headers['Authorization'], 'Bearer $_token');
      expect(result, isA<TutorAccessGranted>());
    },
  );

  test('Active and Pending are granted with the server status', () async {
    for (final entry in {
      'Active': 'Active',
      'active': 'Active',
      ' ACTIVE ': 'Active',
      'Pending': 'Pending',
      'pending': 'Pending',
    }.entries) {
      final result = await _api((_) => _json({'accountStatus': entry.key}))
          .check(_token);
      expect((result as TutorAccessGranted).accountStatus, entry.value);
      expect(result.dashboard?['accountStatus'], isNotNull);
    }
  });

  test('Incomplete, Rejected, unknown and missing status are denied', () async {
    for (final body in <Object>[
      {'accountStatus': 'Incomplete'},
      {'accountStatus': 'Rejected'},
      {'accountStatus': 'Suspended'},
      {'accountStatus': ''},
      {'accountStatus': null},
      <String, Object?>{},
      <Object>[],
    ]) {
      final result = await _api((_) => _json(body)).check(_token);
      expect(result, isA<TutorAccessDenied>(), reason: '$body');
    }
  });

  test(
    'a 403 from the backend (not a tutor, or restricted) is denied',
    () async {
      final result = await _api(
        (_) => _json({'error': 'An active tutor account is required.'}, 403),
      ).check(_token);
      expect(result, isA<TutorAccessDenied>());
    },
  );

  test(
    '401, server errors, bad JSON and network failures are failures',
    () async {
      final handlers = <http.Response Function(http.Request)>[
        (_) => _json({'error': 'Invalid token'}, 401),
        (_) => _json({'error': 'x'}, 500),
        (_) => _json({'error': 'x'}, 404),
        (_) => http.Response('not json $_token', 200),
        (_) => throw http.ClientException('offline $_token'),
      ];
      for (final handler in handlers) {
        final result = await _api(handler).check(_token);
        expect(result, isA<TutorAccessFailure>());
        final message = (result as TutorAccessFailure).message;
        expect(message, isNot(contains(_token)));
      }
    },
  );
}
