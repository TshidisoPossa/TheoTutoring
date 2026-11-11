import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/tutor_presence.dart';
import 'package:theo_tutoring_backend/tutor_search.dart';

/// Reviews sent with the profile; the app shows two and "See all" the rest.
const tutorProfileReviewLimit = 50;

/// The Tutor Profile page students open from Find a Tutor (documentation
/// 9.2): the search-card details plus qualifications, weekly availability,
/// reviews and whether the tutor is using the app right now.
class MySqlTutorPublicProfileRepository {
  /// Creates a repository using the supplied MySQL connection.
  MySqlTutorPublicProfileRepository(this.connection);

  /// Shared MySQL connection.
  final MySQLConnection connection;

  /// The profile of an approved, active tutor, or null if there is none.
  Future<Map<String, Object?>?> load(int tutorId) async {
    final tutor = await MySqlTutorSearchRepository(connection).findById(
      tutorId,
    );
    if (tutor == null) return null;

    final presence = await connection.execute(
      'SELECT ${tutorAvailableNowSql('tp')} AS AvailableNow '
      'FROM tutorprofile tp WHERE tp.TutorID = :tutorId',
      {'tutorId': tutorId},
    );

    final qualifications = await connection.execute(
      '''
      SELECT Degree, Institution FROM qualification
      WHERE TutorID = :tutorId
      ORDER BY QualificationID DESC
      ''',
      {'tutorId': tutorId},
    );

    final availability = await connection.execute(
      '''
      SELECT Day, TIME_FORMAT(StartTime, '%H:%i') AS StartTime,
        TIME_FORMAT(end_Time, '%H:%i') AS EndTime
      FROM tutavailability
      WHERE TutorID = :tutorId
      ORDER BY FIELD(Day, 'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday'), StartTime
      ''',
      {'tutorId': tutorId},
    );

    final reviews = await connection.execute(
      '''
      SELECT r.Reviewid, r.Rating, r.comment, su.Name AS StudentName,
        DATE_FORMAT(r.Created_At, '%Y-%m-%dT%H:%i:%s') AS CreatedAt
      FROM reviews r
      INNER JOIN studentprofile sp ON sp.StudentID = r.StudentID
      INNER JOIN `user` su ON su.UserId = sp.UserID
      WHERE r.TutorID = :tutorId
      ORDER BY r.Created_At DESC, r.Reviewid DESC
      LIMIT $tutorProfileReviewLimit
      ''',
      {'tutorId': tutorId},
    );

    return {
      ...tutor,
      'availableNow': presence.rows.first.str('AvailableNow') == '1',
      'qualifications': [
        for (final row in qualifications.rows)
          {
            'degree': row.str('Degree'),
            'institution': row.str('Institution'),
          },
      ],
      'availability': [
        for (final row in availability.rows)
          {
            'day': row.str('Day'),
            'startTime': row.str('StartTime'),
            'endTime': row.str('EndTime'),
          },
      ],
      'reviews': [
        for (final row in reviews.rows)
          {
            'reviewId': int.parse(row.reqStr('Reviewid')),
            'studentName': reviewerName(row.str('StudentName')),
            'rating': int.parse(row.reqStr('Rating')),
            'comment': row.str('comment'),
            'createdAt': row.str('CreatedAt'),
          },
      ],
    };
  }
}

/// Reviewers are shown by first name and surname initial: "Lerato M.".
String reviewerName(String? fullName) {
  final parts = (fullName ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Student';
  if (parts.length == 1) return parts.first;
  return '${parts.first} ${parts.last[0].toUpperCase()}.';
}
