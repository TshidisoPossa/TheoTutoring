import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/settings_services.dart';
import 'package:theo_tutoring_app/config/api.dart';

void main() {
  test(
    'session rate calls use shared URL and Firebase bearer identity',
    () async {
      final requests = <http.Request>[];
      final service = AdminSettingsService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'adminName': 'Admin', 'current': null, 'history': []}),
            200,
          );
        }),
        tokenProvider: () async => 'firebase-token',
      );

      await service.fetchSessionRate();
      await service.updateSessionRate('350.00');

      expect(
        requests.map((request) => request.url.origin),
        everyElement(Uri.parse(apiBaseUrl).origin),
      );
      expect(
        requests.map((request) => request.url.path),
        everyElement('/admin/session-rate'),
      );
      expect(requests[0].method, 'GET');
      expect(requests[1].method, 'PUT');
      expect(jsonDecode(requests[1].body), {'amount': '350.00'});
      expect(
        requests.every(
          (r) => r.headers['Authorization'] == 'Bearer firebase-token',
        ),
        isTrue,
      );
    },
  );

  test('session rate API does not send without a Firebase token', () async {
    var sent = false;
    final service = AdminSettingsService(
      client: MockClient((_) async {
        sent = true;
        return http.Response('{}', 200);
      }),
      tokenProvider: () async => null,
    );

    await expectLater(service.fetchSessionRate(), throwsStateError);
    expect(sent, isFalse);
  });
}
