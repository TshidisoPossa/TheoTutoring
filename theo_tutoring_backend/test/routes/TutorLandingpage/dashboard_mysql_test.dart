import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/database.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/LandingPageScreen.dart'
    as dashboard_route;

// Runs the dashboard route against the real database from .env, as one
// Active tutor. Opt in, so a normal `dart test` never touches the database:
//   DASHBOARD_MYSQL_TEST_TUTOR_ID=1 dart test test/routes/TutorLandingpage/dashboard_mysql_test.dart
// It adds sample bookings for that tutor and deletes them afterwards. The
// link test sets the tutor's MeetLink and puts it back. The Firebase login
// check (middleware) is skipped.

class _MockRequestContext extends Mock implements RequestContext {}

final _tutorId = int.tryParse(
  Platform.environment['DASHBOARD_MYSQL_TEST_TUTOR_ID'] ?? '',
);

const _meetLink = 'https://meet.google.com/aaa-bbbb-ccc';
const _ownLink =
    'https://zoom.us/j/123456789'; // an older lesson's Booking.Link

void main() {
  if (_tutorId == null) {
    test(
      'Dashboard route against MySQL',
      () {},
      skip: 'Set DASHBOARD_MYSQL_TEST_TUTOR_ID to run against the database',
    );
    return;
  }
  // Needs room today for a lesson that has ended and one still to come.
  final now = DateTime.now();
  if (now.hour < 1 || now.hour >= 22) {
    test('Dashboard route against MySQL', () {}, skip: 'Run 01:00-22:00');
    return;
  }

  late MySQLConnection conn;
  late Map<String, dynamic> before; // the dashboard before our bookings
  final ids = <String, int>{}; // name -> Booking_id of each test booking

  Future<Map<String, dynamic>> dashboard() async {
    final context = _MockRequestContext();
    when(() => context.read<TutorSession>()).thenReturn(
      TutorSession('dashboard-mysql-test', _tutorId!),
    );
    when(() => context.request).thenReturn(
      Request(
        'GET',
        Uri.parse('http://localhost/TutorLandingpage/LandingPageScreen'),
      ),
    );
    final response = await dashboard_route.onRequest(context);
    expect(response.statusCode, 200);
    return await response.json() as Map<String, dynamic>;
  }

  String day(int offset) =>
      now.add(Duration(days: offset)).toIso8601String().substring(0, 10);

  String clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';

  // Our bookings on today's schedule, by name, in the order returned.
  List<String> ours(Map<String, dynamic> body) => [
    for (final row
        in (body['todaysSchedule'] as List).cast<Map<String, dynamic>>())
      for (final e in ids.entries)
        if ('${row['Booking_id']}' == '${e.value}') e.key,
  ];

  setUpAll(() async {
    conn = await getConnection();
    before = await dashboard();

    final subject = await conn.execute(
      'SELECT subjectId FROM subjects ORDER BY subjectId LIMIT 1',
    );
    final student = await conn.execute(
      'SELECT StudentID FROM studentprofile ORDER BY StudentID LIMIT 1',
    );

    Future<void> add(
      String name, {
      required String status,
      required String date,
      required String start,
      required String end,
    }) async {
      final result = await conn.execute(
        'INSERT INTO booking (StudentID, TutorID, SubjectID, `Date`, '
        'StartTime, EndTime, Note, Status) '
        'VALUES (:st, :t, :subj, :d, :s, :e, :note, :status)',
        {
          'st': student.rows.first.str('StudentID'),
          't': _tutorId,
          'subj': subject.rows.first.str('subjectId'),
          'd': date,
          's': start,
          'e': end,
          'note': 'dashboard-mysql-test $name',
          'status': status,
        },
      );
      ids[name] = result.lastInsertID.toInt();
    }

    final later = now.add(const Duration(minutes: 30));
    final laterEnd = later.add(const Duration(minutes: 30));
    final earlier = now.subtract(const Duration(minutes: 50));
    final earlierEnd = now.subtract(const Duration(minutes: 10));

    // Only this one is "upcoming today"
    await add(
      'later today',
      status: 'Confirmed',
      date: day(0),
      start: clock(later),
      end: clock(laterEnd),
    );
    // Today, but not counted
    await add(
      'ended today',
      status: 'Confirmed',
      date: day(0),
      start: clock(earlier),
      end: clock(earlierEnd),
    );
    await add(
      'cancelled today',
      status: 'Cancelled',
      date: day(0),
      start: clock(later),
      end: clock(laterEnd),
    );
    await add(
      'pending today',
      status: 'Pending',
      date: day(0),
      start: clock(later),
      end: clock(laterEnd),
    );
    // Not today
    await add(
      'tomorrow',
      status: 'Confirmed',
      date: day(1),
      start: '10:00:00',
      end: '11:00:00',
    );
    await add(
      'yesterday',
      status: 'Confirmed',
      date: day(-1),
      start: '10:00:00',
      end: '11:00:00',
    );
  });

  tearDownAll(() async {
    for (final id in ids.values) {
      await conn.execute(
        'DELETE FROM booking WHERE Booking_id = :id',
        {'id': id},
      );
    }
    await conn.close();
  });

  test('Active Students counts every active registered student', () async {
    final expected = await conn.execute(
      'SELECT COUNT(*) AS n FROM studentprofile s '
      'JOIN `user` u ON u.UserId = s.UserID '
      "WHERE u.Role = 'student' AND u.AccountStatus = 'Active'",
    );
    final body = await dashboard();
    final students = int.parse(expected.rows.first.reqStr('n'));
    expect(body['activeStudents'], students);
    // Adding bookings does not change it: it is not per tutor
    expect(body['activeStudents'], before['activeStudents']);
  });

  test('Upcoming Today only counts Confirmed lessons today that have not '
      'ended', () async {
    final body = await dashboard();
    expect(body['upcomingToday'], (before['upcomingToday'] as int) + 1);
    expect(ours(body), ['later today']);
  });

  test("Today's Schedule matches the Upcoming Today card", () async {
    final body = await dashboard();
    final schedule = (body['todaysSchedule'] as List)
        .cast<Map<String, dynamic>>();
    expect(schedule.length, body['upcomingToday']);
    final row = schedule.firstWhere(
      (r) => '${r['Booking_id']}' == '${ids['later today']}',
    );
    // What a schedule card needs
    expect(row['Subject'], isNotNull);
    expect(row['StudentName'], isNotNull);
    expect(row['StartTime'], isNotNull);
    expect(row['EndTime'], isNotNull);
    expect(int.parse('${row['MinutesUntilStart']}'), inInclusiveRange(28, 31));
  });

  test("Today's Schedule link is the tutor's Meet room, unless the booking "
      'has its own', () async {
    final saved = await conn.execute(
      'SELECT MeetLink FROM tutorprofile WHERE TutorID = :t',
      {'t': _tutorId},
    );
    final savedMeetLink = saved.rows.first.str('MeetLink');
    Future<Object?> link() async {
      final body = await dashboard();
      return (body['todaysSchedule'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (r) => '${r['Booking_id']}' == '${ids['later today']}',
          )['Link'];
    }

    try {
      await conn.execute(
        'UPDATE tutorprofile SET MeetLink = :link WHERE TutorID = :t',
        {'link': _meetLink, 't': _tutorId},
      );
      expect(await link(), _meetLink);

      await conn.execute(
        'UPDATE booking SET Link = :link WHERE Booking_id = :id',
        {'link': _ownLink, 'id': ids['later today']},
      );
      expect(await link(), _ownLink);
    } finally {
      await conn.execute(
        'UPDATE tutorprofile SET MeetLink = :link WHERE TutorID = :t',
        {'link': savedMeetLink, 't': _tutorId},
      );
    }
  });
}
