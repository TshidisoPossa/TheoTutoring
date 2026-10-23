import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/monitor_services.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_monitor.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/monitor_models.dart';

class _FakeMonitorService extends AdminMonitorService {
  _FakeMonitorService({
    this.failSnapshot = false,
    this.failAudit = false,
    this.emptyAudit = false,
  }) : super(
         client: MockClient((_) async => throw StateError('Unexpected HTTP')),
       );

  bool failSnapshot;
  bool failAudit;
  bool emptyAudit;
  final requestedCursors = <String?>[];

  @override
  Future<MonitorSnapshot> fetchSnapshot(String range) async {
    if (failSnapshot) throw Exception('Service unavailable');
    return MonitorSnapshot.fromJson({
      'adminName': 'Admin Example',
      'metrics': {
        'uptimePercent': null,
        'uptimeSince': null,
        'requestsPerSecond': null,
        'errorRatePercent': null,
        'avgLatencyMs': null,
        'p95LatencyMs': null,
      },
      'operationalMetrics': {
        'activeUsers': 10,
        'activeTutors': 3,
        'pendingApplications': 2,
      },
      'traffic': {'baselinePerMinute': null, 'points': <Object?>[]},
    });
  }

  @override
  Future<AuditLogPage> fetchAuditLog({String? before, int limit = 20}) async {
    requestedCursors.add(before);
    if (failAudit) throw Exception('Audit unavailable');
    if (emptyAudit) {
      return const AuditLogPage(entries: [], nextCursor: null);
    }
    if (before == null) {
      return AuditLogPage(
        entries: [_entry('refund-action-1', 'Recorded event')],
        nextCursor: 'older-page',
      );
    }
    return AuditLogPage(
      entries: [_entry('report-resolution-1', 'Current state summary')],
      nextCursor: null,
    );
  }

  AuditEntry _entry(String id, String _) => AuditEntry(
    id: id,
    actorName: 'Admin Example',
    isSystem: false,
    category: AuditCategory.adminAction,
    recordType: id.startsWith('report-')
        ? AuditRecordType.currentStateSummary
        : AuditRecordType.immutableEvent,
    action: id.startsWith('report-')
        ? 'Report resolved (current-state summary)'
        : 'Refund approved',
    detail: null,
    createdAt: DateTime.utc(2026, 10, 22, 10),
  );
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeMonitorService service,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.8)),
          child: child!,
        ),
        home: AdminMonitorPlatformScreen(service: service),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets(
    'shows real operational counts and unavailable telemetry safely',
    (tester) async {
      final service = _FakeMonitorService();
      await pumpScreen(tester, service);

      expect(find.text('Server Uptime'), findsOneWidget);
      expect(find.text('API Requests / sec'), findsOneWidget);
      expect(find.text('Active Users'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Pending Applications'), findsOneWidget);
      expect(
        find.text('Request telemetry is not available from this backend.'),
        findsOneWidget,
      );
      expect(find.text('Baseline capacity'), findsNothing);
      expect(find.text('Recorded event'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );

  testWidgets('loads older audit entries using the returned cursor', (
    tester,
  ) async {
    final service = _FakeMonitorService();
    await pumpScreen(tester, service);
    await tester.tap(find.text('Load older logs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(service.requestedCursors, [null, 'older-page']);
    expect(find.text('Current state summary'), findsOneWidget);
    expect(
      find.text('Report resolved (current-state summary)'),
      findsOneWidget,
    );
    expect(find.text('Load older logs'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('shows the empty audit state', (tester) async {
    final service = _FakeMonitorService(emptyAudit: true);
    await pumpScreen(tester, service);

    expect(find.text('No audit events recorded yet.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('shows retryable audit errors', (tester) async {
    final service = _FakeMonitorService(failAudit: true);
    await pumpScreen(tester, service);

    expect(find.text('Could not load the audit log.'), findsOneWidget);
    expect(find.text('Audit unavailable'), findsOneWidget);
    service.failAudit = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Recorded event'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('shows retryable initial metric errors', (tester) async {
    final service = _FakeMonitorService(failSnapshot: true);
    await pumpScreen(tester, service);

    expect(find.text('Could not load platform metrics.'), findsOneWidget);
    expect(find.text('Service unavailable'), findsOneWidget);
    service.failSnapshot = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Server Uptime'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('shows range refresh errors while retaining the last snapshot', (
    tester,
  ) async {
    final service = _FakeMonitorService();
    await pumpScreen(tester, service);
    service.failSnapshot = true;

    await tester.tap(find.text('24h'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Could not refresh platform metrics.'), findsOneWidget);
    expect(find.text('Server Uptime'), findsOneWidget);
    expect(
      find.text('Request telemetry is not available from this backend.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
