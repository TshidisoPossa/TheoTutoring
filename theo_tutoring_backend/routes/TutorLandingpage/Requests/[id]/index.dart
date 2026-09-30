import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import '../../../../lib/database.dart'; // getConnection()
import '../../../../lib/tutorlanding_session.dart'; // TutorSession

//Author Tshidiso Possa

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405); // only GET is allowed
  }
  final bookingId = int.tryParse(id); // route parameter as int
  if (bookingId == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid id'},
    ); // not a number
  }
  final tutor = context.read<TutorSession>(); // who is calling
  final conn = await getConnection(); // shared DB connection (do not close it)

  // Booking details and student profile in one query
  final found = await conn.execute(
    'SELECT b.Booking_id, b.Subject, b.Note, b.`Date`, b.StartTime, b.EndTime, '
    'b.Status, b.Created_at, ' // booking details
    'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto, ' // student identity
    's.Course, s.InstitutionYear, s.Subject_of_interest ' // student profile
    'FROM Booking b '
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // booking -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> user
    'WHERE b.Booking_id = :id AND b.TutorID = :tid', // must belong to this tutor
    {'id': bookingId, 'tid': tutor.tutorId},
  );
  if (found.rows.isEmpty) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Request not found'},
    ); // not found or not theirs
  }
  final r = found.rows.first.assoc(); // the booking + student row

  // The tutor's schedule on the same date (Accepted/Paid sessions only)
  final day = await conn.execute(
    'SELECT Booking_id, Subject, StartTime, EndTime FROM Booking '
    "WHERE TutorID = :tid AND `Date` = :d AND Status IN ('Accepted','Paid') " // sessions that block the slot
    'AND Booking_id <> :id ORDER BY StartTime', // exclude this request, earliest first
    {'tid': tutor.tutorId, 'd': r['Date'], 'id': bookingId},
  );
  final daySchedule = day.rows
      .map((row) => row.assoc())
      .toList(); // schedule as a list of maps

  // Overlap check: existing start < request end AND existing end > request start
  final hasConflict = daySchedule.any(
    (s) =>
        s['StartTime']!.compareTo(r['EndTime']!) <
            0 && // starts before the request ends
        s['EndTime']!.compareTo(r['StartTime']!) >
            0, // ends after the request starts
  );

  return Response.json(
    body: {
      'booking': {
        'bookingId': r['Booking_id'], // used by Accept / Decline
        'subject': r['Subject'], // subject requested
        'note': r['Note'], // student's message
        'date': r['Date'], // session date
        'startTime': r['StartTime'], // session start
        'endTime': r['EndTime'], // session end
        'status': r['Status'], // Pending / Accepted / Declined / Paid
        'createdAt': r['Created_at'], // when it was requested
      },
      'student': {
        'name': r['StudentName'], // student name
        'profilePhoto': r['StudentPhoto'], // student photo
        'course': r['Course'], // course of study
        'institutionYear': r['InstitutionYear'], // year of study
        'subjectOfInterest':
            r['Subject_of_interest'], // subjects they want help with
      },
      'daySchedule': daySchedule, // planner schedule for that day
      'hasConflict': hasConflict, // true means Accept would return 409
    },
  );
}
