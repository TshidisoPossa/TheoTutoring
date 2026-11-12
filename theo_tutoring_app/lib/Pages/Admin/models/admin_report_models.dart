// Backend contract (Dart Frog, lib/admin_reports.dart). Read-only.
//
// GET /admin/reports?status=all|open|under-review|resolved&category=
//     &page=&pageSize=
//   { adminName, total, page, pageSize,
//     reports: [ { reportId, category (null for older student reports),
//                  description, status, bookingId, createdAt,
//                  reporter: {userId, name, email, role} | null,
//                  reportedUser: {userId, name, email, role} | null } ] }

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

int? _intOrNull(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

/// The ?status= values the backend accepts.
const adminReportStatuses = <(String, String)>[
  ('All', 'all'),
  ('Open', 'open'),
  ('Under review', 'under-review'),
  ('Resolved', 'resolved'),
];

/// The ?category= values the backend accepts (tutorReportCategories).
const adminReportCategories = <String>[
  'Payments & Payouts',
  'Student issues',
  'Other',
];

class AdminReportPerson {
  const AdminReportPerson({
    required this.userId,
    this.name,
    this.email,
    this.role,
  });

  /// Null when the backend sends no person (or a non-object).
  static AdminReportPerson? tryParse(dynamic v) {
    if (v is! Map) return null;
    return AdminReportPerson(
      userId: _intOrNull(v['userId']),
      name: _text(v['name']),
      email: _text(v['email']),
      role: _text(v['role']),
    );
  }

  final int? userId;
  final String? name;
  final String? email;
  final String? role;
}

class AdminReport {
  const AdminReport({
    required this.reportId,
    required this.description,
    required this.status,
    this.category,
    this.bookingId,
    this.createdAt,
    this.reporter,
    this.reportedUser,
  });

  factory AdminReport.fromJson(Map<String, dynamic> j) => AdminReport(
    reportId: _int(j['reportId']),
    category: _text(j['category']),
    description: _text(j['description']) ?? '',
    status: _text(j['status']) ?? '',
    bookingId: _intOrNull(j['bookingId']),
    createdAt: _text(j['createdAt']),
    reporter: AdminReportPerson.tryParse(j['reporter']),
    reportedUser: AdminReportPerson.tryParse(j['reportedUser']),
  );

  final int reportId;
  final String? category;
  final String description;
  final String status;
  final int? bookingId;
  final String? createdAt;
  final AdminReportPerson? reporter;
  final AdminReportPerson? reportedUser;
}

class AdminReportsPage {
  const AdminReportsPage({
    required this.adminName,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.reports,
  });

  factory AdminReportsPage.fromJson(Map<String, dynamic> j) {
    final pageSize = _int(j['pageSize']);
    return AdminReportsPage(
      adminName: _text(j['adminName']),
      total: _int(j['total']),
      page: _int(j['page']) < 1 ? 1 : _int(j['page']),
      pageSize: pageSize < 1 ? 20 : pageSize,
      reports: [
        for (final r in (j['reports'] as List<dynamic>?) ?? const [])
          if (r is Map<String, dynamic>) AdminReport.fromJson(r),
      ],
    );
  }

  final String? adminName;
  final int total;
  final int page;
  final int pageSize;
  final List<AdminReport> reports;

  int get pageCount => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
}
