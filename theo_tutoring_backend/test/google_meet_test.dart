import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/google_meet.dart';

// createMeetRoom against a fake Google, so no real rooms are made.

const _room = 'https://meet.google.com/abc-mnop-xyz';

/// A Google that answers every request with [status] and [body].
MockClient _google(int status, Object body) => MockClient(
  (_) async => http.Response(
    body is String ? body : jsonEncode(body),
    status,
  ),
);

void main() {
  test('creates the room as the tutor and returns its link', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response(
        jsonEncode({'name': 'spaces/abc', 'meetingUri': _room}),
        200,
      );
    });

    expect(await createMeetRoom('google-token', client: client), _room);
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://meet.googleapis.com/v2/spaces');
    expect(sent.headers['Authorization'], 'Bearer google-token');
    expect(sent.body, '{}'); // the room keeps Google's default access
  });

  test('401 and 403 mean Google refused the account', () async {
    for (final status in [401, 403]) {
      expect(
        createMeetRoom('t', client: _google(status, {'error': 'no'})),
        throwsA(isA<GoogleMeetDenied>()),
        reason: 'HTTP $status',
      );
    }
  });

  test('a server error means Google is unavailable', () {
    expect(
      createMeetRoom('t', client: _google(500, {'error': 'busy'})),
      throwsA(isA<GoogleMeetUnavailable>()),
    );
  });

  test('a reply without meetingUri is refused', () {
    expect(
      createMeetRoom('t', client: _google(200, {'name': 'spaces/abc'})),
      throwsA(isA<GoogleMeetUnavailable>()),
    );
  });

  test('a link that is not on meet.google.com is refused', () {
    expect(
      createMeetRoom(
        't',
        client: _google(200, {'meetingUri': 'https://evil.example/abc'}),
      ),
      throwsA(isA<GoogleMeetUnavailable>()),
    );
  });

  test('a reply that is not JSON means Google is unavailable', () {
    expect(
      createMeetRoom('t', client: _google(200, '<html>Oops</html>')),
      throwsA(isA<GoogleMeetUnavailable>()),
    );
  });

  test('a lost connection means Google is unavailable', () {
    final client = MockClient(
      (request) async => throw http.ClientException('lost', request.url),
    );
    expect(
      createMeetRoom('t', client: client),
      throwsA(isA<GoogleMeetUnavailable>()),
    );
  });

  test('a Google that never answers times out', () {
    final never = Completer<http.Response>();
    final client = MockClient((_) => never.future);
    expect(
      createMeetRoom(
        't',
        client: client,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<GoogleMeetUnavailable>()),
    );
  });
}
