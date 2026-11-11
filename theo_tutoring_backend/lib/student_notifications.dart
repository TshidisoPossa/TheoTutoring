import 'dart:io';

import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Where the student's bell notifications come from:
//  - their payment went through -> notifyStudentOfPaidPurchase (payment route)
//  - an admin approved or declined their refund
//      -> notifyStudentOfRefund (admin refund approve/deny routes)
//  - a lesson starts within 24 hours
//      -> syncStudentNotifications, run when the student opens the bell
// Every notice has a fixed Firestore id, so nothing is announced twice.

NotificationStore? _store; // shared, so the Google access token is reused

NotificationStore get _sharedStore =>
    _store ??= NotificationStore.fromFirebaseAdmin();

/// Who is calling a /students/notifications route.
class StudentSession {
  /// Creates a session.
  const StudentSession(this.firebaseUid, this.studentId);

  /// Firebase UID (User.FirebaseUid): the student's Firestore folder.
  final String firebaseUid;

  /// StudentProfile.StudentID.
  final int studentId;
}

/// The active student with this Firebase UID, or null if there is none.
Future<StudentSession?> findActiveStudent(
  MySQLConnection conn,
  String firebaseUid,
) async {
  final result = await conn.execute(
    '''
    SELECT sp.StudentID
    FROM `user` u
    INNER JOIN studentprofile sp ON sp.UserID = u.UserId
    WHERE u.FirebaseUid = :uid AND u.Role = 'student'
      AND u.AccountStatus = 'Active'
    LIMIT 1
    ''',
    {'uid': firebaseUid},
  );
  if (result.rows.isEmpty) return null;
  return StudentSession(
    firebaseUid,
    int.parse(result.rows.first.reqStr('StudentID')),
  );
}

/// "250" or "250.5" -> "R250.00"
String rands(String? amount) =>
    'R${(double.tryParse(amount ?? '') ?? 0).toStringAsFixed(2)}';

/// One lesson of a purchase: its booking, "2026-10-28" and "14:00".
typedef PurchasedLesson = ({int bookingId, String date, String startTime});

/// "Your payment of R250.00 went through. Your Maths lesson with Thabo
/// Mokoena on Tue 28 Oct, 14:00 is confirmed."
/// [lessons] are in date order; the card is about the first one.
Notice paidNotice({
  required int purchaseId,
  required String tutorName,
  required String subject,
  required String amount,
  required List<PurchasedLesson> lessons,
}) {
  final first = lessons.first;
  final when = sessionLabel(first.date, first.startTime);
  final paid = 'Your payment of ${rands(amount)} went through.';
  return Notice(
    id: 'paid-$purchaseId',
    type: NotificationType.paymentReceived,
    title: 'Payment successful',
    body: lessons.length == 1
        ? '$paid Your $subject lesson with $tutorName on $when is confirmed.'
        : '$paid Your ${lessons.length} $subject lessons with $tutorName are '
              'confirmed, starting $when.',
    bookingId: first.bookingId,
  );
}

/// "Your Maths lesson with Thabo Mokoena starts in an hour." or
/// "... is tomorrow at 14:00."
Notice studentUpcomingNotice({
  required int bookingId,
  required String tutorName,
  required String subject,
  required String startTime,
  required int minutesUntil,
  required int daysAway,
}) {
  final when = lessonStartsIn(minutesUntil, daysAway, startTime);
  final verb = minutesUntil <= 60 ? 'starts' : 'is';
  return Notice(
    id: 'upcoming-$bookingId-${reminderKind(minutesUntil)}',
    type: NotificationType.upcomingSession,
    title: 'Upcoming lesson',
    body: 'Your $subject lesson with $tutorName $verb $when.',
    bookingId: bookingId,
  );
}

/// "Your refund of R125.00 (50%) for the Maths lesson with Thabo Mokoena on
/// Tue 28 Oct, 14:00 was approved." / "... was declined. Reason: ..."
Notice refundNotice({
  required int refundId,
  required bool approved,
  required int bookingId,
  required String subject,
  required String tutorName,
  required String date,
  required String startTime,
  String? amount,
  String? percentage,
  String? reason,
}) {
  final lesson =
      'the $subject lesson with $tutorName on ${sessionLabel(date, startTime)}';
  final String body;
  if (!approved) {
    final why = reason?.trim() ?? '';
    body =
        'Your refund for $lesson was declined.'
        '${why.isEmpty ? '' : ' Reason: $why'}';
  } else if ((double.tryParse(amount ?? '') ?? 0) <= 0) {
    body =
        'Your refund for $lesson was reviewed. Under the cancellation policy '
        'no money is due back.';
  } else {
    final percent = double.tryParse(percentage ?? '')?.round();
    body =
        'Your refund of ${rands(amount)}'
        '${percent == null ? '' : ' ($percent%)'} for $lesson was approved.';
  }
  return Notice(
    id: 'refund-$refundId',
    type: approved
        ? NotificationType.refundApproved
        : NotificationType.refundDenied,
    title: approved ? 'Refund approved' : 'Refund declined',
    body: body,
    bookingId: bookingId,
  );
}

/// Tells the student their payment for [purchaseId] went through. Called by
/// the payment route after a successful payment. The payment is already
/// saved, so a problem here is only logged. Returns whether they were told.
Future<bool> notifyStudentOfPaidPurchase(int purchaseId) async {
  try {
    final conn = await getConnection(); // shared connection (do not close it)
    final result = await conn.execute(
      '''
      SELECT b.Booking_id, s.subjectName, tu.Name AS TutorName,
        su.FirebaseUid AS StudentUid,
        DATE_FORMAT(b.Date, '%Y-%m-%d') AS LessonDate,
        TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
        (SELECT pp.Amount FROM purchasepayment pp
          WHERE pp.PurchaseID = b.PurchaseID LIMIT 1) AS Amount
      FROM booking b
      INNER JOIN subjects s ON s.subjectId = b.SubjectID
      INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
      INNER JOIN `user` tu ON tu.UserId = tp.UserID
      INNER JOIN studentprofile sp ON sp.StudentID = b.StudentID
      INNER JOIN `user` su ON su.UserId = sp.UserID
      WHERE b.PurchaseID = :purchaseId AND b.Status = 'Confirmed'
      ORDER BY b.Date, b.StartTime
      ''',
      {'purchaseId': purchaseId},
    );
    final rows = result.rows.map((r) => r.textAssoc()).toList();
    if (rows.isEmpty) return false;
    final studentUid = rows.first['StudentUid'];
    if (studentUid == null || studentUid.isEmpty) return false;

    final notice = paidNotice(
      purchaseId: purchaseId,
      tutorName: rows.first['TutorName'] ?? 'your tutor',
      subject: rows.first['subjectName'] ?? '',
      amount: rows.first['Amount'] ?? '0',
      lessons: [
        for (final row in rows)
          (
            bookingId: int.parse(row['Booking_id']!),
            date: row['LessonDate']!,
            startTime: row['StartTime']!,
          ),
      ],
    );
    await notice.sendTo(studentUid, _sharedStore);
    return true;
  } catch (e) {
    stderr.writeln(
      'Could not notify the student about paid purchase $purchaseId: $e',
    );
    return false;
  }
}

/// Tells the student an administrator approved or declined refund
/// [refundId]. Called by the admin refund routes after the decision is
/// saved, so a problem here is only logged. [reason] is the admin's reason
/// for declining. Returns whether the student was told.
Future<bool> notifyStudentOfRefund(int refundId, {String? reason}) async {
  try {
    final conn = await getConnection(); // shared connection (do not close it)
    final result = await conn.execute(
      '''
      SELECT r.RefundStatus, r.RefundAmount, r.RefundPercentage, b.Booking_id,
        s.subjectName, tu.Name AS TutorName, su.FirebaseUid AS StudentUid,
        DATE_FORMAT(b.Date, '%Y-%m-%d') AS LessonDate,
        TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime
      FROM refund r
      INNER JOIN booking b ON b.Booking_id = r.BookingID
      INNER JOIN subjects s ON s.subjectId = b.SubjectID
      INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
      INNER JOIN `user` tu ON tu.UserId = tp.UserID
      INNER JOIN studentprofile sp ON sp.StudentID = b.StudentID
      INNER JOIN `user` su ON su.UserId = sp.UserID
      WHERE r.RefundID = :refundId
      ''',
      {'refundId': refundId},
    );
    if (result.rows.isEmpty) return false;
    final row = result.rows.first.textAssoc();
    final status = row['RefundStatus'];
    final studentUid = row['StudentUid'];
    if (status != 'Approved' && status != 'Denied') return false;
    if (studentUid == null || studentUid.isEmpty) return false;

    final notice = refundNotice(
      refundId: refundId,
      approved: status == 'Approved',
      bookingId: int.parse(row['Booking_id']!),
      subject: row['subjectName'] ?? '',
      tutorName: row['TutorName'] ?? 'your tutor',
      date: row['LessonDate']!,
      startTime: row['StartTime']!,
      amount: row['RefundAmount'],
      percentage: row['RefundPercentage'],
      reason: reason,
    );
    await notice.sendTo(studentUid, _sharedStore);
    return true;
  } catch (e) {
    stderr.writeln('Could not notify the student about refund $refundId: $e');
    return false;
  }
}

/// Adds the student's lesson reminders that are not in Firestore yet. Run
/// when the student opens the bell (the list or the unread badge).
Future<void> syncStudentNotifications(
  MySQLConnection conn,
  NotificationStore store,
  StudentSession student,
) async {
  // Confirmed lessons starting in the next 24 hours (South African time,
  // like the rest of the booking code).
  final upcoming = await conn.execute(
    '''
    SELECT b.Booking_id, s.subjectName, tu.Name AS TutorName,
      TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
      TIMESTAMPDIFF(
        MINUTE, UTC_TIMESTAMP() + INTERVAL 2 HOUR, TIMESTAMP(b.Date, b.StartTime)
      ) AS MinutesUntil,
      DATEDIFF(b.Date, DATE(UTC_TIMESTAMP() + INTERVAL 2 HOUR)) AS DaysAway
    FROM booking b
    INNER JOIN subjects s ON s.subjectId = b.SubjectID
    INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
    INNER JOIN `user` tu ON tu.UserId = tp.UserID
    WHERE b.StudentID = :studentId AND b.Status = 'Confirmed'
      AND TIMESTAMP(b.Date, b.StartTime) > UTC_TIMESTAMP() + INTERVAL 2 HOUR
      AND TIMESTAMP(b.Date, b.StartTime)
        <= UTC_TIMESTAMP() + INTERVAL 2 HOUR + INTERVAL 24 HOUR
    ORDER BY b.Date, b.StartTime
    LIMIT 20
    ''',
    {'studentId': student.studentId},
  );

  final notices = [
    for (final row in upcoming.rows.map((r) => r.textAssoc()))
      studentUpcomingNotice(
        bookingId: int.parse(row['Booking_id']!),
        tutorName: row['TutorName'] ?? 'your tutor',
        subject: row['subjectName'] ?? '',
        startTime: row['StartTime'] ?? '',
        minutesUntil: int.parse(row['MinutesUntil']!),
        daysAway: int.parse(row['DaysAway']!),
      ),
  ];
  await Future.wait([
    for (final n in notices) n.sendTo(student.firebaseUid, store),
  ]);
}
