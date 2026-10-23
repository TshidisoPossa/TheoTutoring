import 'package:intl/intl.dart';

// Refunds & Issues (project documentation sections 4.6, 4.9, 9.5 and the
// Refund / Report tables in 11.1). A "case" is either a refund raised by a
// cancelled booking or a report one user made about another.
//
// Expected backend response (Dart Frog):
// GET /admin/refunds?type=all|cancellation|report&status=all|open|resolved
//   { "adminName": "...",
//     "summary": { "openDisputes", "pendingRefunds", "pendingRefundAmount",
//                  "resolvedLast7Days", "needsAction" },
//     "cases": [ { "id", "type": "cancellation|report",
//                  "status": "pending|approved|denied|open|under_review|resolved",
//                  "bookingId", "transactionId", "studentName", "tutorName",
//                  "subject", "sessionStart", "cancelledAt", "createdAt",
//                  "reportedBy": "student|tutor", "reason",
//                  "amountPaid", "paymentMethod",
//                  "refundPercentage", "refundAmount",
//                  "overriddenByAdmin", "decidedBy", "needsAction" } ] }
//
// POST /admin/refunds/{id}/approve                      -> applies the calculated refund
// POST /admin/refunds/{id}/deny      { "reason" }
// POST /admin/refunds/{id}/override  { "refundPercentage": 0-100, "reason" }
// POST /admin/refunds/{id}/resolve   { "note" }         -> reports only

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _int(dynamic v) => (_num(v) ?? 0).toInt();

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _date(dynamic v) {
  final s = _text(v);
  return s == null ? null : DateTime.tryParse(s)?.toLocal();
}

final _money = NumberFormat('#,##0.00');
String formatRand(double v) => 'R ${_money.format(v)}';

final _dateTime = DateFormat('d MMM yyyy, HH:mm');
String formatCaseDate(DateTime d) => _dateTime.format(d);

enum CaseType {
  cancellation,
  report;

  static CaseType parse(dynamic v) =>
      v?.toString() == 'report' ? CaseType.report : CaseType.cancellation;

  String get label => switch (this) {
    CaseType.cancellation => 'Cancellation',
    CaseType.report => 'User Report',
  };

  // Value sent to the backend filter.
  String get apiValue => name;
}

enum CaseStatus {
  // Refund statuses
  pending,
  approved,
  denied,
  // Report statuses
  open,
  underReview,
  resolved;

  static CaseStatus parse(dynamic v) =>
      switch (v?.toString().toLowerCase().replaceAll(' ', '_')) {
        'approved' => CaseStatus.approved,
        'denied' || 'rejected' => CaseStatus.denied,
        'open' => CaseStatus.open,
        'under_review' => CaseStatus.underReview,
        'resolved' => CaseStatus.resolved,
        _ => CaseStatus.pending,
      };

  String get label => switch (this) {
    CaseStatus.pending => 'Pending',
    CaseStatus.approved => 'Approved',
    CaseStatus.denied => 'Denied',
    CaseStatus.open => 'Open',
    CaseStatus.underReview => 'Under Review',
    CaseStatus.resolved => 'Resolved',
  };

  bool get isClosed =>
      this == CaseStatus.approved ||
      this == CaseStatus.denied ||
      this == CaseStatus.resolved;
}

class RefundCase {
  final String id;
  final CaseType type;
  final CaseStatus status;
  final String? bookingId;
  final String? transactionId;
  final String studentName;
  final String tutorName;
  final String? subject;
  final DateTime? sessionStart;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final String? reportedBy;
  final String? reason;
  final double? amountPaid;
  final String? paymentMethod;
  final double? refundPercentage;
  final double? refundAmount;
  final bool overriddenByAdmin;
  final String? decidedBy;
  final bool needsAction;

  const RefundCase({
    required this.id,
    required this.type,
    required this.status,
    required this.bookingId,
    required this.transactionId,
    required this.studentName,
    required this.tutorName,
    required this.subject,
    required this.sessionStart,
    required this.cancelledAt,
    required this.createdAt,
    required this.reportedBy,
    required this.reason,
    required this.amountPaid,
    required this.paymentMethod,
    required this.refundPercentage,
    required this.refundAmount,
    required this.overriddenByAdmin,
    required this.decidedBy,
    required this.needsAction,
  });

  factory RefundCase.fromJson(Map<String, dynamic> j) => RefundCase(
    id: j['id'].toString(),
    type: CaseType.parse(j['type']),
    status: CaseStatus.parse(j['status']),
    bookingId: _text(j['bookingId']),
    transactionId: _text(j['transactionId']),
    studentName: _text(j['studentName']) ?? 'Unknown student',
    tutorName: _text(j['tutorName']) ?? 'Unknown tutor',
    subject: _text(j['subject']),
    sessionStart: _date(j['sessionStart']),
    cancelledAt: _date(j['cancelledAt']),
    createdAt: _date(j['createdAt']),
    reportedBy: _text(j['reportedBy']),
    reason: _text(j['reason']),
    amountPaid: _num(j['amountPaid']),
    paymentMethod: _text(j['paymentMethod']),
    refundPercentage: _num(j['refundPercentage']),
    refundAmount: _num(j['refundAmount']),
    overriddenByAdmin: j['overriddenByAdmin'] == true,
    decidedBy: _text(j['decidedBy']),
    needsAction: j['needsAction'] == true,
  );

  /// The reference shown in the table: the payment ID when there is one,
  /// otherwise the booking, otherwise the case itself.
  String get reference =>
      transactionId ?? (bookingId != null ? 'BK-$bookingId' : '#$id');

  bool get hasPayment => (amountPaid ?? 0) > 0;

  /// Hours between cancellation and the session start, used by the policy.
  double? get hoursNotice {
    if (cancelledAt == null || sessionStart == null) return null;
    return sessionStart!.difference(cancelledAt!).inMinutes / 60;
  }

  // Which actions the admin can take (documentation 9.5: Deny, Approve
  // Refund, Override Decision). Decisions are only made while a case is open.
  bool get canApproveOrDeny =>
      type == CaseType.cancellation && status == CaseStatus.pending;

  bool get canOverride =>
      type == CaseType.cancellation && !status.isClosed && hasPayment;

  bool get canResolve => type == CaseType.report && !status.isClosed;
}

class RefundSummary {
  final int openDisputes;
  final int pendingRefunds;
  final double pendingRefundAmount;
  final int resolvedLast7Days;
  final int needsAction;

  const RefundSummary({
    required this.openDisputes,
    required this.pendingRefunds,
    required this.pendingRefundAmount,
    required this.resolvedLast7Days,
    required this.needsAction,
  });

  factory RefundSummary.fromJson(Map<String, dynamic> j) => RefundSummary(
    openDisputes: _int(j['openDisputes']),
    pendingRefunds: _int(j['pendingRefunds']),
    pendingRefundAmount: _num(j['pendingRefundAmount']) ?? 0,
    resolvedLast7Days: _int(j['resolvedLast7Days']),
    needsAction: _int(j['needsAction']),
  );
}

class RefundCasesResult {
  final String adminName;
  final RefundSummary summary;
  final List<RefundCase> cases;

  const RefundCasesResult({
    required this.adminName,
    required this.summary,
    required this.cases,
  });

  factory RefundCasesResult.fromJson(Map<String, dynamic> j) =>
      RefundCasesResult(
        adminName: (j['adminName'] ?? '').toString(),
        summary: RefundSummary.fromJson(
          (j['summary'] as Map<String, dynamic>?) ?? const {},
        ),
        cases: ((j['cases'] as List<dynamic>?) ?? const [])
            .map((e) => RefundCase.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
