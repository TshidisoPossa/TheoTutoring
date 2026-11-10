import 'dart:convert';

import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/database.dart';

// ignore_for_file: public_member_api_docs

class AdminMonitorValidation implements Exception {
  const AdminMonitorValidation(this.message);
  final String message;
}

class AdminMonitorCursor {
  const AdminMonitorCursor({required this.createdAt, required this.sortKey});
  final DateTime createdAt;
  final String sortKey;

  static AdminMonitorCursor? parse(String? value) {
    if (value == null) return null;
    if (value.length > 512) {
      throw const AdminMonitorValidation('The audit cursor is invalid.');
    }
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(value))))
              as Map<String, dynamic>;
      final time = DateTime.parse(decoded['createdAt'] as String).toUtc();
      final key = decoded['sortKey'] as String;
      if (key.isEmpty) throw const FormatException();
      return AdminMonitorCursor(createdAt: time, sortKey: key);
    } catch (_) {
      throw const AdminMonitorValidation('The audit cursor is invalid.');
    }
  }

  String encode() => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'createdAt': createdAt.toUtc().toIso8601String(),
            'sortKey': sortKey,
          }),
        ),
      )
      .replaceAll('=', '');
}

/// Orders newest events first, using the namespaced key to break ties.
int compareAdminMonitorAuditOrder({
  required DateTime leftCreatedAt,
  required String leftSortKey,
  required DateTime rightCreatedAt,
  required String rightSortKey,
}) {
  final byTime = rightCreatedAt.compareTo(leftCreatedAt);
  return byTime != 0 ? byTime : rightSortKey.compareTo(leftSortKey);
}

Map<String, Object?> adminMonitorAuditEntryJson({
  required String id,
  required String actorName,
  required String actorType,
  required String category,
  required String action,
  required String? detail,
  required String createdAt,
  required String recordType,
}) => {
  'id': id,
  'actorName': actorName,
  'actorType': actorType,
  'category': category,
  'action': action,
  'detail': detail,
  'createdAt': createdAt,
  // Additive metadata; the Flutter model ignores unknown keys while API
  // consumers can distinguish immutable rows from current-state summaries.
  'recordType': recordType,
};

abstract interface class AdminMonitorRepository {
  Future<Map<String, Object?>> fetchSnapshot({
    required String range,
    required String adminName,
  });

  Future<Map<String, Object?>> fetchAuditPage({
    required int limit,
    required AdminMonitorCursor? before,
  });
}

typedef AdminMonitorRepositoryFactory = AdminMonitorRepository Function();

class MySqlAdminMonitorRepository implements AdminMonitorRepository {
  MySqlAdminMonitorRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final Future<MySQLConnection> Function() _connectionFactory;

  @override
  Future<Map<String, Object?>> fetchSnapshot({
    required String range,
    required String adminName,
  }) async {
    final connection = await _connectionFactory();
    try {
      final result = await connection.execute('''
        SELECT
          (SELECT COUNT(*) FROM `User` WHERE AccountStatus = 'Active') AS activeUsers,
          (SELECT COUNT(*) FROM TutorProfile profile
            INNER JOIN `User` tutor ON tutor.UserId = profile.UserID
            WHERE tutor.AccountStatus = 'Active'
              AND profile.VerificationStat = 'Approved') AS activeTutors,
          (SELECT COUNT(*) FROM TutorApplication WHERE Status = 'Pending') AS pendingApplications
      ''');
      final row = result.rows.single;
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
          'activeUsers': int.tryParse(row.colByName('activeUsers') ?? ''),
          'activeTutors': int.tryParse(row.colByName('activeTutors') ?? ''),
          'pendingApplications': int.tryParse(
            row.colByName('pendingApplications') ?? '',
          ),
        },
        // No request telemetry or baseline is stored by this backend.
        'traffic': {'baselinePerMinute': null, 'points': <Object?>[]},
      };
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  @override
  Future<Map<String, Object?>> fetchAuditPage({
    required int limit,
    required AdminMonitorCursor? before,
  }) async {
    final connection = await _connectionFactory();
    try {
      final result = await connection.execute(
        '''
        SELECT id, sortKey, actorName, actorType, category, action, detail,
               createdAt, recordType
        FROM (
          SELECT
            CONCAT('refund-action-', action.RefundAdminActionID) AS id,
            CONCAT('refund-action-', LPAD(action.RefundAdminActionID, 20, '0')) AS sortKey,
            actor.Name AS actorName,
            'admin' AS actorType,
            'admin_action' AS category,
            CONCAT('Refund ', LOWER(action.Action)) AS action,
            NULLIF(TRIM(CONCAT_WS(' · ',
              NULLIF(action.Reason, ''),
              CASE WHEN action.RefundAmount IS NOT NULL
                THEN CONCAT('Amount: ', action.RefundAmount) END,
              CASE WHEN action.RefundPercentage IS NOT NULL
                THEN CONCAT('Percentage: ', action.RefundPercentage, '%') END
            )), '') AS detail,
            action.CreatedAtUtc AS createdAt,
            'immutable_event' AS recordType
          FROM RefundAdminAction action
          INNER JOIN Admin admin ON admin.AdminID = action.AdminID
          INNER JOIN `User` actor ON actor.UserId = admin.UserId

          UNION ALL

          SELECT
            CONCAT('report-resolution-', report.ReportID) AS id,
            CONCAT('report-resolution-', LPAD(report.ReportID, 20, '0')) AS sortKey,
            actor.Name AS actorName,
            'admin' AS actorType,
            'admin_action' AS category,
            'Report resolved (current-state summary)' AS action,
            NULLIF(TRIM(report.ResolutionNote), '') AS detail,
            report.ResolvedAtUtc AS createdAt,
            'current_state_summary' AS recordType
          FROM Report report
          INNER JOIN Admin admin ON admin.AdminID = report.AdminID
          INNER JOIN `User` actor ON actor.UserId = admin.UserId
          WHERE report.Status = 'Resolved'
            AND report.ResolvedAtUtc IS NOT NULL

        ) audit_entries
        WHERE :hasCursor = 0
           OR (createdAt, sortKey) < (:cursorTime, :cursorSortKey)
        ORDER BY createdAt DESC, sortKey DESC
        LIMIT :pageLimit
        ''',
        {
          'hasCursor': before == null ? 0 : 1,
          'cursorTime': before == null
              ? null
              : _mysqlDateTime(before.createdAt),
          'cursorSortKey': before?.sortKey ?? '',
          'pageLimit': limit + 1,
        },
      );

      final rows = result.rows.toList()
        ..sort(
          (left, right) => compareAdminMonitorAuditOrder(
            leftCreatedAt: DateTime.parse(
              _utcIso(left.colByName('createdAt'))!,
            ),
            leftSortKey: left.colByName('sortKey')!,
            rightCreatedAt: DateTime.parse(
              _utcIso(right.colByName('createdAt'))!,
            ),
            rightSortKey: right.colByName('sortKey')!,
          ),
        );
      final hasMore = rows.length > limit;
      final selected = hasMore ? rows.take(limit) : rows;
      final entries = selected.map((row) {
        final createdAt = _utcIso(row.colByName('createdAt'));
        return adminMonitorAuditEntryJson(
          id: row.colByName('id')!,
          actorName: row.colByName('actorName') ?? 'System',
          actorType: row.colByName('actorType') ?? 'system',
          category: row.colByName('category') ?? 'other',
          action: row.colByName('action') ?? '',
          detail: row.colByName('detail'),
          createdAt: createdAt!,
          recordType: row.colByName('recordType') ?? 'current_state_summary',
        );
      }).toList();

      final nextCursor = hasMore && rows.isNotEmpty
          ? _cursorFor(rows[limit - 1]).encode()
          : null;
      return {'entries': entries, 'nextCursor': nextCursor};
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  AdminMonitorCursor _cursorFor(ResultSetRow row) => AdminMonitorCursor(
    createdAt: DateTime.parse(_utcIso(row.colByName('createdAt'))!).toUtc(),
    sortKey: row.colByName('sortKey')!,
  );

  String? _utcIso(String? value) {
    if (value == null) return null;
    final normalized = value.trim().replaceFirst(' ', 'T');
    return '${normalized}Z';
  }

  String _mysqlDateTime(DateTime value) {
    final utc = value.toUtc();
    String two(int part) => part.toString().padLeft(2, '0');
    final micros = utc.millisecond * 1000 + utc.microsecond;
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}.'
        '${micros.toString().padLeft(6, '0')}';
  }
}
