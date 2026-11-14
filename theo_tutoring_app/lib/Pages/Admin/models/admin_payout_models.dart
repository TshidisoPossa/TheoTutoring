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
  });

  factory AdminPayout.fromJson(Map<String, dynamic> json) {
    final tutor = json['tutor'] is Map
        ? Map<String, dynamic>.from(json['tutor'] as Map)
        : const <String, dynamic>{};
    final booking = json['booking'];
    return AdminPayout(
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
        payouts: [
          for (final item in (json['payouts'] as List?) ?? const [])
            if (item is Map)
              AdminPayout.fromJson(Map<String, dynamic>.from(item)),
        ],
      );

  final String? adminName;
  final List<AdminPayout> payouts;
  final PayoutSummary summary;

  /// Payouts matching the filter, across every page.
  final int total;
  final int page;
  final int pageSize;

  int get pageCount => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
}
