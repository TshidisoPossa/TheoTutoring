import 'package:intl/intl.dart';

// Backend contract (Dart Frog, lib/admin_tutors.dart):
//
// GET /admin/tutors?status=all|active|suspended|pending&search=&page=1&pageSize=10
//   { "adminName",
//     "summary": { "totalTutors", "activeThisMonth",
//                  "avgLessonsPerTutor", "suspendedAccounts" },
//     "tutors": [ { "tutorId", "name", "email", "phone", "photoUrl",
//                   "subjects", "experience", "verification",
//                   "averageRating", "reviewCount", "totalLessons",
//                   "joinedAt",
//                   "status": "Active|Pending|Suspended|Deactivated|..." } ],
//     "total", "page", "pageSize" }
//
// PATCH /admin/tutors/{tutorId}/status   { "status": "Active|Suspended|Deactivated" }
//   -> the updated tutor. "Removed" in the UI is the existing
//      User.AccountStatus value 'Deactivated' (no data is deleted). Tutors
//      still in review (Incomplete, Pending, Rejected) are refused (409):
//      they are decided on the Applications page.

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double? _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// Account statuses an admin can set from the Tutors page.
enum TutorStatusChange {
  active('Active', 'Active'),
  suspended('Suspended', 'Suspended'),
  removed('Deactivated', 'Removed');

  const TutorStatusChange(this.apiValue, this.label);

  /// The User.AccountStatus value sent to the backend.
  final String apiValue;
  final String label;
}

class AdminTutor {
  final int tutorId;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;

  /// "Accounting, Mathematics", or null if none chosen yet.
  final String? subjects;
  final String? experience;

  /// TutorProfile.VerificationStat: Pending, Approved or Rejected.
  final String? verification;
  final double averageRating;
  final int reviewCount;
  final int totalLessons;
  final DateTime? joinedAt;

  /// User.AccountStatus, e.g. Active, Pending, Suspended, Deactivated.
  final String status;

  const AdminTutor({
    required this.tutorId,
    required this.name,
    required this.email,
    required this.totalLessons,
    required this.status,
    this.phone,
    this.photoUrl,
    this.subjects,
    this.experience,
    this.verification,
    this.averageRating = 0,
    this.reviewCount = 0,
    this.joinedAt,
  });

  factory AdminTutor.fromJson(Map<String, dynamic> j) => AdminTutor(
    tutorId: _int(j['tutorId']) ?? 0,
    name: _text(j['name']) ?? 'Unnamed tutor',
    email: _text(j['email']) ?? '',
    phone: _text(j['phone']),
    photoUrl: _text(j['photoUrl']),
    subjects: _text(j['subjects']),
    experience: _text(j['experience']),
    verification: _text(j['verification']),
    averageRating: _num(j['averageRating']) ?? 0,
    reviewCount: _int(j['reviewCount']) ?? 0,
    totalLessons: _int(j['totalLessons']) ?? 0,
    joinedAt: DateTime.tryParse('${j['joinedAt'] ?? ''}')?.toLocal(),
    status: _text(j['status']) ?? 'Unknown',
  );

  String get reference => 'TUT-$tutorId';

  /// "Deactivated" accounts are shown as "Removed".
  String get statusLabel => status == 'Deactivated' ? 'Removed' : status;

  bool get isSuspended => status == 'Suspended';
  bool get isRemoved => status == 'Deactivated';

  /// Not approved yet: the Applications page decides their status.
  bool get isInReview =>
      !TutorStatusChange.values.any((option) => option.apiValue == status);

  /// "4.5 (12 reviews)" or "No reviews yet".
  String get ratingLabel => reviewCount == 0
      ? 'No reviews yet'
      : '${averageRating.toStringAsFixed(1)} '
            '($reviewCount ${reviewCount == 1 ? 'review' : 'reviews'})';

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

class TutorSummary {
  final int? totalTutors;
  final int? activeThisMonth;
  final double? avgLessonsPerTutor;
  final int? suspendedAccounts;

  const TutorSummary({
    this.totalTutors,
    this.activeThisMonth,
    this.avgLessonsPerTutor,
    this.suspendedAccounts,
  });

  factory TutorSummary.fromJson(Map<String, dynamic> j) => TutorSummary(
    totalTutors: _int(j['totalTutors']),
    activeThisMonth: _int(j['activeThisMonth']),
    avgLessonsPerTutor: _num(j['avgLessonsPerTutor']),
    suspendedAccounts: _int(j['suspendedAccounts']),
  );
}

class AdminTutorsPage {
  final String adminName;
  final TutorSummary summary;
  final List<AdminTutor> tutors;
  final int total;
  final int page;
  final int pageSize;

  const AdminTutorsPage({
    required this.adminName,
    required this.summary,
    required this.tutors,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory AdminTutorsPage.fromJson(Map<String, dynamic> j) {
    final tutors = ((j['tutors'] as List<dynamic>?) ?? const [])
        .map((e) => AdminTutor.fromJson(e as Map<String, dynamic>))
        .toList();
    return AdminTutorsPage(
      adminName: _text(j['adminName']) ?? '',
      summary: TutorSummary.fromJson(
        (j['summary'] as Map<String, dynamic>?) ?? const {},
      ),
      tutors: tutors,
      total: _int(j['total']) ?? tutors.length,
      page: _int(j['page']) ?? 1,
      pageSize: _int(j['pageSize']) ?? 10,
    );
  }

  int get pageCount => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
}
