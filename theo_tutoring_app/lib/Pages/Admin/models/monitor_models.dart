import 'package:intl/intl.dart';

// Monitor Platform (project documentation section 9.5): four metric cards,
// a live traffic chart against baseline capacity, and an audit log of system
// events such as configuration changes, database backups and admin actions.
//
// Expected backend response (Dart Frog):
// GET /admin/monitor?range=live|24h
//   { "adminName": "...",
//     "metrics": { "uptimePercent", "uptimeSince", "requestsPerSecond",
//                  "errorRatePercent", "avgLatencyMs", "p95LatencyMs" },
//     "traffic": { "baselinePerMinute",
//                  "points": [ { "time", "requests" } ] } }
//
// GET /admin/monitor/audit-log?limit=20&before=<cursor>
//   { "entries": [ { "id", "actorName", "actorType": "admin|system",
//                    "category": "config|backup|admin_action|security",
//                    "action", "detail", "createdAt" } ],
//     "nextCursor": "..." | null }

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

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

class PlatformMetrics {
  final double? uptimePercent;
  final DateTime? uptimeSince;
  final double? requestsPerSecond;
  final double? errorRatePercent;
  final double? avgLatencyMs;
  final double? p95LatencyMs;

  const PlatformMetrics({
    required this.uptimePercent,
    required this.uptimeSince,
    required this.requestsPerSecond,
    required this.errorRatePercent,
    required this.avgLatencyMs,
    required this.p95LatencyMs,
  });

  factory PlatformMetrics.fromJson(Map<String, dynamic> j) => PlatformMetrics(
    uptimePercent: _num(j['uptimePercent']),
    uptimeSince: _date(j['uptimeSince']),
    requestsPerSecond: _num(j['requestsPerSecond']),
    errorRatePercent: _num(j['errorRatePercent']),
    avgLatencyMs: _num(j['avgLatencyMs']),
    p95LatencyMs: _num(j['p95LatencyMs']),
  );
}

class TrafficPoint {
  final DateTime time;
  final double requests;

  const TrafficPoint({required this.time, required this.requests});

  factory TrafficPoint.fromJson(Map<String, dynamic> j) => TrafficPoint(
    time: _date(j['time']) ?? DateTime.now(),
    requests: _num(j['requests']) ?? 0,
  );
}

class TrafficSeries {
  final double? baselinePerMinute;
  final List<TrafficPoint> points;

  const TrafficSeries({required this.baselinePerMinute, required this.points});

  factory TrafficSeries.fromJson(Map<String, dynamic> j) => TrafficSeries(
    baselinePerMinute: _num(j['baselinePerMinute']),
    points: ((j['points'] as List<dynamic>?) ?? const [])
        .map((e) => TrafficPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class MonitorSnapshot {
  final String adminName;
  final PlatformMetrics metrics;
  final TrafficSeries traffic;

  const MonitorSnapshot({
    required this.adminName,
    required this.metrics,
    required this.traffic,
  });

  factory MonitorSnapshot.fromJson(Map<String, dynamic> j) => MonitorSnapshot(
    adminName: (j['adminName'] ?? '').toString(),
    metrics: PlatformMetrics.fromJson(
      (j['metrics'] as Map<String, dynamic>?) ?? const {},
    ),
    traffic: TrafficSeries.fromJson(
      (j['traffic'] as Map<String, dynamic>?) ?? const {},
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
  final String action;
  final String? detail;
  final DateTime createdAt;

  const AuditEntry({
    required this.id,
    required this.actorName,
    required this.isSystem,
    required this.category,
    required this.action,
    required this.detail,
    required this.createdAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    id: j['id'].toString(),
    actorName: _text(j['actorName']) ?? 'System',
    isSystem: j['actorType']?.toString() == 'system',
    category: AuditCategory.parse(j['category']),
    action: _text(j['action']) ?? '',
    detail: _text(j['detail']),
    createdAt: _date(j['createdAt']) ?? DateTime.now(),
  );

  String get initials => isSystem ? 'SY' : _initialsOf(actorName);

  String get timeLabel {
    final now = DateTime.now();
    final sameDay = createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
    return sameDay
        ? DateFormat('HH:mm').format(createdAt)
        : DateFormat('d MMM, HH:mm').format(createdAt);
  }
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
