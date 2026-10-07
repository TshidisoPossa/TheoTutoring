import 'package:intl/intl.dart';

// Expected backend responses (Dart Frog):
// dashboard_models.dart turns the JSON from your backend into Dart objects the page can use.
//Holds data classes
double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _int(dynamic v) => (_num(v) ?? 0).toInt();

class ActivityItem {
  final String type;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final String? photoUrl;

  const ActivityItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    this.photoUrl,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
    type: (j['type'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    subtitle: (j['subtitle'] ?? '').toString(),
    createdAt: DateTime.parse(j['createdAt'].toString()),
    photoUrl: j['photoUrl']?.toString(),
  );
}

class ChartPoint {
  final DateTime date;
  final double revenue;
  final int sessions;

  const ChartPoint({
    required this.date,
    required this.revenue,
    required this.sessions,
  });

  factory ChartPoint.fromJson(Map<String, dynamic> j) => ChartPoint(
    date: DateTime.parse(j['date'].toString()),
    revenue: _num(j['revenue']) ?? 0,
    sessions: _int(j['sessions']),
  );
}

class DashboardSummary {
  final String adminName;
  final double totalRevenue;
  final double? totalRevenueChange;
  final int activeStudents;
  final double? activeStudentsChange;
  final int activeTutors;
  final double? activeTutorsChange;
  final double monthlyGrowth;
  final double? monthlyGrowthChange;
  final int pendingApplications;
  final int pendingRefunds;
  final List<ActivityItem> recentActivity;

  const DashboardSummary({
    required this.adminName,
    required this.totalRevenue,
    required this.totalRevenueChange,
    required this.activeStudents,
    required this.activeStudentsChange,
    required this.activeTutors,
    required this.activeTutorsChange,
    required this.monthlyGrowth,
    required this.monthlyGrowthChange,
    required this.pendingApplications,
    required this.pendingRefunds,
    required this.recentActivity,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> j) => DashboardSummary(
    adminName: (j['adminName'] ?? '').toString(),
    totalRevenue: _num(j['totalRevenue']) ?? 0,
    totalRevenueChange: _num(j['totalRevenueChange']),
    activeStudents: _int(j['activeStudents']),
    activeStudentsChange: _num(j['activeStudentsChange']),
    activeTutors: _int(j['activeTutors']),
    activeTutorsChange: _num(j['activeTutorsChange']),
    monthlyGrowth: _num(j['monthlyGrowth']) ?? 0,
    monthlyGrowthChange: _num(j['monthlyGrowthChange']),
    pendingApplications: _int(j['pendingApplications']),
    pendingRefunds: _int(j['pendingRefunds']),
    recentActivity: ((j['recentActivity'] ?? []) as List<dynamic>)
        .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// 124500 -> R124.5k
String compactRand(double v) {
  if (v >= 1000000) return 'R${_trim(v / 1000000)}M';
  if (v >= 1000) return 'R${_trim(v / 1000)}k';
  return 'R${v.toStringAsFixed(0)}';
}

/// 12.4 -> +12.4%, -2 -> -2.0%, null -> -
String formatChange(double? v) {
  if (v == null) return '-';
  return '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}%';
}

String formatActivityTime(DateTime t) {
  final now = DateTime.now();
  final local = t.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat('hh:mm a').format(local);
  if (diff == 1) return 'Yesterday';
  return DateFormat('d MMM').format(local);
}
