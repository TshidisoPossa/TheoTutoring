import 'package:intl/intl.dart';

// Expected backend response (Dart Frog):
// GET /admin/applications
//   { "adminName": "...",
//     "applications": [ { "id", "fullName", "photoUrl", "status": "pending_review|background_check",
//                         "appliedAt", "qualifications": ["..."], "subjects": ["..."] } ] }

class TutorApplication {
  final String id;
  final String fullName;
  final String? photoUrl;
  final String status;
  final DateTime appliedAt;
  final List<String> qualifications;
  final List<String> subjects;

  const TutorApplication({
    required this.id,
    required this.fullName,
    required this.photoUrl,
    required this.status,
    required this.appliedAt,
    required this.qualifications,
    required this.subjects,
  });

  factory TutorApplication.fromJson(Map<String, dynamic> j) => TutorApplication(
    id: j['id'].toString(),
    fullName: (j['fullName'] ?? '').toString(),
    photoUrl: j['photoUrl']?.toString(),
    status: (j['status'] ?? '').toString(),
    appliedAt: DateTime.parse(j['appliedAt'].toString()),
    qualifications: ((j['qualifications'] ?? []) as List<dynamic>)
        .map((e) => e.toString())
        .toList(),
    subjects: ((j['subjects'] ?? []) as List<dynamic>)
        .map((e) => e.toString())
        .toList(),
  );

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class ApplicationsResult {
  final String adminName;
  final List<TutorApplication> applications;

  const ApplicationsResult({
    required this.adminName,
    required this.applications,
  });

  factory ApplicationsResult.fromJson(Map<String, dynamic> j) =>
      ApplicationsResult(
        adminName: (j['adminName'] ?? '').toString(),
        applications: ((j['applications'] ?? []) as List<dynamic>)
            .map((e) => TutorApplication.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

String _ago(int n, String unit) => '$n ${n == 1 ? unit : '${unit}s'} ago';

/// 2 days ago -> "2 days ago", older than 30 days -> "on 3 Sep 2026"
String formatApplied(DateTime t) {
  final local = t.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return _ago(diff.inMinutes, 'minute');
  if (diff.inHours < 24) return _ago(diff.inHours, 'hour');
  if (diff.inDays < 30) return _ago(diff.inDays, 'day');
  return 'on ${DateFormat('d MMM yyyy').format(local)}';
}
