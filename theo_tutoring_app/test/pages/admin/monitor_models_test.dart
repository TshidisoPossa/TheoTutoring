import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/monitor_models.dart';

void main() {
  test('parses the counts and ignores the empty telemetry placeholders', () {
    final snapshot = MonitorSnapshot.fromJson({
      'adminName': 'Verified Admin',
      'metrics': {'uptimePercent': null, 'avgLatencyMs': null},
      'traffic': {'baselinePerMinute': null, 'points': <Object?>[]},
      'operationalMetrics': {
        'activeUsers': 12,
        'activeTutors': '4',
        'pendingApplications': 0,
      },
    });

    expect(snapshot.adminName, 'Verified Admin');
    expect(snapshot.operationalMetrics.activeUsers, 12);
    expect(snapshot.operationalMetrics.activeTutors, 4);
    expect(snapshot.operationalMetrics.pendingApplications, 0);
  });

  test('a missing or unreadable count stays null rather than zero', () {
    final snapshot = MonitorSnapshot.fromJson({
      'operationalMetrics': {'activeUsers': 'n/a'},
    });
    expect(snapshot.adminName, '');
    expect(snapshot.operationalMetrics.activeUsers, isNull);
    expect(snapshot.operationalMetrics.activeTutors, isNull);
    expect(snapshot.operationalMetrics.pendingApplications, isNull);
    expect(
      MonitorSnapshot.fromJson({}).operationalMetrics.activeUsers,
      isNull,
    );
  });

  test('parses backend audit metadata and distinguishes record kinds', () {
    final immutable = AuditEntry.fromJson({
      'id': 'refund-action-12',
      'actorName': 'Admin Example',
      'actorType': 'admin',
      'category': 'admin_action',
      'action': 'Refund approved',
      'detail': null,
      'createdAt': '2026-10-22T10:00:00.000Z',
      'recordType': 'immutable_event',
    });
    final summary = AuditEntry.fromJson({
      'id': 'report-resolution-7',
      'actorName': 'Admin Example',
      'actorType': 'admin',
      'category': 'admin_action',
      'action': 'Report resolved (current-state summary)',
      'detail': 'Reviewed',
      'createdAt': '2026-10-22T10:00:00.000Z',
      'recordType': 'current_state_summary',
    });

    expect(immutable.category, AuditCategory.adminAction);
    expect(immutable.recordTypeLabel, 'Recorded event');
    expect(immutable.actorName, 'Admin Example');
    expect(summary.recordTypeLabel, 'Current state summary');
    expect(summary.detail, 'Reviewed');
  });

  test('parses an empty audit page and nullable next cursor', () {
    final page = AuditLogPage.fromJson({'entries': [], 'nextCursor': null});

    expect(page.entries, isEmpty);
    expect(page.nextCursor, isNull);
  });
}
