// Read-only endpoint integration coverage. It uses real Firebase token
// verification, resolveAdmin, the configured MySQL connection, and the real
// Monitoring repository. It runs only against the isolated test database and
// only when explicit Firebase ID tokens are supplied by the caller.
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/env.dart';

import '../../routes/admin/monitor/audit-log.dart' as audit_route;
import '../../routes/admin/monitor/index.dart' as monitor_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

const _testDatabase = 'theotutoring_test';
final _adminToken = Platform.environment['THEO_ADMIN_MONITOR_ADMIN_ID_TOKEN'];
final _nonAdminToken =
    Platform.environment['THEO_ADMIN_MONITOR_NON_ADMIN_ID_TOKEN'];

String? _skipReason() {
  if (env['DB_NAME'] != _testDatabase) {
    return 'Set the backend .env DB_NAME to $_testDatabase in a test-only '
        'configuration before running this read-only integration test.';
  }
  if (_adminToken == null || _adminToken!.isEmpty) {
    return 'Provide THEO_ADMIN_MONITOR_ADMIN_ID_TOKEN for an active admin '
        'whose FirebaseUid exists in $_testDatabase.';
  }
  if (_nonAdminToken == null || _nonAdminToken!.isEmpty) {
    return 'Provide THEO_ADMIN_MONITOR_NON_ADMIN_ID_TOKEN for a valid Firebase '
        'user with no active Admin row in $_testDatabase.';
  }
  return null;
}

void main() {
  group(
    'Admin Monitoring endpoints against $_testDatabase',
    () {
      test('active administrator can read snapshot and audit page', () async {
        final snapshot = await _snapshot(_adminToken!, '24h');
        expect(snapshot.statusCode, HttpStatus.ok);
        final snapshotBody =
            jsonDecode(await snapshot.body()) as Map<String, dynamic>;
        expect(snapshotBody['adminName'], isA<String>());
        expect((snapshotBody['adminName'] as String).trim(), isNotEmpty);
        expect(snapshotBody['metrics'], {
          'uptimePercent': null,
          'uptimeSince': null,
          'requestsPerSecond': null,
          'errorRatePercent': null,
          'avgLatencyMs': null,
          'p95LatencyMs': null,
        });
        expect(snapshotBody['traffic'], {
          'baselinePerMinute': null,
          'points': <Object?>[],
        });

        final audit = await _audit(_adminToken!, limit: 5);
        expect(audit.statusCode, HttpStatus.ok);
        final auditBody =
            jsonDecode(await audit.body()) as Map<String, dynamic>;
        expect(auditBody['entries'], isA<List<dynamic>>());
        expect(
          auditBody['nextCursor'] == null || auditBody['nextCursor'] is String,
          isTrue,
        );
        for (final value in auditBody['entries'] as List<dynamic>) {
          final entry = value as Map<String, dynamic>;
          expect(entry['id'], isA<String>());
          expect(entry['actorName'], isA<String>());
          expect(entry['actorType'], 'admin');
          expect(entry['category'], 'admin_action');
          expect(entry['action'], isA<String>());
          expect(entry['createdAt'], isA<String>());
          expect(
            entry['recordType'],
            anyOf('immutable_event', 'current_state_summary'),
          );
          expect(
            entry['id'].toString().startsWith('refund-action-') ||
                entry['id'].toString().startsWith('report-resolution-'),
            isTrue,
          );
        }
      });

      test('valid Firebase non-admin is denied by both endpoints', () async {
        final snapshot = await _snapshot(_nonAdminToken!, 'live');
        final audit = await _audit(_nonAdminToken!);
        expect(snapshot.statusCode, HttpStatus.forbidden);
        expect(audit.statusCode, HttpStatus.forbidden);
      });

      test('invalid Firebase identity is rejected by both endpoints', () async {
        final snapshot = await _snapshot('not-a-firebase-token', 'live');
        final audit = await _audit('not-a-firebase-token');
        expect(snapshot.statusCode, HttpStatus.unauthorized);
        expect(audit.statusCode, HttpStatus.unauthorized);
      });
    },
    skip: _skipReason() ?? false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<Response> _snapshot(String token, String range) async {
  final (context, _) = _context(
    '/admin/monitor?range=${Uri.encodeQueryComponent(range)}',
    token,
  );
  return monitor_route.handleMonitorSnapshot(context);
}

Future<Response> _audit(String token, {int limit = 20}) async {
  final (context, _) = _context(
    '/admin/monitor/audit-log?limit=$limit',
    token,
  );
  return audit_route.handleAdminAuditLog(context);
}

(RequestContext, Request) _context(String path, String token) {
  final context = _MockRequestContext();
  final request = _MockRequest();
  when(() => context.request).thenReturn(request);
  when(() => request.method).thenReturn(HttpMethod.get);
  when(() => request.uri).thenReturn(Uri.parse(path));
  when(() => request.headers).thenReturn({'Authorization': 'Bearer $token'});
  return (context, request);
}
