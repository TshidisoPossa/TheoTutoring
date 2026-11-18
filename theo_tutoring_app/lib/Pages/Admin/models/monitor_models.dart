import 'package:intl/intl.dart';

// Monitor Platform: database-backed platform counts and an audit log of
// recorded administrator activity.
//
// Backend responses (Dart Frog):
// GET /admin/monitor
//   { "adminName": "...",
//     "operationalMetrics": { "activeUsers", "activeTutors",
//                             "pendingApplications" } }
//   (The response also carries empty "metrics" and "traffic" placeholders;
//   no request telemetry is recorded, so they are not read.)
//
// GET /admin/monitor/audit-log?limit=20&before=<cursor>
//   { "entries": [ { "id", "actorName", "actorType": "admin|system",
//                    "category": "config|backup|admin_action|security",
//                    "action", "detail", "createdAt" } ],
//     "nextCursor": "..." | null }

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _date(dynamic v) {
  final s = _text(v);
  return s == null ? null : DateTime.tryParse(s)?.toLocal();
}

String _initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class OperationalMetrics {
  final int? activeUsers;
  final int? activeTutors;
  final int? pendingApplications;

  const OperationalMetrics({
    required this.activeUsers,
    required this.activeTutors,
    required this.pendingApplications,
  });

  factory OperationalMetrics.fromJson(Map<String, dynamic> json) =>
      OperationalMetrics(
        activeUsers: _integer(json['activeUsers']),
        activeTutors: _integer(json['activeTutors']),
        pendingApplications: _integer(json['pendingApplications']),
      );
}

int? _integer(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');

class MonitorSnapshot {
  final String adminName;
  final OperationalMetrics operationalMetrics;

  const MonitorSnapshot({
    required this.adminName,
    required this.operationalMetrics,
  });

  factory MonitorSnapshot.fromJson(Map<String, dynamic> j) => MonitorSnapshot(
    adminName: (j['adminName'] ?? '').toString(),
    operationalMetrics: OperationalMetrics.fromJson(
      (j['operationalMetrics'] as Map<String, dynamic>?) ?? const {},
    ),
  );
}

enum AuditCategory {
  config,
  backup,
  adminAction,
  security,
  other;

  static AuditCategory parse(dynamic v) => switch (v?.toString()) {
    'config' => AuditCategory.config,
    'backup' => AuditCategory.backup,
    'admin_action' => AuditCategory.adminAction,
    'security' => AuditCategory.security,
    _ => AuditCategory.other,
  };
}

class AuditEntry {
  final String id;
  final String actorName;
  final bool isSystem;
  final AuditCategory category;
  final AuditRecordType recordType;
  final String action;
  final String? detail;
  final DateTime createdAt;

  const AuditEntry({
    required this.id,
    required this.actorName,
    required this.isSystem,
    required this.category,
    required this.recordType,
    required this.action,
    required this.detail,
    required this.createdAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    id: j['id'].toString(),
    actorName: _text(j['actorName']) ?? 'System',
    isSystem: j['actorType']?.toString() == 'system',
    category: AuditCategory.parse(j['category']),
    recordType: AuditRecordType.parse(j['recordType']),
    action: _text(j['action']) ?? '',
    detail: _text(j['detail']),
    createdAt: _date(j['createdAt']) ?? DateTime.now(),
  );

  String get recordTypeLabel => switch (recordType) {
    AuditRecordType.immutableEvent => 'Recorded event',
    AuditRecordType.currentStateSummary => 'Current state summary',
    AuditRecordType.unknown => 'Audit entry',
  };

  String get initials => isSystem ? 'SY' : _initialsOf(actorName);

  String get timeLabel {
    final now = DateTime.now();
    final sameDay =
        createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
    return sameDay
        ? DateFormat('HH:mm').format(createdAt)
        : DateFormat('d MMM, HH:mm').format(createdAt);
  }
}

enum AuditRecordType {
  immutableEvent,
  currentStateSummary,
  unknown;

  static AuditRecordType parse(dynamic value) => switch (value?.toString()) {
    'immutable_event' => AuditRecordType.immutableEvent,
    'current_state_summary' => AuditRecordType.currentStateSummary,
    _ => AuditRecordType.unknown,
  };
}

class AuditLogPage {
  final List<AuditEntry> entries;
  final String? nextCursor;

  const AuditLogPage({required this.entries, required this.nextCursor});

  factory AuditLogPage.fromJson(Map<String, dynamic> j) => AuditLogPage(
    entries: ((j['entries'] as List<dynamic>?) ?? const [])
        .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextCursor: _text(j['nextCursor']),
  );
}
