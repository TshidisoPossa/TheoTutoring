import 'dart:io';

import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Where the tutor's bell notifications come from:
//  - a student paid for lessons -> notifyTutorOfPaidPurchase (payment route)
//  - a student cancelled        -> students/lessons/[id]/cancel.dart
//  - a lesson starts within 24 hours, or a student left a review
//      -> syncTutorNotifications, run when the tutor opens the bell. There is
//         no scheduler, so these are worked out from MySQL at that moment.
// Every notice has a fixed Firestore id (e.g. "review-12"), so running the
// same check again never adds a second card.

NotificationStore? _store; // shared, so the Google access token is reused

/// One lesson of a purchase: its booking, "2026-10-28" and "14:00".
typedef PaidLesson = ({int bookingId, String date, String startTime});

/// "Lesego Mokoena booked a lesson in Maths for Tue 28 Oct, 14:00."
/// [lessons] are in date order; the card opens the first one.
Notice bookedNotice({
  required int purchaseId,
  required String studentName,
  required String subject,
  required List<PaidLesson> lessons,
}) {
  final first = lessons.first;
  final when = sessionLabel(first.date, first.startTime);
  return Notice(
    id: 'booked-$purchaseId',
    type: NotificationType.bookingConfirmed,
    title: 'New lesson booked',
    body: lessons.length == 1
        ? '$studentName booked a lesson in $subject for $when.'
        : '$studentName booked ${lessons.length} lessons in $subject, '
              'starting $when.',
    bookingId: first.bookingId,
  );
}

/// "You're tutoring Lesego Mokoena in Maths in an hour."
/// Within the hour it is the "-hour" reminder, otherwise the "-day" one
/// ("today at 14:00" / "tomorrow at 14:00"), so each lesson gets at most
/// one of each.
Notice upcomingNotice({
  required int bookingId,
  required String studentName,
  required String subject,
  required String startTime,
  required int minutesUntil,
  required int daysAway,
}) {
  final when = lessonStartsIn(minutesUntil, daysAway, startTime);
  return Notice(
    id: 'upcoming-$bookingId-${reminderKind(minutesUntil)}',
    type: NotificationType.upcomingSession,
    title: 'Upcoming lesson',
    body: "You're tutoring $studentName in $subject $when.",
    bookingId: bookingId,
  );
}

/// "Lerato Dube gave your Maths lesson 5 stars: “Very patient.”"
/// Long comments are cut to fit the card.
Notice reviewNotice({
  required int reviewId,
  required String studentName,
  required int rating,
  String? subject,
  String? comment,
  int? bookingId,
  DateTime? createdAt,
}) {
  final lesson = subject == null || subject.isEmpty
      ? 'lesson'
      : '$subject lesson';
  final stars = rating == 1 ? '1 star' : '$rating stars';
  final text = comment?.trim() ?? '';
  final quote = text.length > 80
      ? '${text.substring(0, 77).trimRight()}…'
      : text;
  return Notice(
    id: 'review-$reviewId',
    type: NotificationType.newReview,
    title: 'New review',
    body: quote.isEmpty
        ? '$studentName gave your $lesson $stars.'
        : '$studentName gave your $lesson $stars: “$quote”',
    bookingId: bookingId,
    createdAt: createdAt,
  );
}

/// Tells the tutor a student has paid for [purchaseId]'s lessons. Called by
/// the payment route after a successful payment. The payment is already
/// saved, so a problem here is only logged. Returns whether the tutor was
/// told.
Future<bool> notifyTutorOfPaidPurchase(int purchaseId) async {
  try {
    final conn = await getConnection(); // shared connection (do not close it)
    final result = await conn.execute(
      '''
      SELECT b.Booking_id, s.subjectName, su.Name AS StudentName,
        tu.FirebaseUid AS TutorUid,
        DATE_FORMAT(b.Date, '%Y-%m-%d') AS LessonDate,
        TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime
      FROM Booking b
      INNER JOIN Subjects s ON s.subjectId = b.SubjectID
      INNER JOIN TutorProfile tp ON tp.TutorID = b.TutorID
      INNER JOIN `User` tu ON tu.UserId = tp.UserID
      INNER JOIN StudentProfile sp ON sp.StudentID = b.StudentID
      INNER JOIN `User` su ON su.UserId = sp.UserID
      WHERE b.PurchaseID = :purchaseId AND b.Status = 'Confirmed'
      ORDER BY b.Date, b.StartTime
      ''',
      {'purchaseId': purchaseId},
    );
    final rows = result.rows.map((r) => r.assoc()).toList();
    if (rows.isEmpty) return false;
    final tutorUid = rows.first['TutorUid'];
    if (tutorUid == null || tutorUid.isEmpty) return false;

    final notice = bookedNotice(
      purchaseId: purchaseId,
      studentName: rows.first['StudentName'] ?? 'A student',
      subject: rows.first['subjectName'] ?? '',
      lessons: [
        for (final row in rows)
          (
            bookingId: int.parse(row['Booking_id']!),
            date: row['LessonDate']!,
            startTime: row['StartTime']!,
          ),
      ],
    );
    await notice.sendTo(
      tutorUid,
      _store ??= NotificationStore.fromFirebaseAdmin(),
    );
    return true;
  } catch (e) {
    stderr.writeln(
      'Could not notify the tutor about paid purchase $purchaseId: $e',
    );
    return false;
  }
}

/// Adds the tutor's lesson reminders and new-review notifications that are
/// not in Firestore yet. Run when the tutor opens the bell (the list or the
/// unread badge), before reading it.
Future<void> syncTutorNotifications(
  MySQLConnection conn,
  NotificationStore store, {
  required String tutorUid,
  required int tutorId,
}) async {
  // Confirmed lessons starting in the next 24 hours (South African time,
  // like the rest of the booking code).
  final upcoming = await conn.execute(
    '''
    SELECT b.Booking_id, s.subjectName, su.Name AS StudentName,
      TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
      TIMESTAMPDIFF(
        MINUTE, UTC_TIMESTAMP() + INTERVAL 2 HOUR, TIMESTAMP(b.Date, b.StartTime)
      ) AS MinutesUntil,
      DATEDIFF(b.Date, DATE(UTC_TIMESTAMP() + INTERVAL 2 HOUR)) AS DaysAway
    FROM Booking b
    INNER JOIN Subjects s ON s.subjectId = b.SubjectID
    INNER JOIN StudentProfile sp ON sp.StudentID = b.StudentID
    INNER JOIN `User` su ON su.UserId = sp.UserID
    WHERE b.TutorID = :tutorId AND b.Status = 'Confirmed'
      AND TIMESTAMP(b.Date, b.StartTime) > UTC_TIMESTAMP() + INTERVAL 2 HOUR
      AND TIMESTAMP(b.Date, b.StartTime)
        <= UTC_TIMESTAMP() + INTERVAL 2 HOUR + INTERVAL 24 HOUR
    ORDER BY b.Date, b.StartTime
    LIMIT 20
    ''',
    {'tutorId': tutorId},
  );

  // Reviews from the last 7 days. Created_At was filled in by MySQL, so its
  // age is measured with MySQL's own clock.
  final reviews = await conn.execute(
    '''
    SELECT r.Reviewid, r.Rating, r.`comment` AS Comment, r.BookingID,
      s.subjectName, su.Name AS StudentName,
      TIMESTAMPDIFF(SECOND, r.Created_At, NOW()) AS AgeSeconds
    FROM Reviews r
    INNER JOIN StudentProfile sp ON sp.StudentID = r.StudentID
    INNER JOIN `User` su ON su.UserId = sp.UserID
    LEFT JOIN Booking b ON b.Booking_id = r.BookingID
    LEFT JOIN Subjects s ON s.subjectId = b.SubjectID
    WHERE r.TutorID = :tutorId AND r.Created_At >= NOW() - INTERVAL 7 DAY
    ORDER BY r.Created_At DESC
    LIMIT 20
    ''',
    {'tutorId': tutorId},
  );

  final now = DateTime.now().toUtc();
  final notices = [
    for (final row in upcoming.rows.map((r) => r.assoc()))
      upcomingNotice(
        bookingId: int.parse(row['Booking_id']!),
        studentName: row['StudentName'] ?? 'your student',
        subject: row['subjectName'] ?? '',
        startTime: row['StartTime'] ?? '',
        minutesUntil: int.parse(row['MinutesUntil']!),
        daysAway: int.parse(row['DaysAway']!),
      ),
    for (final row in reviews.rows.map((r) => r.assoc()))
      reviewNotice(
        reviewId: int.parse(row['Reviewid']!),
        studentName: row['StudentName'] ?? 'A student',
        rating: int.parse(row['Rating']!),
        subject: row['subjectName'],
        comment: row['Comment'],
        bookingId: int.tryParse(row['BookingID'] ?? ''),
        createdAt: now.subtract(
          Duration(seconds: int.tryParse(row['AgeSeconds'] ?? '') ?? 0),
        ),
      ),
  ];
  await Future.wait([for (final n in notices) n.sendTo(tutorUid, store)]);
}
