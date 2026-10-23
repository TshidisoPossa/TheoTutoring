import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/monitor_models.dart';

void main() {
  test('parses unavailable snapshot values without inventing traffic data', () {
    final snapshot = MonitorSnapshot.fromJson({
      'adminName': 'Verified Admin',
      'metrics': {
        'uptimePercent': null,
        'uptimeSince': null,
        'requestsPerSecond': null,
        'errorRatePercent': null,
        'avgLatencyMs': null,
        'p95LatencyMs': null,
      },
      'traffic': {'baselinePerMinute': null, 'points': <Object?>[]},
    });

    expect(snapshot.adminName, 'Verified Admin');
    expect(snapshot.metrics.uptimePercent, isNull);
    expect(snapshot.metrics.uptimeSince, isNull);
    expect(snapshot.metrics.requestsPerSecond, isNull);
    expect(snapshot.metrics.errorRatePercent, isNull);
    expect(snapshot.metrics.avgLatencyMs, isNull);
    expect(snapshot.metrics.p95LatencyMs, isNull);
    expect(snapshot.traffic.baselinePerMinute, isNull);
    expect(snapshot.traffic.points, isEmpty);
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
