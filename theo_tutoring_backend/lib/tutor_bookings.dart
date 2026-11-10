import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/google_meet.dart';

/// Booking.Status values from schema.sql.
const tutorBookingStatuses = {
  'Pending',
  'Confirmed',
  'Completed',
  'Cancelled',
  'Rejected',
};

const defaultTutorBookingsLimit = 50;
const maxTutorBookingsLimit = 100;

class TutorBookingSummary {
  const TutorBookingSummary({
    required this.bookingId,
    required this.status,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.subjectId,
    required this.subject,
    required this.studentName,
    required this.createdAt,
    this.note,
    this.link,
    this.purchaseId,
    this.lessonNumber,
  });

  final int bookingId;
  final String status;
  final String date;
  final String startTime;
  final String endTime;
  final int subjectId;
  final String subject;
  final String studentName;
  final String createdAt;
  final String? note;
  final String? link;
  final int? purchaseId;
  final int? lessonNumber;

  Map<String, Object?> toJson() => {
    'bookingId': bookingId,
    'status': status,
    'date': date,
    'startTime': startTime,
    'endTime': endTime,
    'subjectId': subjectId,
    'subject': subject,
    'studentName': studentName,
    'note': note,
    'link': link,
    'purchaseId': purchaseId,
    'lessonNumber': lessonNumber,
    'createdAt': createdAt,
  };
}

abstract interface class TutorBookingsRepository {
  /// Bookings owned by [tutorId] only, newest first.
  Future<List<TutorBookingSummary>> listForTutor(
    int tutorId, {
    String? status,
    int limit = defaultTutorBookingsLimit,
  });
}

class MySqlTutorBookingsRepository implements TutorBookingsRepository {
  MySqlTutorBookingsRepository(this._connection);

  final MySQLConnection _connection;

  // Purchase-backed bookings are only visible to the tutor once paid
  // (Confirmed/Completed); unpaid holds and expired holds stay hidden, matching
  // the dashboard's request count. Legacy bookings (no purchase) show all.
  static const listSql = '''
    SELECT b.Booking_id, b.Status, b.`Date`, b.StartTime, b.EndTime,
           b.SubjectID, sj.subjectName AS Subject, b.Note, $tutorMeetLinkSql,
           b.PurchaseID, b.LessonNumber, b.Created_at,
           u.Name AS StudentName
    FROM Booking b
    JOIN Subjects sj ON sj.subjectId = b.SubjectID
    JOIN StudentProfile s ON s.StudentID = b.StudentID
    JOIN `User` u ON u.UserId = s.UserID
    WHERE b.TutorID = :tutorId
      AND (b.PurchaseID IS NULL OR b.Status IN ('Confirmed', 'Completed'))
      AND (:status IS NULL OR b.Status = :status)
    ORDER BY b.`Date` DESC, b.StartTime DESC, b.Booking_id DESC
    LIMIT :limit
  ''';

  @override
  Future<List<TutorBookingSummary>> listForTutor(
    int tutorId, {
    String? status,
    int limit = defaultTutorBookingsLimit,
  }) async {
    final result = await _connection.execute(listSql, {
      'tutorId': tutorId,
      'status': status,
      'limit': limit,
    });
    return [
      for (final row in result.rows) _fromRow(row.assoc()),
    ];
  }

  TutorBookingSummary _fromRow(Map<String, String?> row) => TutorBookingSummary(
    bookingId: int.parse(row['Booking_id']!),
    status: row['Status']!,
    date: row['Date']!,
    startTime: row['StartTime']!,
    endTime: row['EndTime']!,
    subjectId: int.parse(row['SubjectID']!),
    subject: row['Subject']!,
    studentName: row['StudentName']!,
    note: row['Note'],
    link: row['Link'],
    purchaseId: row['PurchaseID'] == null
        ? null
        : int.parse(row['PurchaseID']!),
    lessonNumber: row['LessonNumber'] == null
        ? null
        : int.parse(row['LessonNumber']!),
    createdAt: row['Created_at']!,
  );
}
