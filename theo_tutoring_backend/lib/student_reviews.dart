import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/request_utils.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';

/// Longest written (public) review a student can leave.
const reviewCommentMaxLength = 500;

/// Longest private note for the TheoTutoring team.
const reviewPrivateNoteMaxLength = 500;

/// The badges under "What made this session great?". Stored in
/// Reviews.Highlights and shown only to the admin. Keep in sync with the
/// app's student_review.dart.
const reviewHighlights = [
  'Clear explanations',
  'Punctual & prepared',
  'Patient with questions',
  'Great practice problems',
  'Encouraging atmosphere',
  'Helpful whiteboard notes',
];

/// SQL condition for a lesson that has taken place (documentation 4.9: only
/// completed sessions can be reviewed). Nothing marks a booking 'Completed'
/// yet, so a Confirmed (paid) lesson whose end time has passed counts too,
/// the same rule as the tutor's Completed tab. Times are SAST, like the rest
/// of the student screens. Expects the Booking alias `b`.
const completedLessonSql =
    "(b.Status = 'Completed' OR (b.Status = 'Confirmed' AND "
    'TIMESTAMP(b.Date, b.EndTime) < (UTC_TIMESTAMP() + INTERVAL 2 HOUR)))';

/// What the student sent: 1-5 stars, an optional written (public) review,
/// the badges they tapped and an optional private note for the admin.
typedef ReviewInput = ({
  int rating,
  String? comment,
  List<String> highlights,
  String? privateNote,
});

/// Reads `{"rating": 4, "comment": "...", "highlights": [...],
/// "privateNote": "..."}`; only rating is required. Throws a
/// [FormatException] with a message for the student when it is not valid.
ReviewInput parseReviewBody(Map<String, dynamic> body) {
  final raw = body['rating'];
  final rating = raw is int
      ? raw
      : raw is double && raw == raw.roundToDouble()
      ? raw.toInt()
      : null;
  if (rating == null || rating < 1 || rating > 5) {
    throw const FormatException('Please choose a rating from 1 to 5 stars.');
  }
  final comment = optionalString(
    body,
    'comment',
    maxLength: reviewCommentMaxLength,
  );
  final privateNote = optionalString(
    body,
    'privateNote',
    maxLength: reviewPrivateNoteMaxLength,
  );

  final rawHighlights = body['highlights'];
  if (rawHighlights != null &&
      (rawHighlights is! List || rawHighlights.any((h) => h is! String))) {
    throw const FormatException('highlights must be a list of text.');
  }
  final picked = (rawHighlights as List? ?? const []).cast<String>();
  for (final highlight in picked) {
    if (!reviewHighlights.contains(highlight)) {
      throw FormatException('"$highlight" is not one of the badges.');
    }
  }
  // Fixed order, no repeats
  final highlights = [
    for (final highlight in reviewHighlights)
      if (picked.contains(highlight)) highlight,
  ];

  return (
    rating: rating,
    comment: comment,
    highlights: highlights,
    privateNote: privateNote,
  );
}

/// A review that was saved.
class SavedReview {
  /// Creates the result.
  const SavedReview({
    required this.reviewId,
    required this.bookingId,
    required this.rating,
    required this.comment,
    required this.tutorAverage,
    required this.tutorReviewCount,
  });

  /// Reviews.Reviewid.
  final int reviewId;

  /// The reviewed booking.
  final int bookingId;

  /// 1-5.
  final int rating;

  /// The written review, or null.
  final String? comment;

  /// The tutor's new TutorProfile.AveRate.
  final double tutorAverage;

  /// How many reviews the tutor has now.
  final int tutorReviewCount;

  /// The route's JSON.
  Map<String, Object?> toJson() => {
    'reviewId': reviewId,
    'bookingId': bookingId,
    'rating': rating,
    'comment': comment,
    'tutorAverage': tutorAverage,
    'tutorReviewCount': tutorReviewCount,
  };
}

/// Saves student reviews.
// ignore: one_member_abstracts
abstract interface class StudentReviewsRepository {
  /// Saves the signed-in student's review of one of their completed
  /// lessons and updates the tutor's average rating.
  ///
  /// Throws [StudentDashboardDenied] when the caller is not an active
  /// student, and [LessonActionException] (404/409) when the lesson is not
  /// theirs, has not finished, or was already reviewed.
  Future<SavedReview> submit(
    String firebaseUid,
    int bookingId,
    ReviewInput input,
  );
}

/// [StudentReviewsRepository] on MySQL.
class MySqlStudentReviewsRepository implements StudentReviewsRepository {
  /// Creates the repository on [connection].
  MySqlStudentReviewsRepository(this.connection);

  /// The request's connection.
  final MySQLConnection connection;

  @override
  Future<SavedReview> submit(
    String firebaseUid,
    int bookingId,
    ReviewInput input,
  ) async {
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
    final studentId = int.parse(student.rows.first.colByName('StudentID')!);

    try {
      return await connection.transactional((tx) async {
        final booking = await tx.execute(
          '''
          SELECT b.TutorID,
            CASE WHEN $completedLessonSql THEN 1 ELSE 0 END AS IsOver,
            (SELECT r.Reviewid FROM Reviews r
             WHERE r.BookingID = b.Booking_id) AS ExistingReview
          FROM Booking b
          WHERE b.Booking_id = :bookingId AND b.StudentID = :studentId
          FOR UPDATE
          ''',
          {'bookingId': bookingId, 'studentId': studentId},
        );
        if (booking.rows.isEmpty) {
          throw const LessonActionException(404, 'Lesson not found.');
        }
        final row = booking.rows.first;
        if (row.colByName('ExistingReview') != null) {
          throw const LessonActionException(
            409,
            'You have already reviewed this lesson.',
          );
        }
        if (row.colByName('IsOver') != '1') {
          throw const LessonActionException(
            409,
            'You can review this lesson once it has taken place.',
          );
        }
        final tutorId = int.parse(row.colByName('TutorID')!);

        final inserted = await tx.execute(
          '''
          INSERT INTO Reviews (StudentID, TutorID, Rating, `comment`,
            Highlights, PrivateNote, BookingID)
          VALUES (:studentId, :tutorId, :rating, :comment,
            :highlights, :privateNote, :bookingId)
          ''',
          {
            'studentId': studentId,
            'tutorId': tutorId,
            'rating': input.rating,
            'comment': input.comment,
            'highlights': input.highlights.isEmpty
                ? null
                : input.highlights.join(','),
            'privateNote': input.privateNote,
            'bookingId': bookingId,
          },
        );

        // The tutor's average is stored (documentation 4.9: updated
        // automatically), as the search and profile screens read it.
        await tx.execute(
          '''
          UPDATE TutorProfile
          SET AveRate = COALESCE(
            (SELECT ROUND(AVG(r.Rating), 2) FROM Reviews r
             WHERE r.TutorID = :tutorId), 0)
          WHERE TutorID = :tutorId
          ''',
          {'tutorId': tutorId},
        );
        final rating = await tx.execute(
          '''
          SELECT tp.AveRate,
            (SELECT COUNT(*) FROM Reviews r WHERE r.TutorID = tp.TutorID)
              AS ReviewCount
          FROM TutorProfile tp
          WHERE tp.TutorID = :tutorId
          ''',
          {'tutorId': tutorId},
        );
        final ratingRow = rating.rows.first;

        return SavedReview(
          reviewId: inserted.lastInsertID.toInt(),
          bookingId: bookingId,
          rating: input.rating,
          comment: input.comment,
          tutorAverage:
              double.tryParse(ratingRow.colByName('AveRate') ?? '') ?? 0,
          tutorReviewCount: int.parse(ratingRow.colByName('ReviewCount')!),
        );
      });
    } on MySQLServerException catch (error) {
      // Two submits at once: Reviews.BookingID is UNIQUE
      if (error.errorCode == 1062) {
        throw const LessonActionException(
          409,
          'You have already reviewed this lesson.',
        );
      }
      rethrow;
    }
  }
}
