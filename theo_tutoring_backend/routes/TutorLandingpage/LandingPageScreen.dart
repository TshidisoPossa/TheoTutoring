import '../../lib/database.dart'; // getConnection()
import '../../lib/tutorlanding_session.dart'; // TutorSession

import 'package:dart_frog/dart_frog.dart'; // Dart Frog types

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405); // only GET is allowed
  }
  final tutor = context.read<TutorSession>(); // who is calling
  final p = {'tid': tutor.tutorId}; // shared query parameter
  final conn = await getConnection(); // open a DB connection
  try {
    // Top bar: tutor name and profile photo
    final me = await conn.execute(
      'SELECT Name, ProfilePhoto FROM `User` WHERE UserId = :uid',
      {'uid': tutor.userId},
    );

    // Card 1: distinct students with a current or future Accepted/Paid booking
    final active = await conn.execute(
      "SELECT COUNT(DISTINCT StudentID) AS n FROM Booking "
      "WHERE TutorID = :tid AND Status IN ('Accepted','Paid') AND `Date` >= CURDATE()",
      p,
    );

    // Card 2: Paid sessions today that have not ended yet
    final today = await conn.execute(
      "SELECT COUNT(*) AS n FROM Booking "
      "WHERE TutorID = :tid AND Status = 'Paid' AND `Date` = CURDATE() AND EndTime > CURTIME()",
      p,
    );

    // Banner: number of pending requests
    final pending = await conn.execute(
      "SELECT COUNT(*) AS n FROM Booking WHERE TutorID = :tid AND Status = 'Pending'",
      p,
    );

    // Recent Requests: two newest pending bookings with the student's name and photo
    final recent = await conn.execute(
      'SELECT b.Booking_id, b.Subject, b.Note, b.`Date`, b.StartTime, b.EndTime, '
      'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto '
      'FROM Booking b '
      'JOIN StudentProfile s ON s.StudentID = b.StudentID '
      'JOIN `User` u ON u.UserId = s.UserID '
      "WHERE b.TutorID = :tid AND b.Status = 'Pending' "
      'ORDER BY b.Created_at DESC LIMIT 2',
      p,
    );

    // Today's Schedule: Paid sessions today in time order
    final schedule = await conn.execute(
      'SELECT b.Booking_id, b.Subject, b.StartTime, b.EndTime, b.Link, '
      'u.Name AS StudentName '
      'FROM Booking b '
      'JOIN StudentProfile s ON s.StudentID = b.StudentID '
      'JOIN `User` u ON u.UserId = s.UserID '
      "WHERE b.TutorID = :tid AND b.Status = 'Paid' AND b.`Date` = CURDATE() "
      'ORDER BY b.StartTime',
      p,
    );

    final meRow = me.rows.isEmpty
        ? <String, String?>{}
        : me.rows.first.assoc(); // tutor row or empty
    return Response.json(
      body: {
        'name': meRow['Name'], // dashboard title area
        'profilePhoto': meRow['ProfilePhoto'], // avatar in the top bar
        'activeStudents': int.parse(active.rows.first.assoc()['n']!), // card 1
        'upcomingToday': int.parse(today.rows.first.assoc()['n']!), // card 2
        'newRequests': int.parse(
          pending.rows.first.assoc()['n']!,
        ), // banner count
        'recentRequests': recent.rows
            .map((r) => r.assoc())
            .toList(), // request cards
        'todaysSchedule': schedule.rows
            .map((r) => r.assoc())
            .toList(), // schedule cards
      },
    );
  } finally {
    await conn.close(); // always close the connection
  }
}
