import 'package:intl/intl.dart';

// Expected backend responses (Dart Frog):

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _int(dynamic v) => (_num(v) ?? 0).toInt();

String? _text(dynamic v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
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

class PayoutItem {
  final String id;
  final String tutorName;
  final String? photoUrl;
  final String subject;
  final double amount;
  final String status;

  const PayoutItem({
    required this.id,
    required this.tutorName,
    required this.photoUrl,
    required this.subject,
    required this.amount,
    required this.status,
  });

  factory PayoutItem.fromJson(Map<String, dynamic> j) => PayoutItem(
    id: j['id'].toString(),
    tutorName: (j['tutorName'] ?? '').toString(),
    photoUrl: _text(j['photoUrl']),
    subject: (j['subject'] ?? '').toString(),
    amount: _num(j['amount']) ?? 0,
    status: (j['status'] ?? '').toString(),
  );

  String get initials => _initialsOf(tutorName);
}

class TransactionItem {
  final String id;
  final DateTime date;
  final String studentName;
  final String? studentPhotoUrl;
  final String tutorName;
  final String subject;
  final double amount;
  final String status;

  const TransactionItem({
    required this.id,
    required this.date,
    required this.studentName,
    required this.studentPhotoUrl,
    required this.tutorName,
    required this.subject,
    required this.amount,
    required this.status,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> j) => TransactionItem(
    id: j['id'].toString(),
    date: DateTime.parse(j['date'].toString()),
    studentName: (j['studentName'] ?? '').toString(),
    studentPhotoUrl: _text(j['studentPhotoUrl']),
    tutorName: (j['tutorName'] ?? '').toString(),
    subject: (j['subject'] ?? '').toString(),
    amount: _num(j['amount']) ?? 0,
    status: (j['status'] ?? '').toString(),
  );

  String get studentInitials => _initialsOf(studentName);
}

class SubjectRevenue {
  final String subject;
  final double revenue;

  const SubjectRevenue({required this.subject, required this.revenue});

  factory SubjectRevenue.fromJson(Map<String, dynamic> j) => SubjectRevenue(
    subject: (j['subject'] ?? '').toString(),
    revenue: _num(j['revenue']) ?? 0,
  );
}

class FinancialOverview {
  final String adminName;
  final double grossRevenue;
  final double? grossRevenueChange;
  final double? previousGrossRevenue;
  final double netProfit;
  final double? netProfitChange;
  final double pendingPayouts;
  final int? payoutDueInDays;
  final int pendingPayoutTutors;
  final int payoutReadyCount;
  final List<PayoutItem> payoutQueue;
  final List<TransactionItem> transactions;

  const FinancialOverview({
    required this.adminName,
    required this.grossRevenue,
    required this.grossRevenueChange,
    required this.previousGrossRevenue,
    required this.netProfit,
    required this.netProfitChange,
    required this.pendingPayouts,
    required this.payoutDueInDays,
    required this.pendingPayoutTutors,
    required this.payoutReadyCount,
    required this.payoutQueue,
    required this.transactions,
  });

  factory FinancialOverview.fromJson(Map<String, dynamic> j) =>
      FinancialOverview(
        adminName: (j['adminName'] ?? '').toString(),
        grossRevenue: _num(j['grossRevenue']) ?? 0,
        grossRevenueChange: _num(j['grossRevenueChange']),
        previousGrossRevenue: _num(j['previousGrossRevenue']),
        netProfit: _num(j['netProfit']) ?? 0,
        netProfitChange: _num(j['netProfitChange']),
        pendingPayouts: _num(j['pendingPayouts']) ?? 0,
        payoutDueInDays: j['payoutDueInDays'] == null
            ? null
            : _int(j['payoutDueInDays']),
        pendingPayoutTutors: _int(j['pendingPayoutTutors']),
        payoutReadyCount: _int(j['payoutReadyCount']),
        payoutQueue: ((j['payoutQueue'] ?? []) as List<dynamic>)
            .map((e) => PayoutItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        transactions: ((j['transactions'] ?? []) as List<dynamic>)
            .map((e) => TransactionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

final _money = NumberFormat('#,##0.00');

/// 2565000 -> R 2,565,000.00
String formatRandFull(double v) => 'R ${_money.format(v)}';

/// 12.4 -> +12.4%, -2 -> -2.0%
String signedPercent(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}%';
