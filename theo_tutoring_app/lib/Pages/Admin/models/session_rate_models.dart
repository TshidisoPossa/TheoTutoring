import 'package:intl/intl.dart';

// Admin settings: the fixed session rate (project documentation sections 2.3,
// 5 rule 6, FR27 and the SessionRate table in 11.1). Tutors never set prices;
// the latest rate applies to new bookings and older rates are kept so past
// payments still make sense.
//
// Expected backend response (Dart Frog):
// GET /admin/session-rate
//   { "adminName": "...",
//     "current": { "id", "amount", "effectiveFrom", "setBy" } | null,
//     "history": [ { "id", "amount", "effectiveFrom", "setBy" } ] }
//
// POST /admin/session-rate  { "amount": 350.00, "effectiveFrom": "yyyy-MM-dd" }
//   201 -> { "id", "amount", "effectiveFrom", "setBy" }
//   400 -> { "error": "..." } when the amount or date is invalid

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

final _money = NumberFormat('#,##0.00');
String formatRand(double v) => 'R ${_money.format(v)}';

final _day = DateFormat('d MMM yyyy');
String formatRateDate(DateTime d) => _day.format(d);

class SessionRate {
  final String id;
  final double amount;
  final DateTime effectiveFrom;
  final String? setBy;

  const SessionRate({
    required this.id,
    required this.amount,
    required this.effectiveFrom,
    required this.setBy,
  });

  factory SessionRate.fromJson(Map<String, dynamic> j) => SessionRate(
    id: j['id'].toString(),
    amount: _num(j['amount']) ?? 0,
    effectiveFrom:
        DateTime.tryParse(j['effectiveFrom']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    setBy: _text(j['setBy']),
  );

  /// A rate that starts in the future has been scheduled but is not live yet.
  bool get isScheduled => effectiveFrom.isAfter(DateTime.now());
}

class SessionRateResult {
  final String adminName;
  final SessionRate? current;
  final List<SessionRate> history;

  const SessionRateResult({
    required this.adminName,
    required this.current,
    required this.history,
  });

  factory SessionRateResult.fromJson(Map<String, dynamic> j) =>
      SessionRateResult(
        adminName: (j['adminName'] ?? '').toString(),
        current: j['current'] is Map<String, dynamic>
            ? SessionRate.fromJson(j['current'] as Map<String, dynamic>)
            : null,
        history: ((j['history'] as List<dynamic>?) ?? const [])
            .map((e) => SessionRate.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
