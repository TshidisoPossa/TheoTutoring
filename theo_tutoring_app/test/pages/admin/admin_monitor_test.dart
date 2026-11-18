import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/monitor_services.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_monitor.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/monitor_models.dart';

// The backend's current response: real counts, plus the empty telemetry
// placeholders it still sends, which the page must not show.
Map<String, dynamic> _snapshotJson({Map<String, dynamic>? counts}) => {
  'adminName': 'Admin Example',
  'metrics': {
    'uptimePercent': null,
    'uptimeSince': null,
    'requestsPerSecond': null,
    'errorRatePercent': null,
    'avgLatencyMs': null,
    'p95LatencyMs': null,
  },
  'operationalMetrics':
      counts ??
      {'activeUsers': 1234, 'activeTutors': 3, 'pendingApplications': 2},
  'traffic': {'baselinePerMinute': null, 'points': <Object?>[]},
};

class _FakeMonitorService extends AdminMonitorService {
  _FakeMonitorService({
    this.failSnapshot = false,
    this.failAudit = false,
    this.emptyAudit = false,
    this.counts,
  }) : super(
         client: MockClient((_) async => throw StateError('Unexpected HTTP')),
       );

  bool failSnapshot;
  bool failAudit;
  bool emptyAudit;
  Map<String, dynamic>? counts;
  Completer<void>? holdSnapshot;
  var snapshotCalls = 0;
  final requestedCursors = <String?>[];

  @override
  Future<MonitorSnapshot> fetchSnapshot() async {
    snapshotCalls++;
    await holdSnapshot?.future;
    if (failSnapshot) throw Exception('Service unavailable');
    return MonitorSnapshot.fromJson(_snapshotJson(counts: counts));
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
        entries: [_entry('refund-action-1')],
        nextCursor: 'older-page',
      );
    }
    return AuditLogPage(
      entries: [_entry('report-resolution-1')],
      nextCursor: null,
    );
  }

  AuditEntry _entry(String id) => AuditEntry(
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

// Everything that has no data source and must not appear.
const _removed = [
  'Server Uptime',
  'API Requests / sec',
  'Error Rate',
  'Avg Latency',
  'Real-time Traffic',
  'Requests per minute vs baseline capacity',
  'Request telemetry is not available from this backend.',
  'Baseline capacity',
  'Live',
  '24h',
  '—',
];

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeMonitorService service, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.8)),
          child: child!,
        ),
        home: AdminMonitorPlatformScreen(service: service),
      ),
    );
    if (!settle) return;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  Future<void> tearDownScreen(
    WidgetTester tester,
    _FakeMonitorService service,
  ) async {
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  }

  testWidgets('shows the database counts and the audit log, and no '
      'telemetry sections', (tester) async {
    final service = _FakeMonitorService();
    await pumpScreen(tester, service);

    expect(find.text('Monitor Platform'), findsOneWidget);
    expect(find.text('Active Users'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('Active Tutors'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Pending Applications'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Audit Log'), findsOneWidget);
    expect(find.text('Refund approved'), findsOneWidget);
    expect(find.text('Recorded event'), findsOneWidget);
    for (final text in _removed) {
      expect(find.text(text), findsNothing, reason: text);
    }

    await tearDownScreen(tester, service);
  });

  testWidgets('loads the counts once, with no background polling', (
    tester,
  ) async {
    final service = _FakeMonitorService();
    await pumpScreen(tester, service);
    await tester.pump(const Duration(minutes: 1));
    expect(service.snapshotCalls, 1);
    await tearDownScreen(tester, service);
  });

  testWidgets('shows a loading indicator until the counts arrive', (
    tester,
  ) async {
    final service = _FakeMonitorService()..holdSnapshot = Completer<void>();
    await pumpScreen(tester, service, settle: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Active Users'), findsNothing);

    service.holdSnapshot!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Active Users'), findsOneWidget);
    await tearDownScreen(tester, service);
  });

  testWidgets('leaves out a count the backend did not return', (tester) async {
    final service = _FakeMonitorService(
      counts: {'activeUsers': 10, 'pendingApplications': 4},
    );
    await pumpScreen(tester, service);
    expect(find.text('Active Users'), findsOneWidget);
    expect(find.text('Pending Applications'), findsOneWidget);
    expect(find.text('Active Tutors'), findsNothing);
    expect(find.text('—'), findsNothing);
    await tearDownScreen(tester, service);
  });

  testWidgets('says so when no counts are available', (tester) async {
    final service = _FakeMonitorService(counts: {});
    await pumpScreen(tester, service);
    expect(
      find.text('No platform counts are available right now.'),
      findsOneWidget,
    );
    expect(find.text('Active Users'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(find.text('Audit Log'), findsOneWidget); // still shown
    await tearDownScreen(tester, service);
  });

  testWidgets('shows retryable count errors, keeping the audit log', (
    tester,
  ) async {
    final service = _FakeMonitorService(failSnapshot: true);
    await pumpScreen(tester, service);

    expect(find.text('Could not load platform metrics.'), findsOneWidget);
    expect(find.text('Service unavailable'), findsOneWidget);
    expect(find.text('Refund approved'), findsOneWidget);

    service.failSnapshot = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Could not load platform metrics.'), findsNothing);
    expect(find.text('Active Users'), findsOneWidget);
    await tearDownScreen(tester, service);
  });

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
    await tearDownScreen(tester, service);
  });

  testWidgets('shows the empty audit state', (tester) async {
    final service = _FakeMonitorService(emptyAudit: true);
    await pumpScreen(tester, service);

    expect(find.text('No audit events recorded yet.'), findsOneWidget);
    expect(find.text('Active Users'), findsOneWidget);
    await tearDownScreen(tester, service);
  });

  testWidgets('shows retryable audit errors', (tester) async {
    final service = _FakeMonitorService(failAudit: true);
    await pumpScreen(tester, service);

    expect(find.text('Could not load the audit log.'), findsOneWidget);
    expect(find.text('Audit unavailable'), findsOneWidget);
    expect(find.text('Active Users'), findsOneWidget);
    service.failAudit = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Recorded event'), findsOneWidget);
    await tearDownScreen(tester, service);
  });

  testWidgets('stacks the counts on a narrow screen without overflow', (
    tester,
  ) async {
    final service = _FakeMonitorService();
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: AdminMonitorPlatformScreen(service: service)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
    final users = tester.getTopLeft(find.text('Active Users'));
    final tutors = tester.getTopLeft(find.text('Active Tutors'));
    expect(tutors.dy, greaterThan(users.dy)); // one per row
    await tearDownScreen(tester, service);
  });
}
