import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/database.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/schedule/index.dart' as schedule_route;

// Runs the Schedule route against the real database from .env, as one tutor.
// Opt in, so a normal `dart test` never touches the database:
//   SCHEDULE_MYSQL_TEST_TUTOR_ID=1 dart test test/routes/TutorLandingpage/schedule_mysql_test.dart
// It adds sample bookings (and one payment) for that tutor and deletes them
// afterwards. The Firebase login check (middleware) is skipped.

class _MockRequestContext extends Mock implements RequestContext {}

final _tutorId = int.tryParse(
  Platform.environment['SCHEDULE_MYSQL_TEST_TUTOR_ID'] ?? '',
);

void main() {
  if (_tutorId == null) {
    test(
      'Schedule route against MySQL',
      () {},
      skip: 'Set SCHEDULE_MYSQL_TEST_TUTOR_ID to run against the database',
    );
    return;
  }
  // The "today" booking starts in 5 minutes and must end before midnight.
  final startedAt = DateTime.now();
  if (startedAt.hour == 23 && startedAt.minute >= 30) {
    test('Schedule route against MySQL', () {}, skip: 'Run before 23:30');
    return;
  }
  final todayStart = startedAt.add(const Duration(minutes: 5));
  final midnight = DateTime(
    startedAt.year,
    startedAt.month,
    startedAt.day,
    23,
    59,
  );
  final oneHourLater = todayStart.add(const Duration(hours: 1));
  final todayEnd = oneHourLater.isBefore(midnight) ? oneHourLater : midnight;
  final todayMinutes =
      (todayEnd.hour * 60 + todayEnd.minute) -
      (todayStart.hour * 60 + todayStart.minute);

  late MySQLConnection conn;
  late Map<String, int> baseCounts; // tab numbers before the test bookings
  final ids = <String, int>{}; // name -> Booking_id of each test booking
  late int subjectA;
  late int subjectB;
  late String subjectBName;
  late String studentName;

  Future<Map<String, dynamic>> schedule(String query) async {
    final context = _MockRequestContext();
    when(() => context.read<TutorSession>()).thenReturn(
      TutorSession('schedule-mysql-test', _tutorId!),
    );
    when(() => context.request).thenReturn(
      Request(
        'GET',
        Uri.parse('http://localhost/TutorLandingpage/schedule$query'),
      ),
    );
    final response = await schedule_route.onRequest(context);
    expect(response.statusCode, 200);
    return await response.json() as Map<String, dynamic>;
  }

  // Only the test bookings, in the order the route returned them.
  List<Map<String, dynamic>> ours(Map<String, dynamic> body) => [
    for (final day in (body['days'] as List).cast<Map<String, dynamic>>())
      for (final s in (day['sessions'] as List).cast<Map<String, dynamic>>())
        if (ids.containsValue(s['bookingId'])) s,
  ];

  List<String> namesOf(Map<String, dynamic> body) => [
    for (final s in ours(body))
      ids.entries.firstWhere((e) => e.value == s['bookingId']).key,
  ];

  String day(int offset) => DateTime.now()
      .add(Duration(days: offset))
      .toIso8601String()
      .substring(0, 10);

  String clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';

  setUpAll(() async {
    conn = await getConnection();
    baseCounts = Map<String, int>.from(
      (await schedule(''))['counts'] as Map,
    );

    final subjects = await conn.execute(
      'SELECT subjectId, subjectName FROM Subjects ORDER BY subjectId LIMIT 2',
    );
    subjectA = int.parse(subjects.rows.first.colByName('subjectId')!);
    subjectB = int.parse(subjects.rows.last.colByName('subjectId')!);
    subjectBName = subjects.rows.last.colByName('subjectName')!;
    final student = await conn.execute(
      'SELECT s.StudentID, u.Name FROM StudentProfile s '
      'JOIN `User` u ON u.UserId = s.UserID ORDER BY s.StudentID LIMIT 1',
    );
    final studentId = student.rows.first.colByName('StudentID');
    studentName = student.rows.first.colByName('Name')!;

    Future<void> add(
      String name, {
      required String status,
      required String date,
      required String start,
      required String end,
      int? subject,
      String createdAt = 'NOW()',
    }) async {
      final result = await conn.execute(
        'INSERT INTO Booking (StudentID, TutorID, SubjectID, `Date`, '
        'StartTime, EndTime, Note, Status, Created_at) '
        'VALUES (:st, :t, :subj, :d, :s, :e, :note, :status, $createdAt)',
        {
          'st': studentId,
          't': _tutorId,
          'subj': subject ?? subjectA,
          'd': date,
          's': start,
          'e': end,
          'note': 'schedule-mysql-test $name',
          'status': status,
        },
      );
      ids[name] = result.lastInsertID.toInt();
    }

    await add(
      'today',
      status: 'Confirmed',
      date: day(0),
      start: clock(todayStart),
      end: clock(todayEnd),
    );
    await add(
      'tomorrow',
      status: 'Confirmed',
      date: day(1),
      start: '10:00:00',
      end: '11:30:00',
    );
    await add(
      'later',
      status: 'Confirmed',
      date: day(10),
      start: '09:00:00',
      end: '10:00:00',
      subject: subjectB,
    );
    await add(
      'request',
      status: 'Pending',
      date: day(3),
      start: '14:00:00',
      end: '15:00:00',
      createdAt: 'NOW() - INTERVAL 2 HOUR',
    );
    await add(
      'staleRequest',
      status: 'Pending',
      date: day(-1),
      start: '14:00:00',
      end: '15:00:00',
    );
    await add(
      'endedYesterday',
      status: 'Confirmed',
      date: day(-1),
      start: '09:00:00',
      end: '10:00:00',
    );
    await add(
      'completed',
      status: 'Completed',
      date: day(-3),
      start: '09:00:00',
      end: '10:00:00',
    );
    await add(
      'cancelled',
      status: 'Cancelled',
      date: day(1),
      start: '13:00:00',
      end: '14:00:00',
    );

    // The student paid for "today" 25 minutes ago.
    await conn.execute(
      'INSERT INTO Payment (BookingId, PaymentMethod, PaymentStatus, '
      'Paid_At, Amount) '
      "VALUES (:b, 'Card', 'Successful', NOW() - INTERVAL 25 MINUTE, 300)",
      {'b': ids['today']},
    );
  });

  tearDownAll(() async {
    for (final id in ids.values) {
      await conn.execute(
        'DELETE FROM Payment WHERE BookingId = :id',
        {'id': id},
      );
      await conn.execute(
        'DELETE FROM Booking WHERE Booking_id = :id',
        {'id': id},
      );
    }
    await conn.close();
  });

  test('tab numbers count each tab', () async {
    final counts = (await schedule(''))['counts'] as Map;
    expect(counts['upcoming'], baseCounts['upcoming']! + 3);
    expect(counts['new'], baseCounts['new']! + 1);
    expect(counts['past'], baseCounts['past']! + 2);
    expect(counts['all'], baseCounts['all']! + 5);
  });

  test('Upcoming: Confirmed sessions not ended, soonest first', () async {
    final body = await schedule('?tab=upcoming');
    expect(namesOf(body), ['today', 'tomorrow', 'later']);

    final today = ours(body).first;
    expect(today['daysFromToday'], 0);
    expect(today['durationMinutes'], todayMinutes);
    expect(today['startsInMinutes'], inInclusiveRange(3, 5));
    expect(today['confirmedMinutesAgo'], inInclusiveRange(24, 26));
    expect(today['note'], 'schedule-mysql-test today');
    expect((today['student'] as Map)['name'], studentName);

    final tomorrow = ours(body)[1];
    expect(tomorrow['daysFromToday'], 1);
    expect(tomorrow['startTime'], '10:00');
    expect(tomorrow['endTime'], '11:30');
    expect(tomorrow['durationMinutes'], 90);
    expect(tomorrow['confirmedMinutesAgo'], isNull); // no payment row
  });

  test('New: Pending requests whose session has not started', () async {
    final body = await schedule('?tab=new');
    expect(namesOf(body), ['request']);
    final request = ours(body).single;
    expect(request['status'], 'Pending');
    expect(request['requestedMinutesAgo'], inInclusiveRange(119, 121));
  });

  test('Past: ended Confirmed and Completed, most recent first', () async {
    expect(namesOf(await schedule('?tab=past')), [
      'endedYesterday',
      'completed',
    ]);
  });

  test('All: every Confirmed or Completed session', () async {
    final names = namesOf(await schedule('?tab=all'));
    expect(
      names.toSet(),
      {'today', 'tomorrow', 'later', 'endedYesterday', 'completed'},
    );
  });

  test('date chips: today, tomorrow and this week', () async {
    expect(namesOf(await schedule('?date=today')), ['today']);
    expect(namesOf(await schedule('?date=tomorrow')), ['tomorrow']);
    final week = namesOf(await schedule('?date=week'));
    expect(week, contains('today'));
    expect(week, isNot(contains('later'))); // 10 days away
  });

  test('subject filter', () async {
    final body = await schedule('?tab=all&subjectId=$subjectB');
    expect(namesOf(body), ['later']);
    expect(ours(body).single['subject'], subjectBName);
    expect(body['subjectIds'], [subjectB]);
  });

  test('sessions are grouped under each day', () async {
    final body = await schedule('?tab=upcoming');
    final todayGroup = (body['days'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((d) => d['daysFromToday'] == 0);
    expect(todayGroup['date'], day(0));
    expect(todayGroup['count'], (todayGroup['sessions'] as List).length);
  });
}
