import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/jwt_helper.dart';

// ── CONFIRM THESE against the values your booking routes store ──
const _pending = 'pending'; // tutor has not answered yet
const _confirmed = ['paid']; // session will go ahead
const _activeStudent = ['paid', 'completed']; // counts toward "Active Students"
const _requestsShown = 5; // rows in "Recent Requests"

// ── Helpers ──

/// South Africa is UTC+2 all year, so "today" must not depend on the
/// server's own time zone.
DateTime _nowInSouthAfrica() =>
    DateTime.now().toUtc().add(const Duration(hours: 2));

String _two(int n) => n.toString().padLeft(2, '0');
String _dateOf(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _timeOf(DateTime d) =>
    '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

int _int(String? v) => int.tryParse(v ?? '') ?? 0;
String? _nullIfEmpty(String? v) => (v == null || v.isEmpty) ? null : v;
String? _hhmm(String? t) => (t == null || t.length < 5) ? t : t.substring(0, 5);
String? _dateOnly(String? d) => d?.split(' ').first;

String _placeholders(String prefix, List<String> values) =>
    List.generate(values.length, (i) => ':$prefix$i').join(', ');

Map<String, dynamic> _bind(String prefix, List<String> values) => {
  for (var i = 0; i < values.length; i++) '$prefix$i': values[i],
};

/// Small square version of a Cloudinary image for the header avatar.
String? _thumb(String? url) {
  if (url == null) return null;
  const marker = '/upload/';
  if (!url.startsWith('https://res.cloudinary.com/') || !url.contains(marker)) {
    return url;
  }
  return url.replaceFirst(
    marker,
    '${marker}c_fill,g_face,w_96,h_96,f_auto,q_auto/',
  );
}

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Method not allowed'},
    );
  }

  // ── Verify JWT ──
  final authHeader = context.request.headers['Authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Unauthorised. Please log in.'},
    );
  }

  final payload = verifyToken(authHeader.substring(7));
  if (payload == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Invalid or expired session. Please log in again.'},
    );
  }

  try {
    final db = await getConnection();
    final now = _nowInSouthAfrica();
    final today = _dateOf(now);
    final nowTime = _timeOf(now);

    // ── 1. Who is this tutor? (id comes from the token, never the client) ──
    final tutorResult = await db.execute(
      '''
      SELECT tp.TutorID AS tutorId,
             u.Name AS name,
             u.ProfilePhoto AS profilePhoto,
             u.AccountStatus AS accountStatus,
             tp.VerificationStat AS verificationStat
      FROM TutorProfile tp
      JOIN `User` u ON u.UserId = tp.UserId
      WHERE tp.UserId = :userId
      LIMIT 1
      ''',
      {'userId': payload['userId']},
    );

    if (tutorResult.rows.isEmpty) {
      return Response.json(
        statusCode: 403,
        body: {'error': 'Only tutors can view this dashboard'},
      );
    }

    final tutor = tutorResult.rows.first.assoc();
    if ((tutor['accountStatus'] ?? '').toLowerCase() == 'suspended') {
      return Response.json(
        statusCode: 403,
        body: {'error': 'Your account has been suspended'},
      );
    }

    final tutorId = _int(tutor['tutorId']);
    final photo = _nullIfEmpty(tutor['profilePhoto']);

    // ── 2. Stat cards + banner count (one query) ──
    final statsResult = await db.execute(
      '''
      SELECT
        COUNT(DISTINCT CASE WHEN Status IN (${_placeholders('act', _activeStudent)})
                            THEN StudentID END) AS activeStudents,
        COUNT(CASE WHEN Status IN (${_placeholders('conf', _confirmed)})
                    AND `Date` = :today AND EndTime > :nowTime
                   THEN 1 END) AS upcomingToday,
        COUNT(CASE WHEN Status = :pending AND `Date` >= :today
                   THEN 1 END) AS pendingRequests
      FROM Booking
      WHERE TutorID = :tutorId
      ''',
      {
        'tutorId': tutorId,
        'today': today,
        'nowTime': nowTime,
        'pending': _pending,
        ..._bind('act', _activeStudent),
        ..._bind('conf', _confirmed),
      },
    );
    final stats = statsResult.rows.first.assoc();

    // ── 3. Recent requests (text only, no student photos) ──
    final requestsResult = await db.execute(
      '''
      SELECT b.Booking_id AS bookingId,
             u.Name AS studentName,
             b.Subject AS subject,
             b.Note AS note,
             b.`Date` AS sessionDate,
             b.StartTime AS startTime,
             b.EndTime AS endTime,
             b.Created_at AS createdAt
      FROM Booking b
      JOIN StudentProfile sp ON sp.StudentID = b.StudentID
      JOIN `User` u ON u.UserId = sp.UserID
      WHERE b.TutorID = :tutorId
        AND b.Status = :pending
        AND b.`Date` >= :today
      ORDER BY b.Created_at DESC
      LIMIT $_requestsShown
      ''',
      {'tutorId': tutorId, 'pending': _pending, 'today': today},
    );

    final recentRequests = requestsResult.rows.map((row) {
      final r = row.assoc();
      return {
        'bookingId': _int(r['bookingId']),
        'studentName': r['studentName'],
        'subject': r['subject'],
        'note': r['note'],
        'date': _dateOnly(r['sessionDate']),
        'startTime': _hhmm(r['startTime']),
        'endTime': _hhmm(r['endTime']),
        'createdAt': r['createdAt'],
      };
    }).toList();

    // ── 4. Today's schedule ──
    final scheduleResult = await db.execute(
      '''
      SELECT b.Booking_id AS bookingId,
             u.Name AS studentName,
             b.Subject AS subject,
             b.StartTime AS startTime,
             b.EndTime AS endTime,
             b.Link AS link
      FROM Booking b
      JOIN StudentProfile sp ON sp.StudentID = b.StudentID
      JOIN `User` u ON u.UserId = sp.UserID
      WHERE b.TutorID = :tutorId
        AND b.Status IN (${_placeholders('conf', _confirmed)})
        AND b.`Date` = :today
      ORDER BY b.StartTime
      ''',
      {'tutorId': tutorId, 'today': today, ..._bind('conf', _confirmed)},
    );

    final todaySchedule = scheduleResult.rows.map((row) {
      final r = row.assoc();
      return {
        'bookingId': _int(r['bookingId']),
        'studentName': r['studentName'],
        'subject': r['subject'],
        'startTime': _hhmm(r['startTime']),
        'endTime': _hhmm(r['endTime']),
        'link': _nullIfEmpty(r['link']),
      };
    }).toList();

    return Response.json(
      body: {
        'tutor': {
          'tutorId': tutorId,
          'name': tutor['name'],
          'profilePhotoUrl': photo,
          'profilePhotoThumbUrl': _thumb(photo),
          'accountStatus': tutor['accountStatus'],
          'verificationStatus': tutor['verificationStat'],
        },
        'stats': {
          'activeStudents': _int(stats['activeStudents']),
          'upcomingToday': _int(stats['upcomingToday']),
          'pendingRequests': _int(stats['pendingRequests']),
        },
        'recentRequests': recentRequests,
        'todaySchedule': todaySchedule,
        'serverDate': today,
      },
    );
  } catch (e) {
    print('❌ Error in tutor dashboard: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Something went wrong. Please try again.'},
    );
  }
}
