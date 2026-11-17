import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/availability_overrides.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';

// A student moving one of their paid lessons to a new date and time
// (POST /students/lessons/<Booking_id>/reschedule).
//
// The lesson keeps its payment: only Booking.Date/StartTime/EndTime change,
// so nothing is charged or refunded. The new time follows the same rules as
// a new booking (booking_domain.dart): a 60-minute slot inside the tutor's
// hours (weekly hours, or that date's overrides), more than two hours from
// now and within 90 days, and not clashing with the tutor's or the
// student's other confirmed lessons or active payment holds. Each move is
// recorded in bookingreschedule with the status 'Applied'.

/// Statuses a student can reschedule: paid lessons only.
const reschedulableLessonStatuses = ['Confirmed'];

/// What the reschedule route needs to answer and to notify the tutor.
class LessonReschedule {
  const LessonReschedule({
    required this.bookingId,
    required this.subject,
    required this.studentName,
    required this.tutorFirebaseUid,
    required this.oldDate,
    required this.oldStartTime,
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  final int bookingId;
  final String subject;
  final String studentName;
  final String? tutorFirebaseUid;
  final String oldDate; // "2026-11-20"
  final String oldStartTime; // "14:00"
  final String date;
  final String startTime;
  final String endTime;
}

const _weekdays = {
  'Monday': DateTime.monday,
  'Tuesday': DateTime.tuesday,
  'Wednesday': DateTime.wednesday,
  'Thursday': DateTime.thursday,
  'Friday': DateTime.friday,
  'Saturday': DateTime.saturday,
  'Sunday': DateTime.sunday,
};

/// Moves the student's lesson [bookingId] to [date] at [startTime] (SA
/// time, "HH:mm"), in one transaction on [connection].
///
/// Throws [StudentDashboardDenied] for a non-student, [LessonActionException]
/// (404 or 409) when the lesson cannot be moved, and [FormatException] (400)
/// when the new time breaks the booking rules.
Future<LessonReschedule> rescheduleStudentLesson(
  MySQLConnection connection, {
  required String firebaseUid,
  required int bookingId,
  required BookingDate date,
  required int startMinutes,
  required DateTime nowUtc,
}) async {
  final slot = LessonInterval(
    date: date,
    startMinutes: startMinutes,
    endMinutes: startMinutes + lessonDurationMinutes,
  );
  // Times and the 90-day window first: no database work for a bad request.
  validateLessonTiming(slot: slot, nowUtc: nowUtc);

  final student = await connection.execute(
    '''
    SELECT sp.StudentID, u.UserId, u.Name
    FROM `user` u
    INNER JOIN studentprofile sp ON sp.UserID = u.UserId
    WHERE u.FirebaseUid = :uid AND u.Role = 'student'
      AND u.AccountStatus = 'Active'
    LIMIT 1
    ''',
    {'uid': firebaseUid},
  );
  if (student.rows.isEmpty) throw const StudentDashboardDenied();
  final studentId = int.parse(student.rows.first.reqStr('StudentID'));
  final studentUserId = int.parse(student.rows.first.reqStr('UserId'));
  final studentName = student.rows.first.str('Name') ?? 'Your student';

  return connection.transactional((tx) async {
    final booking = await tx.execute(
      '''
      SELECT b.Status, b.TutorID, s.subjectName, tu.FirebaseUid AS TutorUid,
        DATE_FORMAT(b.Date, '%Y-%m-%d') AS SessionDate,
        TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
        TIME_FORMAT(b.EndTime, '%H:%i') AS EndTime,
        TIMESTAMPDIFF(
          MINUTE,
          UTC_TIMESTAMP() + INTERVAL 2 HOUR,
          TIMESTAMP(b.Date, b.StartTime)
        ) AS MinutesBefore
      FROM booking b
      INNER JOIN subjects s ON s.subjectId = b.SubjectID
      INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
      INNER JOIN `user` tu ON tu.UserId = tp.UserID
      WHERE b.Booking_id = :bookingId AND b.StudentID = :studentId
      FOR UPDATE OF b
      ''',
      {'bookingId': bookingId, 'studentId': studentId},
    );
    if (booking.rows.isEmpty) {
      throw const LessonActionException(404, 'Lesson not found.');
    }
    final row = booking.rows.first;
    if (!reschedulableLessonStatuses.contains(row.str('Status'))) {
      throw const LessonActionException(
        409,
        'Only paid, confirmed lessons can be rescheduled.',
      );
    }
    if (int.parse(row.reqStr('MinutesBefore')) <= 0) {
      throw const LessonActionException(
        409,
        'This lesson has already started.',
      );
    }
    final oldDate = row.reqStr('SessionDate');
    final oldStart = row.reqStr('StartTime');
    final oldEnd = row.reqStr('EndTime');
    final newStart = formatClockTime(slot.startMinutes);
    final newEnd = formatClockTime(slot.endMinutes);
    if (oldDate == date.iso && oldStart == newStart) {
      throw const FormatException('Choose a different date or time.');
    }

    // The same tutor lock new bookings take, so a purchase cannot claim
    // this slot at the same moment.
    final tutorId = int.parse(row.reqStr('TutorID'));
    await tx.execute(
      'SELECT TutorID FROM tutorprofile WHERE TutorID = :tutorId FOR UPDATE',
      {'tutorId': tutorId},
    );

    // ── The new time must be inside the tutor's hours ──
    final hours = await tx.execute(
      '''
      SELECT Day, CAST(StartTime AS CHAR) AS StartTime,
        CAST(end_Time AS CHAR) AS EndTime
      FROM tutavailability
      WHERE TutorID = :tutorId
      ''',
      {'tutorId': tutorId},
    );
    final weekly = [
      for (final h in hours.rows)
        if (_weekdays[h.str('Day')] case final weekday?)
          WeeklyAvailability(
            weekday: weekday,
            startMinutes: parseClockTime(h.reqStr('StartTime')),
            endMinutes: parseClockTime(h.reqStr('EndTime')),
          ),
    ];
    validateLessonSlot(
      slot: slot,
      nowUtc: nowUtc,
      availability: weekly,
      overrides: await loadAvailabilityOverrides(
        tx,
        tutorId,
        from: date,
        through: date,
      ),
    );

    // ── ...and free for both the tutor and the student ──
    final clash = await tx.execute(
      '''
      SELECT
        (SELECT COUNT(*) FROM booking b
         WHERE b.Date = :date AND b.Status = 'Confirmed'
           AND b.Booking_id <> :bookingId
           AND (b.TutorID = :tutorId OR b.StudentID = :studentId)
           AND b.StartTime < :endTime AND b.EndTime > :startTime)
        +
        (SELECT COUNT(*) FROM bookingslothold h
         INNER JOIN bookingpurchase p ON p.PurchaseID = h.PurchaseID
         WHERE h.LessonDate = :date AND h.HoldStatus = 'Active'
           AND h.ExpiresAtUtc > UTC_TIMESTAMP(6)
           AND (h.TutorID = :tutorId OR p.StudentID = :studentId)
           AND h.StartTime < :endTime AND h.EndTime > :startTime) AS Clashes
      ''',
      {
        'date': date.iso,
        'bookingId': bookingId,
        'tutorId': tutorId,
        'studentId': studentId,
        'startTime': newStart,
        'endTime': newEnd,
      },
    );
    if (int.parse(clash.rows.first.reqStr('Clashes')) > 0) {
      throw const LessonActionException(
        409,
        'That time is no longer available. Please choose another one.',
      );
    }

    await tx.execute(
      '''
      UPDATE booking
      SET `Date` = :date, StartTime = :startTime, EndTime = :endTime
      WHERE Booking_id = :bookingId
      ''',
      {
        'date': date.iso,
        'startTime': newStart,
        'endTime': newEnd,
        'bookingId': bookingId,
      },
    );
    await tx.execute(
      '''
      INSERT INTO bookingreschedule (
        BookingID, RequestedByUserID, OriginalDate, OriginalStartTime,
        OriginalEndTime, ProposedDate, ProposedStartTime, ProposedEndTime,
        RescheduleStatus, RequestedAtUtc, AppliedAtUtc
      ) VALUES (
        :bookingId, :userId, :oldDate, :oldStart, :oldEnd,
        :date, :startTime, :endTime,
        'Applied', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)
      )
      ''',
      {
        'bookingId': bookingId,
        'userId': studentUserId,
        'oldDate': oldDate,
        'oldStart': oldStart,
        'oldEnd': oldEnd,
        'date': date.iso,
        'startTime': newStart,
        'endTime': newEnd,
      },
    );

    return LessonReschedule(
      bookingId: bookingId,
      subject: row.reqStr('subjectName'),
      studentName: studentName,
      tutorFirebaseUid: row.str('TutorUid'),
      oldDate: oldDate,
      oldStartTime: oldStart,
      date: date.iso,
      startTime: newStart,
      endTime: newEnd,
    );
  });
}
