import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/monitor_services.dart';
import 'package:theo_tutoring_app/config/api.dart';

void main() {
  test(
    'uses shared API base and sends Firebase bearer token for both routes',
    () async {
      final requests = <http.Request>[];
      final service = AdminMonitorService(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/audit-log')) {
            return http.Response(
              jsonEncode({'entries': [], 'nextCursor': null}),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'adminName': 'Admin',
              'operationalMetrics': {'activeUsers': 5},
            }),
            200,
          );
        }),
        tokenProvider: () async => 'firebase-id-token',
      );

      final snapshot = await service.fetchSnapshot();
      await service.fetchAuditLog(before: 'cursor/value', limit: 20);

      expect(snapshot.operationalMetrics.activeUsers, 5);
      expect(requests, hasLength(2));
      expect(requests[0].url.origin, Uri.parse(apiBaseUrl).origin);
      expect(requests[0].url.path, '/admin/monitor');
      // No traffic range any more: there is no traffic data to choose from
      expect(requests[0].url.queryParameters, isEmpty);
      expect(requests[0].headers['Authorization'], 'Bearer firebase-id-token');
      expect(requests[1].url.path, '/admin/monitor/audit-log');
      expect(requests[1].url.queryParameters['limit'], '20');
      expect(requests[1].url.queryParameters['before'], 'cursor/value');
      for (final request in requests) {
        expect(request.headers['Authorization'], 'Bearer firebase-id-token');
      }
    },
  );

  test('does not send requests without a Firebase token', () async {
    var sent = false;
    final service = AdminMonitorService(
      client: MockClient((_) async {
        sent = true;
        return http.Response('{}', 200);
      }),
      tokenProvider: () async => null,
    );

    await expectLater(service.fetchSnapshot(), throwsException);
    expect(sent, isFalse);
  });

  test('uses the backend error message for failed requests', () async {
    final service = AdminMonitorService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'Platform metrics are temporarily unavailable.'}),
          500,
        ),
      ),
      tokenProvider: () async => 'token',
    );

    await expectLater(
      service.fetchSnapshot(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Platform metrics are temporarily unavailable.'),
        ),
      ),
    );
  });
}
