import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/notifications.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/bookings/[id]/index.dart'
    as detail_route;
import '../../../routes/TutorLandingpage/bookings/[id]/postpone.dart'
    as postpone_route;

// Runs the booking details + postpone routes against the real database from
// .env, as one tutor. Opt in, so a normal `dart test` never touches it:
//   BOOKING_MYSQL_TEST_TUTOR_ID=1 dart test test/routes/TutorLandingpage/booking_detail_mysql_test.dart
// It adds sample bookings and availability for that tutor and deletes them
// afterwards. The Firebase login check (middleware) is skipped and Firestore
// is faked, so no real notification is sent.

class _MockRequestContext extends Mock implements RequestContext {}

final _tutorId = int.tryParse(
  Platform.environment['BOOKING_MYSQL_TEST_TUTOR_ID'] ?? '',
);

void main() {
  if (_tutorId == null) {
    test(
      'Booking details route against MySQL',
      () {},
      skip: 'Set BOOKING_MYSQL_TEST_TUTOR_ID to run against the database',
    );
    return;
  }

  late MySQLConnection conn;
  final ids = <String, int>{}; // name -> Booking_id of each test booking
  final availabilityIds = <int>[];
  final firestoreRequests = <http.Request>[];
  late String studentName;

  // Sessions start 8 days out, so every one of them is in the future.
  final base = DateTime.now().add(const Duration(days: 8));
  String day(int offset) => DateTime(base.year, base.month, base.day + offset)
      .toIso8601String()
      .substring(0, 10);
  String today() => DateTime.now().toIso8601String().substring(0, 10);
  const weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];

  final store = NotificationStore(
    projectId: 'demo',
    accessToken: () async => 'token',
    client: MockClient((request) async {
      firestoreRequests.add(request);
      return http.Response(
        jsonEncode({
          'name': 'projects/demo/databases/(default)/documents/'
              'notifications/u/items/n1',
          'fields': <String, dynamic>{},
        }),
        200,
      );
    }),
  );

  _MockRequestContext contextFor(String method, {String? body}) {
    final context = _MockRequestContext();
    when(() => context.read<TutorSession>()).thenReturn(
      TutorSession('booking-mysql-test', _tutorId!),
    );
    when(() => context.read<NotificationStore>()).thenReturn(store);
    when(() => context.request).thenReturn(
      Request(
        method,
        Uri.parse('http://localhost/TutorLandingpage/bookings/x'),
        body: body,
      ),
    );
    return context;
  }

  Future<(int, Map<String, dynamic>)> detail(String name) async {
    final response = await detail_route.onRequest(
      contextFor('GET'),
      '${ids[name]}',
    );
    return (
      response.statusCode,
      await response.json() as Map<String, dynamic>,
    );
  }

  Future<(int, Map<String, dynamic>)> postpone(
    String name,
    String date,
    String start,
    String end,
  ) async {
    final response = await postpone_route.onRequest(
      contextFor(
        'POST',
        body: jsonEncode({'date': date, 'startTime': start, 'endTime': end}),
      ),
      '${ids[name]}',
    );
    return (
      response.statusCode,
      await response.json() as Map<String, dynamic>,
    );
  }

  setUpAll(() async {
    conn = await getConnection();

    final subject = await conn.execute(
      'SELECT subjectId FROM Subjects ORDER BY subjectId LIMIT 1',
    );
    final subjectId = subject.rows.first.colByName('subjectId');
    final student = await conn.execute(
      'SELECT s.StudentID, u.Name FROM StudentProfile s '
      'JOIN `User` u ON u.UserId = s.UserID ORDER BY s.StudentID LIMIT 1',
    );
    final studentId = student.rows.first.colByName('StudentID');
    studentName = student.rows.first.colByName('Name')!;

    // Availability on the series weekday is split in two touching ranges.
    Future<void> available(int offset, String start, String end) async {
      final d = DateTime.parse(day(offset));
      final result = await conn.execute(
        'INSERT INTO TutAvailability (TutorID, Day, StartTime, end_Time) '
        'VALUES (:t, :day, :s, :e)',
        {'t': _tutorId, 'day': weekdays[d.weekday - 1], 's': start, 'e': end},
      );
      availabilityIds.add(result.lastInsertID.toInt());
    }

    await available(0, '08:00:00', '12:00:00');
    await available(0, '12:00:00', '20:00:00');
    await available(1, '08:00:00', '20:00:00');

    Future<void> add(
      String name, {
      required String status,
      required String date,
      required String start,
      required String end,
    }) async {
      final result = await conn.execute(
        'INSERT INTO Booking (StudentID, TutorID, SubjectID, `Date`, '
        'StartTime, EndTime, Note, Status, Created_at) '
        'VALUES (:st, :t, :subj, :d, :s, :e, :note, :status, '
        'NOW() - INTERVAL 3 HOUR)',
        {
          'st': studentId,
          't': _tutorId,
          'subj': subjectId,
          'd': date,
          's': start,
          'e': end,
          'note': 'booking-mysql-test $name',
          'status': status,
        },
      );
      ids[name] = result.lastInsertID.toInt();
    }

    // Weekly series: three weeks in a row, then a gap, then one more.
    await add(
      'week1',
      status: 'Confirmed',
      date: day(0),
      start: '16:00:00',
      end: '17:00:00',
    );
    await add(
      'week2',
      status: 'Confirmed',
      date: day(7),
      start: '16:00:00',
      end: '17:00:00',
    );
    await add(
      'week3',
      status: 'Pending',
      date: day(14),
      start: '16:00:00',
      end: '17:00:00',
    );
    await add(
      'afterGap',
      status: 'Confirmed',
      date: day(28),
      start: '16:00:00',
      end: '17:00:00',
    );
    await add(
      'request',
      status: 'Pending',
      date: day(1),
      start: '10:00:00',
      end: '11:00:00',
    );
    await add(
      'blocker',
      status: 'Confirmed',
      date: day(1),
      start: '14:00:00',
      end: '15:00:00',
    );
    await add(
      'ended',
      status: 'Confirmed',
      date: DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10),
      start: '09:00:00',
      end: '10:00:00',
    );
    await add(
      'cancelled',
      status: 'Cancelled',
      date: day(2),
      start: '09:00:00',
      end: '10:00:00',
    );
  });

  tearDownAll(() async {
    for (final id in ids.values) {
      await conn.execute(
        'DELETE FROM Booking WHERE Booking_id = :id',
        {'id': id},
      );
    }
    for (final id in availabilityIds) {
      await conn.execute(
        'DELETE FROM TutAvailability WHERE AvailabilityID = :id',
        {'id': id},
      );
    }
    await conn.close();
  });

  test('details: session, student and the weekly series', () async {
    final (status, body) = await detail('week1');
    expect(status, 200);

    final booking = body['booking'] as Map<String, dynamic>;
    expect(booking['reference'], 'REQ-${ids['week1']}');
    expect(booking['status'], 'Confirmed');
    expect(booking['date'], day(0));
    expect(booking['startTime'], '16:00');
    expect(booking['endTime'], '17:00');
    expect(booking['durationMinutes'], 60);
    expect(booking['note'], 'booking-mysql-test week1');
    expect(booking['receivedMinutesAgo'], inInclusiveRange(179, 181));
    expect(booking['canPostpone'], isTrue);

    final student = body['student'] as Map<String, dynamic>;
    expect(student['name'], studentName);
    expect(student.keys, containsAll(['year', 'course', 'verified']));

    final recurring = body['recurring'] as Map<String, dynamic>;
    expect(
      recurring['weekday'],
      weekdays[DateTime.parse(day(0)).weekday - 1],
    );
    expect(
      (recurring['sessions'] as List).map((s) => (s as Map)['bookingId']),
      [ids['week1'], ids['week2'], ids['week3']], // stops before the gap
    );
    expect(recurring['totalSessions'], 3);
    expect(recurring['totalMinutes'], 180);
  });

  test('details: a one-off session has no recurring card', () async {
    final (_, body) = await detail('request');
    expect(body['recurring'], isNull);
  });

  test('details: a finished session cannot be postponed', () async {
    final (_, body) = await detail('ended');
    final booking = body['booking'] as Map<String, dynamic>;
    expect(booking['hasStarted'], isTrue);
    expect(booking['canPostpone'], isFalse);
  });

  test("details: another tutor's or a missing booking is a 404", () async {
    final response = await detail_route.onRequest(
      contextFor('GET'),
      '999999999',
    );
    expect(response.statusCode, 404);
  });

  test('postpone: refuses sessions that cannot move', () async {
    var (status, body) = await postpone('ended', day(1), '12:00', '13:00');
    expect(status, 409);
    expect(body['error'], contains('already started'));

    (status, body) = await postpone('cancelled', day(1), '12:00', '13:00');
    expect(status, 409);
    expect(body['error'], contains('pending or confirmed'));
  });

  test('postpone: refuses bad new times', () async {
    // same time as now
    var (status, body) = await postpone('request', day(1), '10:00', '11:00');
    expect(status, 400);

    // less than 3 hours away (already in the past today)
    (status, body) = await postpone('request', today(), '00:00', '00:30');
    expect(status, 400);
    expect(body['error'], contains('3 hours'));

    // outside the tutor's availability (08:00-20:00)
    (status, body) = await postpone('request', day(1), '20:00', '21:00');
    expect(status, 409);
    expect(body['error'], contains('not available'));

    // clashes with the 14:00-15:00 session
    (status, body) = await postpone('request', day(1), '14:30', '15:30');
    expect(status, 409);
    expect(body['error'], contains('clashes'));

    // nothing changed in the database
    final row = await conn.execute(
      'SELECT Status, StartTime FROM Booking WHERE Booking_id = :id',
      {'id': ids['request']},
    );
    expect(row.rows.first.colByName('Status'), 'Pending');
    expect(row.rows.first.colByName('StartTime'), '10:00:00');
  });

  test('postpone: moves the session and notifies the student', () async {
    firestoreRequests.clear();
    // 11:00-13:00 spans the two touching availability ranges on week1's day
    final (status, body) = await postpone('week1', day(0), '11:00', '13:00');
    expect(status, 200);
    expect(body['status'], 'Postponed');
    expect(body['date'], day(0));
    expect(body['startTime'], '11:00');
    expect(body['endTime'], '13:00');
    expect(body['previous'], {
      'status': 'Confirmed',
      'date': day(0),
      'startTime': '16:00',
      'endTime': '17:00',
    });
    expect(body['studentNotified'], isTrue);

    expect(firestoreRequests, hasLength(1));
    final sent = firestoreRequests.single.body;
    expect(sent, contains('BookingPostponed'));
    expect(sent, contains('Please confirm the new time.'));

    final row = await conn.execute(
      'SELECT Status, `Date`, StartTime, EndTime FROM Booking '
      'WHERE Booking_id = :id',
      {'id': ids['week1']},
    );
    final r = row.rows.first.assoc();
    expect(r['Status'], 'Postponed');
    expect(r['StartTime'], '11:00:00');
    expect(r['EndTime'], '13:00:00');

    // Postponed: the button is gone and it is no longer part of the series.
    final (_, detailBody) = await detail('week1');
    expect((detailBody['booking'] as Map)['canPostpone'], isFalse);
    expect(detailBody['recurring'], isNull);

    // ...and it cannot be postponed again until the student answers.
    final (again, _) = await postpone('week1', day(0), '13:00', '14:00');
    expect(again, 409);
  });

  test('postpone: a pending request can be postponed too', () async {
    final (status, body) = await postpone('request', day(1), '12:00', '13:00');
    expect(status, 200);
    expect((body['previous'] as Map)['status'], 'Pending');
  });
}
