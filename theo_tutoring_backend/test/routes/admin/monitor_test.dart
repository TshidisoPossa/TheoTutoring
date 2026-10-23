import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_monitor.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/monitor/audit-log.dart' as audit_route;
import '../../../routes/admin/monitor/index.dart' as monitor_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _FakeMonitorRepository implements AdminMonitorRepository {
  String? range;
  int? limit;
  AdminMonitorCursor? before;

  @override
  Future<Map<String, Object?>> fetchSnapshot({
    required String range,
    required String adminName,
  }) async {
    this.range = range;
    return {
      'adminName': adminName,
      'metrics': {
        'uptimePercent': null,
        'uptimeSince': null,
        'requestsPerSecond': null,
        'errorRatePercent': null,
        'avgLatencyMs': null,
        'p95LatencyMs': null,
      },
      'operationalMetrics': {
        'activeUsers': 12,
        'activeTutors': 4,
        'pendingApplications': 2,
      },
      'traffic': {'baselinePerMinute': null, 'points': <Object?>[]},
    };
  }

  @override
  Future<Map<String, Object?>> fetchAuditPage({
    required int limit,
    required AdminMonitorCursor? before,
  }) async {
    this.limit = limit;
    this.before = before;
    return {
      'entries': [
        adminMonitorAuditEntryJson(
          id: 'refund-action-17',
          actorName: 'Admin Example',
          actorType: 'admin',
          category: 'admin_action',
          action: 'Refund approved',
          detail: 'Refund reason',
          createdAt: '2026-10-22T10:00:00.000Z',
          recordType: 'immutable_event',
        ),
      ],
      'nextCursor': null,
    };
  }
}

void main() {
  late RequestContext context;
  late Request request;
  late _FakeMonitorRepository repository;

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    repository = _FakeMonitorRepository();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.get);
    when(() => request.uri).thenReturn(Uri.parse('/admin/monitor'));
    when(
      () => request.headers,
    ).thenReturn({'Authorization': 'Bearer verified'});
  });

  Future<AdminIdentity> allowedAdmin(String? authorization) async {
    expect(authorization, 'Bearer verified');
    return const AdminIdentity(id: 4, name: 'Verified Admin');
  }

  test(
    'snapshot returns exact UI fields with unavailable values empty',
    () async {
      when(() => request.uri).thenReturn(
        Uri.parse('/admin/monitor?range=24h'),
      );
      final response = await monitor_route.handleMonitorSnapshot(
        context,
        adminResolver: allowedAdmin,
        repositoryFactory: () => repository,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(repository.range, '24h');
      expect(jsonDecode(await response.body()), {
        'adminName': 'Verified Admin',
        'metrics': {
          'uptimePercent': null,
          'uptimeSince': null,
          'requestsPerSecond': null,
          'errorRatePercent': null,
          'avgLatencyMs': null,
          'p95LatencyMs': null,
        },
        'operationalMetrics': {
          'activeUsers': 12,
          'activeTutors': 4,
          'pendingApplications': 2,
        },
        'traffic': {'baselinePerMinute': null, 'points': <Object?>[]},
      });
    },
  );

  test('snapshot rejects an unsupported range', () async {
    when(() => request.uri).thenReturn(Uri.parse('/admin/monitor?range=7d'));
    final response = await monitor_route.handleMonitorSnapshot(
      context,
      adminResolver: allowedAdmin,
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.badRequest);
    expect(repository.range, isNull);
  });

  test('application reviewers cannot access Monitoring data', () async {
    final response = await monitor_route.handleMonitorSnapshot(
      context,
      adminResolver: (_) async => const AdminIdentity(
        id: 7,
        name: 'Reviewer',
        roleKey: 'application_reviewer',
      ),
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.forbidden);
    expect(repository.range, isNull);
  });

  test(
    'both endpoints distinguish invalid authentication from non-admins',
    () async {
      final handlers = [
        (AdminResolver resolver) => monitor_route.handleMonitorSnapshot(
          context,
          adminResolver: resolver,
          repositoryFactory: () => repository,
        ),
        (AdminResolver resolver) => audit_route.handleAdminAuditLog(
          context,
          adminResolver: resolver,
          repositoryFactory: () => repository,
        ),
      ];

      for (final handle in handlers) {
        final unauthenticated = await handle(
          (_) => throw const AuthTokenException('Invalid token.'),
        );
        final nonAdmin = await handle(
          (_) => throw const AdminAccessDenied('Admin required.'),
        );
        expect(unauthenticated.statusCode, HttpStatus.unauthorized);
        expect(nonAdmin.statusCode, HttpStatus.forbidden);
      }
    },
  );

  test(
    'audit response maps immutable event fields and accepts a cursor page',
    () async {
      final cursor = AdminMonitorCursor(
        createdAt: DateTime.utc(2026, 10, 21, 9),
        sortKey: 'report-resolution-0000000000000000007',
      ).encode();
      when(() => request.uri).thenReturn(
        Uri.parse('/admin/monitor/audit-log?limit=7&before=$cursor'),
      );

      final response = await audit_route.handleAdminAuditLog(
        context,
        adminResolver: allowedAdmin,
        repositoryFactory: () => repository,
      );
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      final entries = body['entries'] as List<dynamic>;

      expect(response.statusCode, HttpStatus.ok);
      expect(repository.limit, 7);
      expect(
        repository.before?.sortKey,
        'report-resolution-0000000000000000007',
      );
      expect(entries.single, {
        'id': 'refund-action-17',
        'actorName': 'Admin Example',
        'actorType': 'admin',
        'category': 'admin_action',
        'action': 'Refund approved',
        'detail': 'Refund reason',
        'createdAt': '2026-10-22T10:00:00.000Z',
        'recordType': 'immutable_event',
      });
    },
  );

  test('audit endpoint validates limit and cursor', () async {
    for (final uri in [
      '/admin/monitor/audit-log?limit=0',
      '/admin/monitor/audit-log?limit=101',
      '/admin/monitor/audit-log?limit=abc',
      '/admin/monitor/audit-log?before=invalid',
    ]) {
      when(() => request.uri).thenReturn(Uri.parse(uri));
      final response = await audit_route.handleAdminAuditLog(
        context,
        adminResolver: allowedAdmin,
        repositoryFactory: () => repository,
      );
      expect(response.statusCode, HttpStatus.badRequest, reason: uri);
    }
  });

  test('same-time audit ordering uses the collision-free key descending', () {
    final time = DateTime.utc(2026, 10, 22);
    expect(
      compareAdminMonitorAuditOrder(
        leftCreatedAt: time,
        leftSortKey: 'refund-action-0002',
        rightCreatedAt: time,
        rightSortKey: 'refund-action-0001',
      ),
      lessThan(0),
    );
    expect(
      AdminMonitorCursor.parse(
        AdminMonitorCursor(
          createdAt: time,
          sortKey: 'report-resolution-9',
        ).encode(),
      )?.createdAt,
      time,
    );
  });

  test(
    'audit JSON distinguishes recorded events from current-state summaries',
    () {
      final refund = adminMonitorAuditEntryJson(
        id: 'refund-action-2',
        actorName: 'Admin',
        actorType: 'admin',
        category: 'admin_action',
        action: 'Refund approved',
        detail: null,
        createdAt: '2026-10-22T00:00:00Z',
        recordType: 'immutable_event',
      );
      final report = adminMonitorAuditEntryJson(
        id: 'report-resolution-2',
        actorName: 'Admin',
        actorType: 'admin',
        category: 'admin_action',
        action: 'Report resolved',
        detail: 'Reviewed',
        createdAt: '2026-10-22T00:00:00Z',
        recordType: 'current_state_summary',
      );
      expect(refund['id'], isNot(report['id']));
      expect(refund['recordType'], 'immutable_event');
      expect(report['recordType'], 'current_state_summary');
    },
  );
}
