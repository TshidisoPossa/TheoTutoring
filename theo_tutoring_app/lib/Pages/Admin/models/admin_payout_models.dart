// Models for the admin Payouts page (GET /admin/payouts).

enum PayoutStatus {
  pending('Pending'),
  approved('Approved'),
  paid('Paid'),

  /// A missing or unrecognised status from the API. Offers no actions.
  unknown('Unknown');

  const PayoutStatus(this.label);
  final String label;

  /// The value GET /admin/payouts?status= expects.
  String get apiValue => name;

  /// Exact, case-sensitive match on the backend's lowercase values; anything
  /// else is [unknown].
  static PayoutStatus fromApi(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return unknown;
  }
}

double _money(Object? value) => value is num ? value.toDouble() : 0;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// "1234.50" / "-12.05" (the finance overview's exact amounts) -> cents.
/// Money stays in integer cents; it is only divided for display.
int? parseCents(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(value.trim());
  if (match == null) return null;
  final cents =
      int.parse(match.group(2)!) * 100 +
      int.parse((match.group(3) ?? '0').padRight(2, '0'));
  return match.group(1) == '-' ? -cents : cents;
}

int _cents(Object? value) => parseCents(value) ?? 0;

String? _text(Object? value) {
  final text = value is String ? value.trim() : null;
  return text == null || text.isEmpty ? null : text;
}

/// The backend sends server wall-clock times without a zone; they are shown
/// exactly as stored.
DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

class PayoutBooking {
  const PayoutBooking({
    required this.bookingId,
    this.studentName,
    this.subject,
    this.date,
    this.startTime,
    this.endTime,
    this.status,
  });

  factory PayoutBooking.fromJson(Map<String, dynamic> json) => PayoutBooking(
    bookingId: _int(json['bookingId']),
    studentName: _text(json['studentName']),
    subject: _text(json['subject']),
    date: _text(json['date']),
    startTime: _text(json['startTime']),
    endTime: _text(json['endTime']),
    status: _text(json['status']),
  );

  final int bookingId;
  final String? studentName;
  final String? subject;

  /// YYYY-MM-DD
  final String? date;

  /// HH:mm
  final String? startTime;
  final String? endTime;
  final String? status;
}

class AdminPayout {
  const AdminPayout({
    required this.id,
    required this.status,
    required this.amount,
    required this.commissionAmount,
    required this.netAmount,
    required this.tutorName,
    this.tutorEmail,
    this.booking,
    this.createdAt,
    this.approvedAt,
    this.paidAt,
    this.approvedBy,
    this.paidBy,
    this.paymentReference,
    this.commissionRate,
    this.commissionRateBackfilled = false,
    this.refundStatus,
    this.refundAmount,
    this.flagged = false,
  });

  factory AdminPayout.fromJson(Map<String, dynamic> json) {
    final tutor = json['tutor'] is Map
        ? Map<String, dynamic>.from(json['tutor'] as Map)
        : const <String, dynamic>{};
    final booking = json['booking'];
    final refund = json['refund'] is Map
        ? Map<String, dynamic>.from(json['refund'] as Map)
        : null;
    return AdminPayout(
      paidBy: _text(json['paidBy']),
      paymentReference: _text(json['paymentReference']),
      commissionRate: _text(json['commissionRate']),
      commissionRateBackfilled: json['commissionRateBackfilled'] == true,
      refundStatus: refund == null ? null : _text(refund['status']),
      refundAmount: refund == null ? null : _money(refund['amount']),
      flagged: json['flagged'] == true,
      id: _int(json['payoutId']),
      status: PayoutStatus.fromApi(json['status']),
      amount: _money(json['amount']),
      commissionAmount: _money(json['commissionAmount']),
      netAmount: _money(json['netAmount']),
      tutorName: _text(tutor['name']) ?? 'Unknown tutor',
      tutorEmail: _text(tutor['email']),
      booking: booking is Map
          ? PayoutBooking.fromJson(Map<String, dynamic>.from(booking))
          : null,
      createdAt: _time(json['createdAt']),
      approvedAt: _time(json['approvedAt']),
      paidAt: _time(json['paidAt']),
      approvedBy: _text(json['approvedBy']),
    );
  }

  final int id;
  final PayoutStatus status;

  /// Gross amount for the lesson.
  final double amount;
  final double commissionAmount;

  /// What the tutor receives.
  final double netAmount;
  final String tutorName;
  final String? tutorEmail;
  final PayoutBooking? booking;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? paidAt;
  final String? approvedBy;

  /// The administrator who marked it as paid, and the external reference.
  final String? paidBy;
  final String? paymentReference;

  /// The purchase's captured commission rate, e.g. "10.00"; backfilled when
  /// the purchase predates the commission snapshot (migration 013).
  final String? commissionRate;
  final bool commissionRateBackfilled;

  /// A refund recorded for the lesson after this payout was generated
  /// ('pending', 'approved' or 'processed'); the payout itself is unchanged.
  final String? refundStatus;
  final double? refundAmount;
  final bool flagged;
}

/// A reconciliation finding from the backend (lib/payout_finance.dart).
class PayoutIssue {
  const PayoutIssue({
    required this.code,
    required this.message,
    this.severity = 'warning',
    this.count,
    this.amountCents,
  });

  factory PayoutIssue.fromJson(Map<String, dynamic> json) => PayoutIssue(
    code: _text(json['code']) ?? 'unknown',
    message: _text(json['message']) ?? '',
    severity: _text(json['severity']) ?? 'warning',
    count: json['count'] is num ? (json['count'] as num).toInt() : null,
    amountCents: parseCents(json['amount']),
  );

  final String code;
  final String message;
  final String severity;
  final int? count;
  final int? amountCents;

  bool get isWarning => severity != 'info';
}

/// The Payouts page's financial overview, in cents. Definitions:
/// theo_tutoring_backend/lib/payout_finance.dart.
class PayoutFinance {
  const PayoutFinance({
    this.moneyReceived = 0,
    this.platformCommission = 0,
    this.owedToTutors = 0,
    this.paidToTutors = 0,
    this.refunded = 0,
    this.heldForUpcomingLessons = 0,
    this.retainedCancellationRevenue = 0,
    this.awaitingRefundDecision = 0,
    this.awaitingPayoutGeneration = 0,
    this.unallocated = 0,
    this.accountedFor = 0,
    this.difference = 0,
    this.reconciled = true,
    this.eligibleLessons = 0,
    this.awaitingPayoutGenerationCount = 0,
    this.upcomingLessons = 0,
    this.pendingPayouts = 0,
    this.approvedPayouts = 0,
    this.paidPayouts = 0,
    this.issues = const [],
  });

  factory PayoutFinance.fromJson(Map<String, dynamic> json) {
    final counts = json['counts'] is Map
        ? Map<String, dynamic>.from(json['counts'] as Map)
        : const <String, dynamic>{};
    return PayoutFinance(
      moneyReceived: _cents(json['moneyReceived']),
      platformCommission: _cents(json['platformCommission']),
      owedToTutors: _cents(json['owedToTutors']),
      paidToTutors: _cents(json['paidToTutors']),
      refunded: _cents(json['refunded']),
      heldForUpcomingLessons: _cents(json['heldForUpcomingLessons']),
      retainedCancellationRevenue: _cents(
        json['retainedCancellationRevenue'],
      ),
      awaitingRefundDecision: _cents(json['awaitingRefundDecision']),
      awaitingPayoutGeneration: _cents(json['awaitingPayoutGeneration']),
      unallocated: _cents(json['unallocated']),
      accountedFor: _cents(json['accountedFor']),
      difference: _cents(json['difference']),
      reconciled: json['reconciled'] != false,
      eligibleLessons: _int(counts['eligibleLessons']),
      awaitingPayoutGenerationCount: _int(counts['awaitingPayoutGeneration']),
      upcomingLessons: _int(counts['upcomingLessons']),
      pendingPayouts: _int(counts['pendingPayouts']),
      approvedPayouts: _int(counts['approvedPayouts']),
      paidPayouts: _int(counts['paidPayouts']),
      issues: [
        for (final item in (json['issues'] as List?) ?? const [])
          if (item is Map) PayoutIssue.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }

  final int moneyReceived;
  final int platformCommission;
  final int owedToTutors;
  final int paidToTutors;
  final int refunded;
  final int heldForUpcomingLessons;
  final int retainedCancellationRevenue;
  final int awaitingRefundDecision;
  final int awaitingPayoutGeneration;
  final int unallocated;
  final int accountedFor;
  final int difference;
  final bool reconciled;
  final int eligibleLessons;
  final int awaitingPayoutGenerationCount;
  final int upcomingLessons;
  final int pendingPayouts;
  final int approvedPayouts;
  final int paidPayouts;
  final List<PayoutIssue> issues;
}

class PayoutSummary {
  const PayoutSummary({
    this.pendingCount = 0,
    this.pendingNetAmount = 0,
    this.approvedCount = 0,
    this.approvedNetAmount = 0,
    this.paidCount = 0,
    this.paidNetAmount = 0,
  });

  factory PayoutSummary.fromJson(Map<String, dynamic> json) => PayoutSummary(
    pendingCount: _int(json['pendingCount']),
    pendingNetAmount: _money(json['pendingNetAmount']),
    approvedCount: _int(json['approvedCount']),
    approvedNetAmount: _money(json['approvedNetAmount']),
    paidCount: _int(json['paidCount']),
    paidNetAmount: _money(json['paidNetAmount']),
  );

  final int pendingCount;
  final double pendingNetAmount;
  final int approvedCount;
  final double approvedNetAmount;
  final int paidCount;
  final double paidNetAmount;
}

class AdminPayoutsPage {
  const AdminPayoutsPage({
    required this.payouts,
    required this.summary,
    required this.total,
    required this.page,
    required this.pageSize,
    this.adminName,
    this.finance,
  });

  factory AdminPayoutsPage.fromJson(Map<String, dynamic> json) =>
      AdminPayoutsPage(
        adminName: _text(json['adminName']),
        total: _int(json['total']),
        page: _int(json['page']) < 1 ? 1 : _int(json['page']),
        pageSize: _int(json['pageSize']) < 1 ? 20 : _int(json['pageSize']),
        summary: json['summary'] is Map
            ? PayoutSummary.fromJson(
                Map<String, dynamic>.from(json['summary'] as Map),
              )
            : const PayoutSummary(),
        finance: json['finance'] is Map
            ? PayoutFinance.fromJson(
                Map<String, dynamic>.from(json['finance'] as Map),
              )
            : null,
        payouts: [
          for (final item in (json['payouts'] as List?) ?? const [])
            if (item is Map)
              AdminPayout.fromJson(Map<String, dynamic>.from(item)),
        ],
      );

  final String? adminName;
  final List<AdminPayout> payouts;
  final PayoutSummary summary;

  /// Null from a backend without the financial overview.
  final PayoutFinance? finance;

  /// Payouts matching the filter, across every page.
  final int total;
  final int page;
  final int pageSize;

  int get pageCount => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
}
