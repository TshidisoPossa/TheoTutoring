import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:mysql_client/mysql_client.dart'; // IResultSet
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/header_tutor.dart'; // shared tutor name + photo
import '../../lib/tutorlanding_session.dart'; // TutorSession

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
    return Response(statusCode: 405); // only GET is allowed
  }
  final tutor = context.read<TutorSession>(); // who is calling
  final p = {'tid': tutor.tutorId}; // shared query parameter
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
      'SELECT Status, AdminFeedback, SubmittedAt, Review_at '
      'FROM TutorApplication WHERE TutorID = :tid '
      'ORDER BY SubmittedAt DESC, TutApplication DESC LIMIT 1', // latest application
      p,
    );
    final a = app.rows.isEmpty ? null : app.rows.first.assoc();
    return Response.json(
      body: {
        'tutor': header, // name + profile picture
        'accountStatus': tutor.accountStatus, // 'Pending'
        'application': a == null
            ? null
            : {
                'status': a['Status'], // Pending / Approved / Rejected
                'adminFeedback': a['AdminFeedback'],
                'submittedAt': a['SubmittedAt'],
                'reviewedAt': a['Review_at'],
              },
      },
    );
  }

  // Card 1: distinct students with a Confirmed session that has not ended yet
  final active = await conn.execute(
    'SELECT COUNT(DISTINCT StudentID) AS n FROM Booking '
    "WHERE TutorID = :tid AND Status = 'Confirmed' "
    'AND (`Date` > CURDATE() OR (`Date` = CURDATE() AND EndTime > CURTIME()))',
    p,
  );

  // Card 2: Confirmed sessions today that have not ended yet
  final today = await conn.execute(
    'SELECT COUNT(*) AS n FROM Booking '
    "WHERE TutorID = :tid AND Status = 'Confirmed' "
    'AND `Date` = CURDATE() AND EndTime > CURTIME()',
    p,
  );

  // Banner: number of pending requests
  final pending = await conn.execute(
    "SELECT COUNT(*) AS n FROM Booking WHERE TutorID = :tid AND Status = 'Pending'",
    p,
  );

  // Recent Requests: two newest pending bookings with the student's name and photo
  final recent = await conn.execute(
    'SELECT b.Booking_id, b.SubjectID, sj.subjectName AS Subject, b.Note, '
    'b.`Date`, b.StartTime, b.EndTime, '
    'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto '
    'FROM Booking b '
    'JOIN Subjects sj ON sj.subjectId = b.SubjectID ' // booking -> subject name
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // booking -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> user
    "WHERE b.TutorID = :tid AND b.Status = 'Pending' "
    'ORDER BY b.Created_at DESC LIMIT 2',
    p,
  );

  // Today's Schedule: Confirmed sessions today in time order
  final schedule = await conn.execute(
    'SELECT b.Booking_id, b.SubjectID, sj.subjectName AS Subject, '
    'b.StartTime, b.EndTime, b.Note, b.Link, '
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
