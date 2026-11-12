import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
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

/// How early a student can join a lesson: 15 minutes before it starts.
const joinWindowSeconds = 15 * 60;

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
      FROM `user` u
      INNER JOIN studentprofile sp ON sp.UserID = u.UserId
      WHERE u.FirebaseUid = :uid
        AND u.Role = 'student'
        AND u.AccountStatus = 'Active'
      LIMIT 1
      ''',
      {'uid': firebaseUid},
    );
    if (student.rows.isEmpty) throw const StudentDashboardDenied();
    return int.parse(student.rows.first.reqStr('StudentID'));
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
        b.CancellationReason
      FROM booking b
      INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
      INNER JOIN `user` tu ON tu.UserId = tp.UserID
      INNER JOIN subjects s ON s.subjectId = b.SubjectID
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
      final status = row.reqStr('Status');
      final lesson = <String, Object?>{
        'bookingId': int.parse(row.reqStr('Booking_id')),
        'status': status,
        'subject': row.str('subjectName'),
        'tutorName': row.str('TutorName'),
        'tutorPhoto': row.str('TutorPhoto'),
        'date': row.str('SessionDate'),
        'startTime': row.str('StartTime'),
        'endTime': row.str('EndTime'),
        // No 'link' here: students only get the Meet link from the join
        // route (POST /students/lessons/<id>/join), at lesson time.
        'cancellationReason': row.str('CancellationReason'),
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
        (SELECT COUNT(*) FROM reviews r2 WHERE r2.TutorID = tp.TutorID)
          AS TutorReviewCount,
        (SELECT GROUP_CONCAT(s2.subjectName ORDER BY s2.subjectName
                             SEPARATOR ', ')
         FROM tutorsubjects ts
         INNER JOIN subjects s2 ON s2.subjectId = ts.SubjectID
         WHERE ts.TutorID = tp.TutorID) AS TutorSubjects
      FROM booking b
      INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
      INNER JOIN `user` tu ON tu.UserId = tp.UserID
      INNER JOIN subjects s ON s.subjectId = b.SubjectID
      LEFT JOIN reviews r ON r.BookingID = b.Booking_id
      WHERE b.StudentID = :studentId AND $completedLessonSql
      ORDER BY b.Date DESC, b.StartTime DESC, b.Booking_id DESC
      LIMIT 50
      ''',
      {'studentId': studentId},
    );
    final completed = [
      for (final row in completedResult.rows)
        <String, Object?>{
          'bookingId': int.parse(row.reqStr('Booking_id')),
          'status': 'Completed',
          'subject': row.str('subjectName'),
          'tutorName': row.str('TutorName'),
          'tutorPhoto': row.str('TutorPhoto'),
          'date': row.str('SessionDate'),
          'startTime': row.str('StartTime'),
          'endTime': row.str('EndTime'),
          'myRating': int.tryParse(row.str('MyRating') ?? ''),
          // For the Leave a Review page's header
          'tutorRating': double.tryParse(row.str('TutorRating') ?? ''),
          'tutorReviewCount':
              int.tryParse(row.str('TutorReviewCount') ?? '') ?? 0,
          'tutorVerified': row.str('TutorVerification') == 'Approved',
          'tutorSubjects': row.str('TutorSubjects'),
        },
    ];

    // Who is reviewing, for the "Lerato Dube (Year 2)" line
    final me = await connection.execute(
      '''
      SELECT u.Name, sp.InstitutionYear, sp.Institution
      FROM studentprofile sp
      INNER JOIN `user` u ON u.UserId = sp.UserID
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
        'name': meRow?.str('Name'),
        'year': meRow?.str('InstitutionYear'),
        'institution': meRow?.str('Institution'),
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
        FROM booking b
        INNER JOIN subjects s ON s.subjectId = b.SubjectID
        INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
        INNER JOIN `user` tu ON tu.UserId = tp.UserID
        INNER JOIN studentprofile sp ON sp.StudentID = b.StudentID
        INNER JOIN `user` su ON su.UserId = sp.UserID
        WHERE b.Booking_id = :bookingId AND b.StudentID = :studentId
        FOR UPDATE OF b
        ''',
        {'bookingId': bookingId, 'studentId': studentId},
      );
      if (booking.rows.isEmpty) {
        throw const LessonActionException(404, 'Lesson not found.');
      }
      final row = booking.rows.first;
      if (!upcomingLessonStatuses.contains(row.str('Status'))) {
        throw const LessonActionException(
          409,
          'This lesson can no longer be cancelled.',
        );
      }
      final minutesBefore = int.parse(row.reqStr('MinutesBefore'));
      if (minutesBefore <= 0) {
        throw const LessonActionException(
          409,
          'This lesson has already started.',
        );
      }

      // What the student paid for this lesson, if anything: a direct
      // Payment, or this lesson's price in a paid package.
      int? refundPercent;
      String? refundAmount;
      final paid = await lessonAmountPaid(
        tx,
        bookingId: bookingId,
        purchaseId: row.str('PurchaseID'),
        lessonPrice: row.str('LessonPriceAtPurchase'),
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
        UPDATE booking
        SET Status = 'Cancelled', CancellationReason = :reason
        WHERE Booking_id = :bookingId
        ''',
        {'bookingId': bookingId, 'reason': reason},
      );

      return LessonCancellation(
        bookingId: bookingId,
        subject: row.reqStr('subjectName'),
        date: row.reqStr('SessionDate'),
        startTime: row.reqStr('StartTime'),
        studentName: row.reqStr('StudentName'),
        tutorFirebaseUid: row.str('TutorUid'),
        refundPercentage: refundPercent,
        refundAmount: refundAmount,
      );
    });
  }

  /// Returns the Google Meet link for one of the student's own lessons, once
  /// the join rules allow it (Google Meet design, section 3):
  ///
  /// * the lesson belongs to this student (404 otherwise);
  /// * it is Confirmed or Postponed, and a Postponed lesson was paid for
  ///   (tutors can also postpone Pending lessons);
  /// * it starts in 15 minutes or less and has not ended;
  /// * the tutor has a link.
  ///
  /// Every other failure is a 409 with the message shown to the student.
  Future<String> joinLink(String firebaseUid, int bookingId) async {
    final studentId = await _studentId(firebaseUid);
    // Times are South African, as everywhere else in this file. SECOND (not
    // MINUTE) so the window opens at exactly 15:00 before the start:
    // TIMESTAMPDIFF(MINUTE, ...) would round 15:59 down to 15.
    final booking = await connection.execute(
      '''
      SELECT b.Status, b.PurchaseID, b.LessonPriceAtPurchase,
        COALESCE(b.Link, tp.MeetLink) AS Link,
        TIMESTAMPDIFF(
          SECOND,
          UTC_TIMESTAMP() + INTERVAL 2 HOUR,
          TIMESTAMP(b.Date, b.StartTime)
        ) AS SecondsToStart,
        TIMESTAMPDIFF(
          SECOND,
          UTC_TIMESTAMP() + INTERVAL 2 HOUR,
          TIMESTAMP(b.Date, b.EndTime)
        ) AS SecondsToEnd
      FROM booking b
      INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
      WHERE b.Booking_id = :bookingId AND b.StudentID = :studentId
      ''',
      {'bookingId': bookingId, 'studentId': studentId},
    );
    if (booking.rows.isEmpty) {
      throw const LessonActionException(404, 'Lesson not found.');
    }
    final row = booking.rows.first;

    const cannotJoin = LessonActionException(
      409,
      "This lesson can't be joined.",
    );
    final status = row.str('Status');
    if (status != 'Confirmed' && status != 'Postponed') throw cannotJoin;
    if (status == 'Postponed') {
      final paidAmount = await lessonAmountPaid(
        connection,
        bookingId: bookingId,
        purchaseId: row.str('PurchaseID'),
        lessonPrice: row.str('LessonPriceAtPurchase'),
      );
      if (paidAmount == null) throw cannotJoin;
    }

    if (int.parse(row.reqStr('SecondsToStart')) > joinWindowSeconds) {
      throw const LessonActionException(
        409,
        'This session opens 15 minutes before it starts.',
      );
    }
    if (int.parse(row.reqStr('SecondsToEnd')) <= 0) {
      throw const LessonActionException(409, 'This session has ended.');
    }

    final link = row.str('Link')?.trim();
    if (link == null || link.isEmpty) {
      throw const LessonActionException(
        409,
        "Your tutor hasn't connected Google Meet yet.",
      );
    }
    return link;
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
          SELECT Amount FROM payment
          WHERE BookingId = :bookingId AND PaymentStatus = 'Successful'
          ''',
          {'bookingId': bookingId},
        )
      : await tx.execute(
          '''
          SELECT :price AS Amount FROM purchasepayment
          WHERE PurchaseID = :purchaseId
          ''',
          {'purchaseId': purchaseId, 'price': lessonPrice},
        );
  return paid.rows.isEmpty ? null : paid.rows.first.str('Amount');
}

/// Saves a Pending Refund of [percent] of [paidAmount] for the admin to
/// approve (documentation 4.6). Returns the refund amount, e.g. "125.00".
/// Throws [RefundAlreadyExists] when the booking already has a refund.
Future<String> recordPendingRefund(
  MySQLConnection tx, {
  required int bookingId,
  required String paidAmount,
  required int percent,
}) async {
  final existing = await tx.execute(
    'SELECT RefundID FROM Refund WHERE BookingID = :bookingId FOR UPDATE',
    {'bookingId': bookingId},
  );
  if (existing.rows.isNotEmpty) throw const RefundAlreadyExists();

  final amount = refundAmountOf(paidAmount, percent);
  await tx.execute(
    '''
    INSERT INTO refund
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

/// A cancel, report or join request the student is not allowed to make.
class LessonActionException implements Exception {
  /// Creates the exception with the HTTP status to return.
  const LessonActionException(this.statusCode, this.message);

  /// HTTP status for the route.
  final int statusCode;

  /// Message shown to the student.
  final String message;
}

/// A refund was already recorded for the booking.
class RefundAlreadyExists extends LessonActionException {
  /// Creates the exception.
  const RefundAlreadyExists()
    : super(409, 'A refund has already been recorded for this lesson.');
}
