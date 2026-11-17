import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';

// The receipt for a paid booking purchase
// (GET /StudentlandingPage/booking-purchases/<PurchaseID>/receipt).
//
// Everything comes from what was saved at payment time, so the receipt
// always matches what was charged: the purchase's rate, subtotal, discount
// and total (bookingpurchase), the settled amount and time (purchasepayment)
// and the successful attempt's method (paymentattempt). Lessons show their
// current date, time and status, so a rescheduled or cancelled lesson is
// shown as it is now; refunds recorded for them are listed too.

/// Why a receipt cannot be given; [statusCode] is the HTTP status.
class ReceiptException implements Exception {
  /// Creates the exception.
  const ReceiptException(this.statusCode, this.message);

  /// HTTP status for the response.
  final int statusCode;

  /// Message shown to the student.
  final String message;
}

const _paymentMethodLabels = {
  'CreditDebitCard': 'Credit/Debit card',
  'PayPal': 'PayPal',
  'EFT': 'EFT',
};

/// "2026-11-16 19:32:52.000929" (UTC) -> "2026-11-16 21:32" (South Africa)
String? _saTime(String? utc) {
  if (utc == null) return null;
  final parsed = DateTime.tryParse('${utc.replaceFirst(' ', 'T')}Z');
  if (parsed == null) return null;
  final sa = parsed.add(const Duration(hours: 2));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${sa.year}-${two(sa.month)}-${two(sa.day)} '
      '${two(sa.hour)}:${two(sa.minute)}';
}

/// "185.00" -> "185.00"; null and odd values become "0.00".
String _money(String? value) {
  final parsed = double.tryParse(value ?? '');
  return (parsed ?? 0).toStringAsFixed(2);
}

/// Loads the receipt for the signed-in student's purchase [purchaseId].
///
/// Throws [ReceiptException]: 403 for a non-student, 404 when the purchase
/// is not theirs, 409 when it has not been paid.
Future<Map<String, Object?>> loadBookingReceipt(
  MySQLConnection connection, {
  required String firebaseUid,
  required int purchaseId,
}) async {
  final student = await connection.execute(
    '''
    SELECT sp.StudentID, u.Name, u.Email
    FROM `user` u
    INNER JOIN studentprofile sp ON sp.UserID = u.UserId
    WHERE u.FirebaseUid = :uid AND u.Role = 'student'
      AND u.AccountStatus = 'Active'
    LIMIT 1
    ''',
    {'uid': firebaseUid},
  );
  if (student.rows.isEmpty) {
    throw const ReceiptException(403, 'An active student account is required.');
  }
  final studentRow = student.rows.first;
  final studentId = int.parse(studentRow.reqStr('StudentID'));

  final purchase = await connection.execute(
    '''
    SELECT p.PurchaseID, p.PurchaseType, p.LessonCount, p.RatePerLesson,
      p.SubtotalAmount, p.DiscountPercent, p.DiscountAmount, p.TotalAmount,
      p.PurchaseStatus, s.subjectName, tu.Name AS TutorName,
      pp.Amount AS PaidAmount, pp.CreatedAtUtc AS PaidAtUtc,
      pa.PaymentAttemptID, pa.PaymentMethod, pa.PaymentMode,
      pa.PaymentReference
    FROM bookingpurchase p
    INNER JOIN subjects s ON s.subjectId = p.SubjectID
    INNER JOIN tutorprofile tp ON tp.TutorID = p.TutorID
    INNER JOIN `user` tu ON tu.UserId = tp.UserID
    LEFT JOIN purchasepayment pp ON pp.PurchaseID = p.PurchaseID
    LEFT JOIN paymentattempt pa ON pa.PaymentAttemptID = pp.PaymentAttemptID
    WHERE p.PurchaseID = :purchaseId AND p.StudentID = :studentId
    ORDER BY pp.PurchasePaymentID
    LIMIT 1
    ''',
    {'purchaseId': purchaseId, 'studentId': studentId},
  );
  if (purchase.rows.isEmpty) {
    throw const ReceiptException(404, 'Booking not found.');
  }
  final p = purchase.rows.first;
  if (p.str('PaidAtUtc') == null) {
    throw const ReceiptException(
      409,
      'This booking has not been paid, so there is no receipt yet.',
    );
  }

  final lessons = await connection.execute(
    '''
    SELECT b.Booking_id, b.LessonNumber, b.Status, b.LessonPriceAtPurchase,
      DATE_FORMAT(b.Date, '%Y-%m-%d') AS LessonDate,
      TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
      TIME_FORMAT(b.EndTime, '%H:%i') AS EndTime
    FROM booking b
    WHERE b.PurchaseID = :purchaseId
    ORDER BY b.LessonNumber, b.Booking_id
    ''',
    {'purchaseId': purchaseId},
  );

  final refunds = await connection.execute(
    '''
    SELECT r.BookingID, r.RefundAmount, r.RefundPercentage, r.RefundStatus
    FROM refund r
    INNER JOIN booking b ON b.Booking_id = r.BookingID
    WHERE b.PurchaseID = :purchaseId AND r.RefundStatus <> 'Rejected'
    ORDER BY r.RefundID
    ''',
    {'purchaseId': purchaseId},
  );

  final method = p.str('PaymentMethod');
  return {
    // TT-000016: the purchase id, so it matches the booking everywhere
    'receiptNumber': 'TT-${purchaseId.toString().padLeft(6, '0')}',
    'purchaseId': purchaseId,
    'paymentAttemptId': int.tryParse(p.str('PaymentAttemptID') ?? ''),
    'paidAt': _saTime(p.str('PaidAtUtc')), // South African time
    'purchaseStatus': p.str('PurchaseStatus'),
    'student': {
      'name': studentRow.str('Name'),
      'email': studentRow.str('Email'),
    },
    'tutorName': p.str('TutorName'),
    'subject': p.str('subjectName'),
    'purchaseType': p.str('PurchaseType'), // Single or Package
    'lessonCount':
        int.tryParse(p.str('LessonCount') ?? '') ?? lessons.rows.length,
    'ratePerLesson': _money(p.str('RatePerLesson')),
    'subtotal': _money(p.str('SubtotalAmount')),
    'discountPercent': (double.tryParse(p.str('DiscountPercent') ?? '') ?? 0)
        .round(),
    'discountAmount': _money(p.str('DiscountAmount')),
    'total': _money(p.str('TotalAmount')),
    'amountPaid': _money(p.str('PaidAmount')),
    'currency': 'ZAR',
    'paymentMethod': _paymentMethodLabels[method] ?? method,
    'paymentMode': p.str('PaymentMode'), // Demo: no real money moved
    'paymentReference': p.str('PaymentReference'),
    'lessons': [
      for (final l in lessons.rows)
        {
          'bookingId': int.parse(l.reqStr('Booking_id')),
          'lessonNumber': int.tryParse(l.str('LessonNumber') ?? ''),
          'date': l.str('LessonDate'),
          'startTime': l.str('StartTime'),
          'endTime': l.str('EndTime'),
          'status': l.str('Status'),
          'price': _money(l.str('LessonPriceAtPurchase')),
        },
    ],
    'refunds': [
      for (final r in refunds.rows)
        {
          'bookingId': int.tryParse(r.str('BookingID') ?? ''),
          'amount': _money(r.str('RefundAmount')),
          'percentage': (double.tryParse(r.str('RefundPercentage') ?? '') ?? 0)
              .round(),
          'status': r.str('RefundStatus'),
        },
    ],
  };
}
