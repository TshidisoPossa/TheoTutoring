import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';

/// Students reporting tutors to the administrator (documentation 4.9).
/// Each report is a Report row the admin Refunds & Issues screen reviews:
/// Open -> Resolved (AdminID = who handled it).
class MySqlStudentReportsRepository {
  /// Creates a repository using the supplied MySQL connection.
  MySqlStudentReportsRepository(this.connection);

  /// Shared MySQL connection.
  final MySQLConnection connection;

  /// Reports the tutor of one of the student's lessons (My Schedule menu).
  /// Returns the new ReportID.
  Future<int> reportLesson(
    String firebaseUid,
    int bookingId,
    String reason,
  ) async {
    final student = await _student(firebaseUid);
    final booking = await connection.execute(
      '''
      SELECT tp.UserID AS ReportedUserID
      FROM booking b
      INNER JOIN tutorprofile tp ON tp.TutorID = b.TutorID
      WHERE b.Booking_id = :bookingId AND b.StudentID = :studentId
      ''',
      {'bookingId': bookingId, 'studentId': student.studentId},
    );
    if (booking.rows.isEmpty) {
      throw const LessonActionException(404, 'Lesson not found.');
    }
    return _file(
      reporterId: student.userId,
      reportedUserId: int.parse(
        booking.rows.first.reqStr('ReportedUserID'),
      ),
      bookingId: bookingId,
      reason: reason,
      alreadyReported:
          'You have already reported this lesson. '
          'An administrator will review it.',
    );
  }

  /// Reports a tutor from their profile, without a lesson (⋮ menu).
  /// Returns the new ReportID.
  Future<int> reportTutor(
    String firebaseUid,
    int tutorId,
    String reason,
  ) async {
    final student = await _student(firebaseUid);
    final tutor = await connection.execute(
      'SELECT UserID FROM tutorprofile WHERE TutorID = :tutorId',
      {'tutorId': tutorId},
    );
    if (tutor.rows.isEmpty) {
      throw const LessonActionException(404, 'Tutor not found.');
    }
    return _file(
      reporterId: student.userId,
      reportedUserId: int.parse(tutor.rows.first.reqStr('UserID')),
      bookingId: null,
      reason: reason,
      alreadyReported:
          'You have already reported this tutor. '
          'An administrator will review it.',
    );
  }

  Future<({int userId, int studentId})> _student(String firebaseUid) async {
    final result = await connection.execute(
      '''
      SELECT u.UserId, sp.StudentID
      FROM `user` u
      INNER JOIN studentprofile sp ON sp.UserID = u.UserId
      WHERE u.FirebaseUid = :uid
        AND u.Role = 'student'
        AND u.AccountStatus = 'Active'
      LIMIT 1
      ''',
      {'uid': firebaseUid},
    );
    if (result.rows.isEmpty) throw const StudentDashboardDenied();
    final row = result.rows.first;
    return (
      userId: int.parse(row.reqStr('UserId')),
      studentId: int.parse(row.reqStr('StudentID')),
    );
  }

  // One unresolved report per lesson (or per tutor without a lesson), so a
  // double tap does not file it twice.
  Future<int> _file({
    required int reporterId,
    required int reportedUserId,
    required int? bookingId,
    required String reason,
    required String alreadyReported,
  }) async {
    final existing = await connection.execute(
      '''
      SELECT 1 FROM report
      WHERE ReporterID = :reporterId
        AND ReportedUserID = :reportedUserId
        AND BookingID <=> :bookingId
        AND Status <> 'Resolved'
      LIMIT 1
      ''',
      {
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'bookingId': bookingId,
      },
    );
    if (existing.rows.isNotEmpty) {
      throw LessonActionException(409, alreadyReported);
    }

    final inserted = await connection.execute(
      '''
      INSERT INTO report
        (ReporterID, ReportedUserID, BookingID, Reason, Status, Created_at)
      VALUES (:reporterId, :reportedUserId, :bookingId, :reason, 'Open',
              UTC_TIMESTAMP())
      ''',
      {
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'bookingId': bookingId,
        'reason': reason,
      },
    );
    return inserted.lastInsertID.toInt(); // BigInt cannot go into JSON
  }
}
