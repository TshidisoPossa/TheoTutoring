import 'package:intl/intl.dart';

// Expected backend contract (Dart Frog). These Admin endpoints do not exist
// yet; the Students page shows an "unavailable" state until they do.
//
// GET /admin/students?status=all|active|suspended|pending&search=&page=1&pageSize=10
//   { "adminName",
//     "summary": { "totalStudents", "activeThisMonth",
//                  "avgLessonsPerStudent", "suspendedAccounts" },
//     "students": [ { "studentId", "name", "email", "phone", "photoUrl",
//                     "course", "institutionYear", "subjectOfInterest",
//                     "totalLessons", "joinedAt",
//                     "status": "Active|Pending|Suspended|Deactivated|..." } ],
//     "total", "page", "pageSize" }
//
// PATCH /admin/students/{studentId}/status   { "status": "Active|Suspended|Deactivated" }
//   -> the updated student. "Removed" in the UI is the existing
//      User.AccountStatus value 'Deactivated' (no data is deleted).

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double? _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// Account statuses an admin can set from the Students page.
enum StudentStatusChange {
  active('Active', 'Active'),
  suspended('Suspended', 'Suspended'),
  removed('Deactivated', 'Removed');

  const StudentStatusChange(this.apiValue, this.label);

  /// The User.AccountStatus value sent to the backend.
  final String apiValue;
  final String label;
}

class AdminStudent {
  final int studentId;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;
  final String? course;
  final String? institutionYear;
  final String? subjectOfInterest;
  final int totalLessons;
  final DateTime? joinedAt;

  /// User.AccountStatus, e.g. Active, Pending, Suspended, Deactivated.
  final String status;

  /// The institution the proof of registration should be from.
  final String? institution;

  /// Proof of registration uploaded at sign-up (Cloudinary link).
  final String? proofOfRegistrationUrl;

  const AdminStudent({
    required this.studentId,
    required this.name,
    required this.email,
    required this.totalLessons,
    required this.status,
    this.phone,
    this.photoUrl,
    this.course,
    this.institutionYear,
    this.subjectOfInterest,
    this.joinedAt,
    this.institution,
    this.proofOfRegistrationUrl,
  });

  factory AdminStudent.fromJson(Map<String, dynamic> j) => AdminStudent(
    studentId: _int(j['studentId']) ?? 0,
    name: _text(j['name']) ?? 'Unnamed student',
    email: _text(j['email']) ?? '',
    phone: _text(j['phone']),
    photoUrl: _text(j['photoUrl']),
    course: _text(j['course']),
    institutionYear: _text(j['institutionYear']),
    subjectOfInterest: _text(j['subjectOfInterest']),
    totalLessons: _int(j['totalLessons']) ?? 0,
    joinedAt: DateTime.tryParse('${j['joinedAt'] ?? ''}')?.toLocal(),
    status: _text(j['status']) ?? 'Unknown',
    institution: _text(j['institution']),
    proofOfRegistrationUrl: _text(j['proofOfRegistrationUrl']),
  );

  AdminStudent copyWith({String? status}) => AdminStudent(
    studentId: studentId,
    name: name,
    email: email,
    phone: phone,
    photoUrl: photoUrl,
    course: course,
    institutionYear: institutionYear,
    subjectOfInterest: subjectOfInterest,
    totalLessons: totalLessons,
    joinedAt: joinedAt,
    status: status ?? this.status,
  );

  String get reference => 'STU-$studentId';

  /// "Deactivated" accounts are shown as "Removed".
  String get statusLabel => status == 'Deactivated' ? 'Removed' : status;

  bool get isSuspended => status == 'Suspended';
  bool get isRemoved => status == 'Deactivated';

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get joinedLabel =>
      joinedAt == null ? '—' : DateFormat('MMM d, yyyy').format(joinedAt!);
}

class StudentSummary {
  final int? totalStudents;
  final int? activeThisMonth;
  final double? avgLessonsPerStudent;
  final int? suspendedAccounts;

  const StudentSummary({
    this.totalStudents,
    this.activeThisMonth,
    this.avgLessonsPerStudent,
    this.suspendedAccounts,
  });

  factory StudentSummary.fromJson(Map<String, dynamic> j) => StudentSummary(
    totalStudents: _int(j['totalStudents']),
    activeThisMonth: _int(j['activeThisMonth']),
    avgLessonsPerStudent: _num(j['avgLessonsPerStudent']),
    suspendedAccounts: _int(j['suspendedAccounts']),
  );
}

class AdminStudentsPage {
  final String adminName;
  final StudentSummary summary;
  final List<AdminStudent> students;
  final int total;
  final int page;
  final int pageSize;

  const AdminStudentsPage({
    required this.adminName,
    required this.summary,
    required this.students,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory AdminStudentsPage.fromJson(Map<String, dynamic> j) {
    final students = ((j['students'] as List<dynamic>?) ?? const [])
        .map((e) => AdminStudent.fromJson(e as Map<String, dynamic>))
        .toList();
    return AdminStudentsPage(
      adminName: _text(j['adminName']) ?? '',
      summary: StudentSummary.fromJson(
        (j['summary'] as Map<String, dynamic>?) ?? const {},
      ),
      students: students,
      total: _int(j['total']) ?? students.length,
      page: _int(j['page']) ?? 1,
      pageSize: _int(j['pageSize']) ?? 10,
    );
  }

  int get pageCount => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
}
