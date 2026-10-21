import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/services/tutor_bookings_api.dart';

const _secretToken = 'real-looking.firebase.id-token';

Map<String, Object?> _booking(int id, String status) => {
  'bookingId': id,
  'status': status,
  'date': '2026-11-01',
  'startTime': '10:00:00',
  'endTime': '11:00:00',
  'subject': 'Maths',
  'studentName': 'Student $id',
  'note': null,
  'link': null,
};

void main() {
  test('sends Bearer with the actual token and parses bookings', () async {
    late http.Request seen;
    final api = TutorBookingsApi(
      tokenProvider: () async => _secretToken,
      client: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'bookings': [_booking(1, 'Confirmed'), _booking(2, 'Completed')],
          }),
          200,
        );
      }),
    );

    final bookings = await api.bookings();

    expect(seen.method, 'GET');
    expect(seen.url.path, endsWith('/TutorLandingpage/bookings'));
    expect(seen.headers['Authorization'], 'Bearer $_secretToken');
    expect(bookings.map((b) => b.status), ['Confirmed', 'Completed']);
    expect(bookings.first.studentName, 'Student 1');
  });

  test('an empty list is a valid result', () async {
    final api = TutorBookingsApi(
      tokenProvider: () async => _secretToken,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'bookings': []}), 200),
      ),
    );
    expect(await api.bookings(), isEmpty);
  });

  test('without a token no request is sent', () async {
    var called = false;
    final api = TutorBookingsApi(
      tokenProvider: () async => null,
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(api.bookings(), throwsA(isA<TutorBookingsException>()));
    expect(called, isFalse);
  });

  for (final entry in {
    401: 'expired',
    403: 'active',
    500: 'unavailable',
  }.entries) {
    test('HTTP ${entry.key} gives a clear error that hides the token', () async {
      final api = TutorBookingsApi(
        tokenProvider: () async => _secretToken,
        client: MockClient(
          (_) async => http.Response('boom $_secretToken', entry.key),
        ),
      );
      try {
        await api.bookings();
        fail('expected an exception');
      } on TutorBookingsException catch (e) {
        expect(e.statusCode, entry.key);
        expect(e.message, contains(entry.value));
        expect(e.message, isNot(contains(_secretToken)));
      }
    });
  }

  test('malformed responses and network failures become exceptions', () async {
    for (final handler in <Future<http.Response> Function(http.Request)>[
      (_) async => http.Response('not json', 200),
      (_) async => http.Response(
        jsonEncode({
          'bookings': [{}],
        }),
        200,
      ),
      (_) async => http.Response(jsonEncode({'other': 1}), 200),
      (_) async => throw http.ClientException('offline $_secretToken'),
    ]) {
      final api = TutorBookingsApi(
        tokenProvider: () async => _secretToken,
        client: MockClient(handler),
      );
      try {
        await api.bookings();
        fail('expected an exception');
      } on TutorBookingsException catch (e) {
        expect(e.message, isNot(contains(_secretToken)));
      }
    }
  });
}
