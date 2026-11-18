import 'package:intl/intl.dart';

// Suspension appeals for the admin Appeals page.
//
// GET /admin/appeals?status=pending|approved|rejected|closed|all
//   { "adminName", "summary": { "pending" },
//     "appeals": [ { "appealId", "status", "explanation", "submittedAt",
//                    "decisionNote", "decidedAt", "reviewedBy",
//                    "suspension": { "suspensionId", "reason", "suspendedAt",
//                                    "suspendedBy", "status", "liftedAt",
//                                    "liftReason" },
//                    "user": { "userId", "role", "profileId", "name", "email",
//                              "phone", "photoUrl", "accountStatus",
//                              "joinedAt" } } ] }
//
// POST /admin/appeals/{id}/decision {"decision": "approve"|"reject", "note"}
//   { "appeal": {...}, "notificationDelivered": bool, "warning"? }

/// Filter chips: label and backend value.
const adminAppealStatuses = [
  ('Pending', 'pending'),
  ('Approved', 'approved'),
  ('Rejected', 'rejected'),
  ('Closed', 'closed'),
  ('All', 'all'),
];

/// The backend's limits (lib/account_suspensions.dart), checked here first.
const appealDecisionNoteMinLength = 10;
const appealDecisionNoteMaxLength = 1000;
const suspensionReasonMinLength = 10;
const suspensionReasonMaxLength = 1000;

String? _text(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

DateTime? _date(Object? v) {
  final s = _text(v);
  return s == null ? null : DateTime.tryParse(s)?.toLocal();
}

String _label(DateTime? d) =>
    d == null ? 'Unknown date' : DateFormat('d MMM yyyy, HH:mm').format(d);

class AdminAppealUser {
  const AdminAppealUser({
    required this.userId,
    required this.role,
    required this.name,
    required this.email,
    required this.accountStatus,
    this.profileId,
    this.phone,
    this.photoUrl,
    this.joinedAt,
  });

  factory AdminAppealUser.fromJson(Map<String, dynamic> j) => AdminAppealUser(
    userId: j['userId'] as int,
    role: _text(j['role']) ?? '',
    profileId: j['profileId'] as int?,
    name: _text(j['name']) ?? 'Unknown user',
    email: _text(j['email']) ?? '',
    phone: _text(j['phone']),
    photoUrl: _text(j['photoUrl']),
    accountStatus: _text(j['accountStatus']) ?? '',
    joinedAt: _text(j['joinedAt']),
  );

  final int userId;
  final String role;
  final int? profileId;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;
  final String accountStatus;
  final String? joinedAt;

  String get roleLabel => switch (role) {
    'student' => 'Student',
    'tutor' => 'Tutor',
    _ => role,
  };
}

class AdminAppealSuspension {
  const AdminAppealSuspension({
    required this.id,
    required this.reason,
    required this.status,
    this.suspendedAt,
    this.suspendedBy,
    this.liftReason,
  });

  factory AdminAppealSuspension.fromJson(Map<String, dynamic> j) =>
      AdminAppealSuspension(
        id: j['suspensionId'] as int,
        reason: _text(j['reason']) ?? '',
        status: _text(j['status']) ?? '',
        suspendedAt: _date(j['suspendedAt']),
        suspendedBy: _text(j['suspendedBy']),
        liftReason: _text(j['liftReason']),
      );

  final int id;
  final String reason;
  final String status;
  final DateTime? suspendedAt;
  final String? suspendedBy;
  final String? liftReason;

  String get suspendedLabel => _label(suspendedAt);
}

class AdminAppeal {
  const AdminAppeal({
    required this.id,
    required this.status,
    required this.explanation,
    required this.suspension,
    required this.user,
    this.submittedAt,
    this.decisionNote,
    this.decidedAt,
    this.reviewedBy,
  });

  factory AdminAppeal.fromJson(Map<String, dynamic> j) => AdminAppeal(
    id: j['appealId'] as int,
    status: _text(j['status']) ?? '',
    explanation: _text(j['explanation']) ?? '',
    submittedAt: _date(j['submittedAt']),
    decisionNote: _text(j['decisionNote']),
    decidedAt: _date(j['decidedAt']),
    reviewedBy: _text(j['reviewedBy']),
    suspension: AdminAppealSuspension.fromJson(
      j['suspension'] as Map<String, dynamic>,
    ),
    user: AdminAppealUser.fromJson(j['user'] as Map<String, dynamic>),
  );

  final int id;

  /// Pending, Approved, Rejected or Closed.
  final String status;
  final String explanation;
  final DateTime? submittedAt;
  final String? decisionNote;
  final DateTime? decidedAt;
  final String? reviewedBy;
  final AdminAppealSuspension suspension;
  final AdminAppealUser user;

  bool get isPending => status == 'Pending';
  String get submittedLabel => _label(submittedAt);
  String get decidedLabel => _label(decidedAt);
}

class AdminAppealsPage {
  const AdminAppealsPage({
    required this.adminName,
    required this.pending,
    required this.appeals,
  });

  factory AdminAppealsPage.fromJson(Map<String, dynamic> j) =>
      AdminAppealsPage(
        adminName: _text(j['adminName']),
        pending: ((j['summary'] as Map?)?['pending'] as int?) ?? 0,
        appeals: [
          for (final a in (j['appeals'] as List? ?? const []))
            AdminAppeal.fromJson(a as Map<String, dynamic>),
        ],
      );

  final String? adminName;
  final int pending;
  final List<AdminAppeal> appeals;
}

/// What a decision returned: the decided appeal, and a warning when the
/// user could not be notified yet.
class AdminAppealDecisionResult {
  const AdminAppealDecisionResult({required this.appeal, this.warning});

  factory AdminAppealDecisionResult.fromJson(Map<String, dynamic> j) =>
      AdminAppealDecisionResult(
        appeal: AdminAppeal.fromJson(j['appeal'] as Map<String, dynamic>),
        warning: j['notificationDelivered'] == false
            ? _text(j['warning']) ??
                  'The user could not be notified right now.'
            : null,
      );

  final AdminAppeal appeal;
  final String? warning;
}
