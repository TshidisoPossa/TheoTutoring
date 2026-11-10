import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/tutor_search.dart';

/// Loads a student's live dashboard data from MySQL.
class MySqlStudentDashboardRepository {
  /// Creates a repository using the supplied MySQL connection.
  MySqlStudentDashboardRepository(this.connection);

  /// Connection shared with the route's authenticated request.
  final MySQLConnection connection;

  /// Loads active student identity, upcoming sessions, and approved tutors.
  Future<Map<String, Object?>> load(String firebaseUid) async {
    final student = await connection.execute(
      '''
      SELECT sp.StudentID, u.Name, u.ProfilePhoto, u.Email, sp.Institution
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

    final studentId = int.parse(student.rows.first.colByName('StudentID')!);
    final sessionsResult = await connection.execute(
      '''
      SELECT b.Booking_id, s.subjectName, tu.Name AS TutorName,
        tu.ProfilePhoto AS TutorPhoto,
        DATE_FORMAT(b.Date, '%Y-%m-%d') AS SessionDate,
        TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
        TIME_FORMAT(b.EndTime, '%H:%i') AS EndTime,
        b.Link
      FROM Booking b
      INNER JOIN TutorProfile tp ON tp.TutorID = b.TutorID
      INNER JOIN `User` tu ON tu.UserId = tp.UserID
      INNER JOIN Subjects s ON s.subjectId = b.SubjectID
      WHERE b.StudentID = :studentId
        AND b.Status = 'Confirmed'
        AND TIMESTAMP(b.Date, b.StartTime) >=
            (UTC_TIMESTAMP() + INTERVAL 2 HOUR)
      ORDER BY b.Date ASC, b.StartTime ASC, b.Booking_id ASC
      LIMIT 40
      ''',
      {'studentId': studentId},
    );
    final sessions = [
      for (final row in sessionsResult.rows)
        <String, Object?>{
          'bookingId': int.parse(row.colByName('Booking_id')!),
          'subject': row.colByName('subjectName'),
          'tutorName': row.colByName('TutorName'),
          'tutorPhoto': row.colByName('TutorPhoto'),
          'date': row.colByName('SessionDate'),
          'startTime': row.colByName('StartTime'),
          'endTime': row.colByName('EndTime'),
          'link': row.colByName('Link'),
        },
    ];

    final tutorPage = await MySqlTutorSearchRepository(connection).search(
      const TutorSearchOptions(query: '', subjectId: null, page: 1, limit: 3),
    );
    return {
      'studentName': student.rows.first.colByName('Name'),
      // Cloudinary URL saved at registration, null if none was uploaded
      'studentPhoto': student.rows.first.colByName('ProfilePhoto'),
      // For the Profile tab
      'studentEmail': student.rows.first.colByName('Email'),
      'studentInstitution': student.rows.first.colByName('Institution'),
      'upcomingSessions': sessions,
      'tutors': tutorPage.tutors,
    };
  }
}

/// Signals that the Firebase identity is not an active student account.
class StudentDashboardDenied implements Exception {
  /// Creates the access-denied signal.
  const StudentDashboardDenied();
}
