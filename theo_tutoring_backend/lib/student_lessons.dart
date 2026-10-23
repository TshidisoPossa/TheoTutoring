import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';

/// Booking statuses shown on the student's Upcoming tab (documentation 4.5),
/// plus the tutor's Accepted/Postponed steps from booking_tutor.dart.
const upcomingLessonStatuses = [
  'Pending',
  'Accepted',
  'Postponed',
  'Confirmed',
];

/// Loads the student's Lessons tab (My Schedule) from MySQL.
class MySqlStudentLessonsRepository {
  /// Creates a repository using the supplied MySQL connection.
  MySqlStudentLessonsRepository(this.connection);

  /// Connection shared with the route's authenticated request.
  final MySQLConnection connection;

  Future<int> _studentId(String firebaseUid) async {
    final student = await connection.execute(
      '''
      SELECT sp.StudentID
      FROM `User` u
      INNER JOIN StudentProfile sp ON sp.UserID = u.UserId
      WHERE u.FirebaseUid = :uid
        AND u.Role = 'student'
        AND u.AccountStatus = 'Active'
      LIMIT 1
      ''',
      {'uid': firebaseUid},
    );
    if (student.rows.isEmpty) throw const StudentDashboardDenied();
    return int.parse(student.rows.first.colByName('StudentID')!);
  }

  /// Loads the student's upcoming and cancelled bookings, each with the
  /// tutor's name and photo and the subject the tutor teaches in it.
  Future<Map<String, Object?>> load(String firebaseUid) async {
    final studentId = await _studentId(firebaseUid);

    // Upcoming: lessons that have not ended yet (SAST, as on the dashboard),
    // soonest first. Cancelled: most recent first.
    final result = await connection.execute(
      '''
      SELECT b.Booking_id, b.Status, s.subjectName, tu.Name AS TutorName,
        tu.ProfilePhoto AS TutorPhoto,
        DATE_FORMAT(b.Date, '%Y-%m-%d') AS SessionDate,
        TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
        TIME_FORMAT(b.EndTime, '%H:%i') AS EndTime,
        b.Link, b.CancellationReason
      FROM Booking b
      INNER JOIN TutorProfile tp ON tp.TutorID = b.TutorID
      INNER JOIN `User` tu ON tu.UserId = tp.UserID
      INNER JOIN Subjects s ON s.subjectId = b.SubjectID
      WHERE b.StudentID = :studentId
        AND (
          b.Status = 'Cancelled'
          OR (
            b.Status IN (${upcomingLessonStatuses.map((s) => "'$s'").join(', ')})
            AND TIMESTAMP(b.Date, b.EndTime) >=
                (UTC_TIMESTAMP() + INTERVAL 2 HOUR)
          )
        )
      ORDER BY b.Date ASC, b.StartTime ASC, b.Booking_id ASC
      LIMIT 100
      ''',
      {'studentId': studentId},
    );

    final upcoming = <Map<String, Object?>>[];
    final cancelled = <Map<String, Object?>>[];
    for (final row in result.rows) {
      final status = row.colByName('Status')!;
      final lesson = <String, Object?>{
        'bookingId': int.parse(row.colByName('Booking_id')!),
        'status': status,
        'subject': row.colByName('subjectName'),
        'tutorName': row.colByName('TutorName'),
        'tutorPhoto': row.colByName('TutorPhoto'),
        'date': row.colByName('SessionDate'),
        'startTime': row.colByName('StartTime'),
        'endTime': row.colByName('EndTime'),
        'link': row.colByName('Link'),
        'cancellationReason': row.colByName('CancellationReason'),
      };
      (status == 'Cancelled' ? cancelled : upcoming).add(lesson);
    }
    return {
      'upcoming': upcoming,
      'cancelled': cancelled.reversed.toList(),
    };
  }

  /// Cancels one of the student's upcoming lessons and saves their [reason].
  ///
  /// A paid lesson also gets a Refund record using the policy in
  /// documentation 4.6 (see [refundPercentFor]); an unpaid one is simply
  /// cancelled.
  Future<LessonCancellation> cancel(
    String firebaseUid,
    int bookingId,
    String reason,
  ) async {
    final studentId = await _studentId(firebaseUid);
    return connection.transactional((tx) async {
      final booking = await tx.execute(
        '''
        SELECT b.Status, b.PurchaseID, b.LessonPriceAtPurchase,
          s.subjectName, tu.FirebaseUid AS TutorUid, su.Name AS StudentName,
          DATE_FORMAT(b.Date, '%Y-%m-%d') AS SessionDate,
          TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
          TIMESTAMPDIFF(
            MINUTE,
            UTC_TIMESTAMP() + INTERVAL 2 HOUR,
            TIMESTAMP(b.Date, b.StartTime)
          ) AS MinutesBefore
        FROM Booking b
        INNER JOIN Subjects s ON s.subjectId = b.SubjectID
        INNER JOIN TutorProfile tp ON tp.TutorID = b.TutorID
        INNER JOIN `User` tu ON tu.UserId = tp.UserID
        INNER JOIN StudentProfile sp ON sp.StudentID = b.StudentID
        INNER JOIN `User` su ON su.UserId = sp.UserID
        WHERE b.Booking_id = :bookingId AND b.StudentID = :studentId
        FOR UPDATE OF b
        ''',
        {'bookingId': bookingId, 'studentId': studentId},
      );
      if (booking.rows.isEmpty) {
        throw const LessonActionException(404, 'Lesson not found.');
      }
      final row = booking.rows.first;
      if (!upcomingLessonStatuses.contains(row.colByName('Status'))) {
        throw const LessonActionException(
          409,
          'This lesson can no longer be cancelled.',
        );
      }
      final minutesBefore = int.parse(row.colByName('MinutesBefore')!);
      if (minutesBefore <= 0) {
        throw const LessonActionException(
          409,
          'This lesson has already started.',
        );
      }

      // What the student paid for this lesson, if anything: a direct
      // Payment, or this lesson's price in a paid package.
      final purchaseId = row.colByName('PurchaseID');
      final paid = purchaseId == null
          ? await tx.execute(
              '''
              SELECT Amount FROM Payment
              WHERE BookingId = :bookingId AND PaymentStatus = 'Successful'
              ''',
              {'bookingId': bookingId},
            )
          : await tx.execute(
              '''
              SELECT :price AS Amount FROM PurchasePayment
              WHERE PurchaseID = :purchaseId
              ''',
              {
                'purchaseId': purchaseId,
                'price': row.colByName('LessonPriceAtPurchase'),
              },
            );

      int? refundPercent;
      String? refundAmount;
      if (paid.rows.isNotEmpty) {
        refundPercent = refundPercentFor(minutesBefore);
        final paidCents = _cents(paid.rows.first.colByName('Amount')!);
        refundAmount = _rands(paidCents * refundPercent ~/ 100);
        await tx.execute(
          '''
          INSERT INTO Refund
            (BookingID, RefundPercentage, RefundAmount, RefundStatus)
          VALUES (:bookingId, :percent, :amount, 'Pending')
          ''',
          {
            'bookingId': bookingId,
            'percent': refundPercent,
            'amount': refundAmount,
          },
        );
      }

      await tx.execute(
        '''
        UPDATE Booking
        SET Status = 'Cancelled', CancellationReason = :reason
        WHERE Booking_id = :bookingId
        ''',
        {'bookingId': bookingId, 'reason': reason},
      );

      return LessonCancellation(
        bookingId: bookingId,
        subject: row.colByName('subjectName')!,
        date: row.colByName('SessionDate')!,
        startTime: row.colByName('StartTime')!,
        studentName: row.colByName('StudentName')!,
        tutorFirebaseUid: row.colByName('TutorUid'),
        refundPercentage: refundPercent,
        refundAmount: refundAmount,
      );
    });
  }

  // "250.00" -> 25000
  static int _cents(String amount) {
    final parts = amount.split('.');
    final cents = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    return int.parse(parts[0]) * 100 + int.parse(cents.substring(0, 2));
  }

  // 12500 -> "125.00"
  static String _rands(int cents) =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

/// Refund percentage for cancelling [minutesBefore] the lesson starts
/// (documentation 4.6): 48 hours or more 100%, 24 hours or more 50%,
/// otherwise nothing.
int refundPercentFor(int minutesBefore) {
  if (minutesBefore >= 48 * 60) return 100;
  if (minutesBefore >= 24 * 60) return 50;
  return 0;
}

/// The outcome of a student cancelling a lesson.
class LessonCancellation {
  /// Creates the outcome.
  const LessonCancellation({
    required this.bookingId,
    required this.subject,
    required this.date,
    required this.startTime,
    required this.studentName,
    required this.tutorFirebaseUid,
    required this.refundPercentage,
    required this.refundAmount,
  });

  /// The cancelled booking.
  final int bookingId;

  /// Subject name, for the tutor's notification.
  final String subject;

  /// Lesson date, e.g. "2026-10-30".
  final String date;

  /// Lesson start, e.g. "10:00".
  final String startTime;

  /// Who cancelled, for the tutor's notification.
  final String studentName;

  /// The tutor to notify, if they have a Firebase account.
  final String? tutorFirebaseUid;

  /// 100, 50 or 0 for a paid lesson; null when nothing was paid.
  final int? refundPercentage;

  /// Amount refunded, e.g. "250.00"; null when nothing was paid.
  final String? refundAmount;
}

/// A cancel or report request the student is not allowed to make.
class LessonActionException implements Exception {
  /// Creates the exception with the HTTP status to return.
  const LessonActionException(this.statusCode, this.message);

  /// HTTP status for the route.
  final int statusCode;

  /// Message shown to the student.
  final String message;
}
