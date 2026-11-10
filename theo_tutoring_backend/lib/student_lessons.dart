import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_reviews.dart';

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

    // Completed: lessons that have taken place, most recent first, with the
    // student's own rating once they have reviewed it (null = can review).
    final completedResult = await connection.execute(
      '''
      SELECT b.Booking_id, s.subjectName, tu.Name AS TutorName,
        tu.ProfilePhoto AS TutorPhoto,
        DATE_FORMAT(b.Date, '%Y-%m-%d') AS SessionDate,
        TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
        TIME_FORMAT(b.EndTime, '%H:%i') AS EndTime,
        r.Rating AS MyRating,
        tp.AveRate AS TutorRating, tp.VerificationStat AS TutorVerification,
        (SELECT COUNT(*) FROM Reviews r2 WHERE r2.TutorID = tp.TutorID)
          AS TutorReviewCount,
        (SELECT GROUP_CONCAT(s2.subjectName ORDER BY s2.subjectName
                             SEPARATOR ', ')
         FROM TutorSubjects ts
         INNER JOIN Subjects s2 ON s2.subjectId = ts.SubjectID
         WHERE ts.TutorID = tp.TutorID) AS TutorSubjects
      FROM Booking b
      INNER JOIN TutorProfile tp ON tp.TutorID = b.TutorID
      INNER JOIN `User` tu ON tu.UserId = tp.UserID
      INNER JOIN Subjects s ON s.subjectId = b.SubjectID
      LEFT JOIN Reviews r ON r.BookingID = b.Booking_id
      WHERE b.StudentID = :studentId AND $completedLessonSql
      ORDER BY b.Date DESC, b.StartTime DESC, b.Booking_id DESC
      LIMIT 50
      ''',
      {'studentId': studentId},
    );
    final completed = [
      for (final row in completedResult.rows)
        <String, Object?>{
          'bookingId': int.parse(row.colByName('Booking_id')!),
          'status': 'Completed',
          'subject': row.colByName('subjectName'),
          'tutorName': row.colByName('TutorName'),
          'tutorPhoto': row.colByName('TutorPhoto'),
          'date': row.colByName('SessionDate'),
          'startTime': row.colByName('StartTime'),
          'endTime': row.colByName('EndTime'),
          'myRating': int.tryParse(row.colByName('MyRating') ?? ''),
          // For the Leave a Review page's header
          'tutorRating': double.tryParse(row.colByName('TutorRating') ?? ''),
          'tutorReviewCount':
              int.tryParse(row.colByName('TutorReviewCount') ?? '') ?? 0,
          'tutorVerified': row.colByName('TutorVerification') == 'Approved',
          'tutorSubjects': row.colByName('TutorSubjects'),
        },
    ];

    // Who is reviewing, for the "Lerato Dube (Year 2)" line
    final me = await connection.execute(
      '''
      SELECT u.Name, sp.InstitutionYear, sp.Institution
      FROM StudentProfile sp
      INNER JOIN `User` u ON u.UserId = sp.UserID
      WHERE sp.StudentID = :studentId
      ''',
      {'studentId': studentId},
    );
    final meRow = me.rows.isEmpty ? null : me.rows.first;

    return {
      'upcoming': upcoming,
      'completed': completed,
      'cancelled': cancelled.reversed.toList(),
      'student': {
        'name': meRow?.colByName('Name'),
        'year': meRow?.colByName('InstitutionYear'),
        'institution': meRow?.colByName('Institution'),
      },
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

      int? refundPercent;
      String? refundAmount;
      final paid = await lessonAmountPaid(
        tx,
        bookingId: bookingId,
        purchaseId: row.colByName('PurchaseID'),
        lessonPrice: row.colByName('LessonPriceAtPurchase'),
      );
      if (paid != null) {
        refundPercent = refundPercentFor(minutesBefore);
        refundAmount = await recordPendingRefund(
          tx,
          bookingId: bookingId,
          paidAmount: paid,
          percent: refundPercent,
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
}

/// What the student paid for a lesson, e.g. "250.00", or null if nothing
/// was paid: a direct Payment, or the lesson's price in a paid package.
/// Used by both student and tutor cancellations.
Future<String?> lessonAmountPaid(
  MySQLConnection tx, {
  required int bookingId,
  required String? purchaseId,
  required String? lessonPrice,
}) async {
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
          {'purchaseId': purchaseId, 'price': lessonPrice},
        );
  return paid.rows.isEmpty ? null : paid.rows.first.colByName('Amount');
}

/// Saves a Pending Refund of [percent] of [paidAmount] for the admin to
/// approve (documentation 4.6). Returns the refund amount, e.g. "125.00".
Future<String> recordPendingRefund(
  MySQLConnection tx, {
  required int bookingId,
  required String paidAmount,
  required int percent,
}) async {
  final amount = refundAmountOf(paidAmount, percent);
  await tx.execute(
    '''
    INSERT INTO Refund
      (BookingID, RefundPercentage, RefundAmount, RefundStatus)
    VALUES (:bookingId, :percent, :amount, 'Pending')
    ''',
    {'bookingId': bookingId, 'percent': percent, 'amount': amount},
  );
  return amount;
}

/// [percent] of [paidAmount] in rands: ("250.00", 50) -> "125.00".
String refundAmountOf(String paidAmount, int percent) {
  final parts = paidAmount.split('.');
  final decimals = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  final cents = int.parse(parts[0]) * 100 + int.parse(decimals.substring(0, 2));
  final refund = cents * percent ~/ 100;
  return '${refund ~/ 100}.${(refund % 100).toString().padLeft(2, '0')}';
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
