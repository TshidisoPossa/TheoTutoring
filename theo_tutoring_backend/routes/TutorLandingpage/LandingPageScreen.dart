import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/google_meet.dart';
import 'package:theo_tutoring_backend/header_tutor.dart';
import 'package:theo_tutoring_backend/tutor_application_status.dart';
import '../../lib/tutorlanding_session.dart';

//Tutor dashboard (landing page after registration)
//
// Follows the tutor dashboard design: the stat cards, today's schedule and
// the average rating with the latest reviews. Booking requests are no longer
// shown here.
//
// Only Confirmed bookings are used (schema.sql): the student has paid and
// the session is booked.
// Pending tutors only see their application status, not bookings.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  final tutor = context.read<TutorSession>();
  final p = {'tid': tutor.tutorId};
  final conn = await getConnection(); // shared DB connection (do not close it)

  // Top bar: tutor name and profile photo, same helper as every tutor page
  final header = await getTutorHeader(conn, tutor.tutorId);
  if (header == null) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Tutor not found'},
    ); // no tutor profile for this session
  }

  // Application still under review: show its status instead of bookings
  if (!tutor.isActive) {
    final app = await conn.execute(
      '''
      SELECT latest.Status, latest.AdminFeedback, latest.SubmittedAt,
             latest.Review_at,
             CASE WHEN latest.Status = 'Pending' THEN (
               SELECT rejected.AdminFeedback
               FROM TutorApplication rejected
               WHERE rejected.TutorID = latest.TutorID
                 AND rejected.Status = 'Rejected'
               ORDER BY rejected.SubmittedAt DESC, rejected.TutApplication DESC
               LIMIT 1
             ) ELSE NULL END AS LatestRejectedFeedback
      FROM TutorApplication latest
      WHERE latest.TutorID = :tid
      ORDER BY latest.SubmittedAt DESC, latest.TutApplication DESC
      LIMIT 1
      ''',
      p,
    );
    final a = app.rows.isEmpty ? null : app.rows.first.assoc();
    return Response.json(
      body: tutorApplicationStatusPayload(
        tutor: header,
        accountStatus: tutor.accountStatus,
        applicationStatus: a?['Status'],
        adminFeedback: tutorApplicationStatusFeedback(
          applicationStatus: a?['Status']?.toString(),
          currentFeedback: a?['AdminFeedback']?.toString(),
          latestRejectedFeedback: a?['LatestRejectedFeedback']?.toString(),
        ),
        submittedAt: a?['SubmittedAt'],
        reviewedAt: a?['Review_at'],
      ),
    );
  }

  // Card 1: every student registered on the platform whose account is
  // Active (not suspended or deactivated). The same for every tutor.
  final active = await conn.execute(
    'SELECT COUNT(*) AS n FROM StudentProfile s '
    'JOIN `User` u ON u.UserId = s.UserID '
    "WHERE u.Role = 'student' AND u.AccountStatus = 'Active'",
  );

  // Card 2 and Today's Schedule: Confirmed sessions today that have not ended
  // yet, in time order. The card shows the length of this list, so the two
  // always agree. MinutesUntilStart is worked out by MySQL so it uses the
  // same clock as CURDATE()/CURTIME(); 0 or less means the session is on now.
  final schedule = await conn.execute(
    'SELECT b.Booking_id, b.SubjectID, sj.subjectName AS Subject, '
    'b.StartTime, b.EndTime, b.Note, $tutorMeetLinkSql, '
    'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto, '
    'TIMESTAMPDIFF(MINUTE, NOW(), TIMESTAMP(b.`Date`, b.StartTime)) '
    'AS MinutesUntilStart '
    'FROM Booking b '
    'JOIN Subjects sj ON sj.subjectId = b.SubjectID '
    'JOIN StudentProfile s ON s.StudentID = b.StudentID '
    'JOIN `User` u ON u.UserId = s.UserID '
    "WHERE b.TutorID = :tid AND b.Status = 'Confirmed' "
    'AND b.`Date` = CURDATE() AND b.EndTime > CURTIME() '
    'ORDER BY b.StartTime',
    p,
  );

  // Rating card: average rating (TutorProfile.AveRate) and latest reviews
  final rating = await conn.execute(
    'SELECT AveRate FROM TutorProfile WHERE TutorID = :tid',
    p,
  );
  final reviews = await conn.execute(
    'SELECT r.Reviewid, r.Rating, r.`comment` AS Comment, r.Created_At, '
    'u.Name AS StudentName '
    'FROM Reviews r '
    'JOIN StudentProfile s ON s.StudentID = r.StudentID '
    'JOIN `User` u ON u.UserId = s.UserID '
    'WHERE r.TutorID = :tid '
    'ORDER BY r.Created_At DESC LIMIT 3',
    p,
  );

  // COUNT(*) comes back as a string, e.g. '3'
  int count(IResultSet r) => int.parse(r.rows.first.assoc()['n'] ?? '0');

  // AveRate is DECIMAL(3,2), also returned as a string, e.g. '4.50'
  final aveRate = rating.rows.isEmpty
      ? null
      : rating.rows.first.assoc()['AveRate'];

  return Response.json(
    body: {
      'tutor': header, // name + profile picture
      'accountStatus': tutor.accountStatus, // 'Active'
      'activeStudents': count(active), // card 1
      'upcomingToday': schedule.rows.length, // card 2
      'averageRating': double.tryParse(aveRate ?? '') ?? 0, // rating card
      'todaysSchedule': schedule.rows
          .map((r) => r.assoc())
          .toList(), // schedule cards
      'latestReviews': reviews.rows
          .map((r) => r.assoc())
          .toList(), // review cards
    },
  );
}
