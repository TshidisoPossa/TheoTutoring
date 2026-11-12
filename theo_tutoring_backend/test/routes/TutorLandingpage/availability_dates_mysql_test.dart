import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/availability_overrides.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/env.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/Profile/availability-dates.dart'
    as dates_route;
import '../../../routes/TutorLandingpage/Profile/availability.dart'
    as availability_route;
import '../../../routes/TutorLandingpage/Profile/index.dart' as profile_route;

// The availability calendar (one-off date changes) against the real
// theotutoring_test database from .env, as one tutor. Needs migration 007.
// Opt in with PROFILE_MYSQL_TEST_TUTOR_ID, and set DB_NAME=theotutoring_test;
// a normal `dart test` never touches the database:
//   PROFILE_MYSQL_TEST_TUTOR_ID=1 dart test test/routes/TutorLandingpage/availability_dates_mysql_test.dart
// The tutor's weekly hours and date changes are put back afterwards, and the
// bookings it adds are deleted. The Firebase login check (middleware) is
// skipped: the tutor is given directly.

class _MockRequestContext extends Mock implements RequestContext {}

final _tutorId = int.tryParse(
  Platform.environment['PROFILE_MYSQL_TEST_TUTOR_ID'] ?? '',
);
const _testDatabase = 'theotutoring_test';

void main() {
  if (env['DB_NAME'] != _testDatabase) {
    test(
      'Availability calendar against MySQL',
      () {},
      skip: 'Set DB_NAME to $_testDatabase in a test-only configuration',
    );
    return;
  }
  if (_tutorId == null) {
    test(
      'Availability calendar against MySQL',
      () {},
      skip: 'Set PROFILE_MYSQL_TEST_TUTOR_ID to run against the database',
    );
    return;
  }
  final tutorId = _tutorId!;

  late MySQLConnection conn;
  late List<Map<String, String?>> weeklyBefore;
  late List<Map<String, String?>> changesBefore;
  late List<BookingDate> freeDates; // no lessons booked, Mon-Sat
  // A free date on a weekday with no real lessons at all, so the weekly
  // grid can drop that weekday (null if every weekday has one).
  BookingDate? quietDate;
  final addedBookings = <int>[];

  Future<Response> call(
    Future<Response> Function(RequestContext) route,
    String method,
    String path, {
    Object? body,
  }) {
    final context = _MockRequestContext();
    when(() => context.read<TutorSession>()).thenReturn(
      TutorSession('availability-dates-mysql-test', tutorId),
    );
    when(() => context.request).thenReturn(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return route(context);
  }

  Future<Response> putDate(Map<String, Object?> body) => call(
    dates_route.onRequest,
    'PUT',
    '/TutorLandingpage/Profile/availability-dates',
    body: body,
  );

  // The slots a student is offered on [date], built the same way as
  // GET /StudentlandingPage/availability.
  Future<List<String>> studentSlots(BookingDate date) async {
    final weekly = await conn.execute(
      'SELECT Day, StartTime, end_Time FROM tutavailability WHERE TutorID = :t',
      {'t': tutorId},
    );
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
      'Sunday',
    ];
    return findAvailableLessons(
      from: date,
      through: date,
      nowUtc: DateTime.now().toUtc(),
      availability: [
        for (final row in weekly.rows)
          WeeklyAvailability(
            weekday: days.indexOf(row.reqStr('Day')) + 1,
            startMinutes: parseClockTime(row.reqStr('StartTime')),
            endMinutes: parseClockTime(row.reqStr('end_Time')),
          ),
      ],
      busyIntervals: const [],
      overrides: await loadAvailabilityOverrides(
        conn,
        tutorId,
        from: date,
        through: date,
      ),
    ).map((slot) => slot.startTime).toList();
  }

  Future<List<Map<String, String?>>> changeRows(BookingDate date) async {
    final rows = await conn.execute(
      'SELECT StartTime, EndTime FROM tutavailabilityoverride '
      'WHERE TutorID = :t AND `Date` = :d ORDER BY StartTime',
      {'t': tutorId, 'd': date.iso},
    );
    return rows.rows.map((r) => r.textAssoc()).toList();
  }

  Future<int> addBooking(BookingDate date, String start, String end) async {
    final student = await conn.execute(
      'SELECT StudentID FROM studentprofile ORDER BY StudentID LIMIT 1',
    );
    final subject = await conn.execute(
      'SELECT subjectId FROM subjects ORDER BY subjectId LIMIT 1',
    );
    final insert = await conn.execute(
      'INSERT INTO booking (StudentID, TutorID, SubjectID, `Date`, '
      'StartTime, EndTime, Note, Status, Created_at) '
      "VALUES (:s, :t, :subj, :d, :start, :end, 'availability-dates-test', "
      "'Confirmed', NOW())",
      {
        's': student.rows.first.str('StudentID'),
        't': tutorId,
        'subj': subject.rows.first.str('subjectId'),
        'd': date.iso,
        'start': start,
        'end': end,
      },
    );
    final id = insert.lastInsertID.toInt();
    addedBookings.add(id);
    return id;
  }

  setUpAll(() async {
    conn = await getConnection();
    final p = {'t': tutorId};
    weeklyBefore = (await conn.execute(
      'SELECT Day, StartTime, end_Time FROM tutavailability WHERE TutorID = :t',
      p,
    )).rows.map((r) => r.textAssoc()).toList();
    changesBefore = (await conn.execute(
      "SELECT DATE_FORMAT(`Date`, '%Y-%m-%d') AS D, StartTime, EndTime "
      'FROM tutavailabilityoverride WHERE TutorID = :t',
      p,
    )).rows.map((r) => r.textAssoc()).toList();

    // A known weekly pattern for the tests: Monday-Saturday 08:00-17:00.
    await conn.execute('DELETE FROM tutavailability WHERE TutorID = :t', p);
    for (final day in [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
    ]) {
      await conn.execute(
        'INSERT INTO tutavailability (TutorID, Day, StartTime, end_Time) '
        "VALUES (:t, :d, '08:00:00', '17:00:00')",
        {'t': tutorId, 'd': day},
      );
    }
    await conn.execute(
      'DELETE FROM tutavailabilityoverride WHERE TutorID = :t',
      p,
    );

    // Dates from 3 to 80 days ahead with no lessons booked, Monday-Saturday.
    final booked = (await conn.execute(
      "SELECT DISTINCT DATE_FORMAT(`Date`, '%Y-%m-%d') AS D FROM booking "
      'WHERE TutorID = :t AND `Date` >= CURDATE()',
      p,
    )).rows.map((r) => r.str('D')).toSet();
    final today = johannesburgDate(DateTime.now().toUtc());
    freeDates = [
      for (var i = 3; i <= 80; i++)
        if (today.addDays(i).weekday != DateTime.sunday &&
            !booked.contains(today.addDays(i).iso))
          today.addDays(i),
    ];
    expect(freeDates.length, greaterThan(10));
    final bookedWeekdays = {
      for (final d in booked) BookingDate.parse(d!).weekday,
    };
    quietDate = freeDates
        .skip(2) // the first two are used by the earlier tests
        .where((d) => !bookedWeekdays.contains(d.weekday))
        .firstOrNull;
  });

  tearDownAll(() async {
    final p = {'t': tutorId};
    for (final id in addedBookings) {
      await conn.execute(
        'DELETE FROM booking WHERE Booking_id = :id',
        {'id': id},
      );
    }
    await conn.execute('DELETE FROM tutavailability WHERE TutorID = :t', p);
    for (final a in weeklyBefore) {
      await conn.execute(
        'INSERT INTO tutavailability (TutorID, Day, StartTime, end_Time) '
        'VALUES (:t, :d, :s, :e)',
        {'t': tutorId, 'd': a['Day'], 's': a['StartTime'], 'e': a['end_Time']},
      );
    }
    await conn.execute(
      'DELETE FROM tutavailabilityoverride WHERE TutorID = :t',
      p,
    );
    for (final c in changesBefore) {
      await conn.execute(
        'INSERT INTO tutavailabilityoverride '
        '(TutorID, `Date`, StartTime, EndTime) VALUES (:t, :d, :s, :e)',
        {'t': tutorId, 'd': c['D'], 's': c['StartTime'], 'e': c['EndTime']},
      );
    }
    await conn.close();
  });

  test('a day off removes that date from the student slots only', () async {
    final date = freeDates[0];
    final weekLater = date.addDays(7);
    expect(await studentSlots(date), hasLength(9)); // 08:00 ... 16:00

    final response = await putDate({'date': date.iso, 'mode': 'off'});
    expect(response.statusCode, 200);
    final body = await response.json() as Map<String, dynamic>;
    final changes =
        (body['availabilityCalendar'] as Map)['dateChanges'] as List;
    expect(changes, [
      {'date': date.iso, 'dayOff': true, 'times': <Object>[]},
    ]);

    expect(await changeRows(date), [
      {'StartTime': null, 'EndTime': null},
    ]);
    expect(await studentSlots(date), isEmpty);
    expect(await studentSlots(weekLater), hasLength(9)); // other weeks stay
  });

  test(
    'custom hours replace the weekly hours, usual brings them back',
    () async {
      final date = freeDates[1];
      final custom = await putDate({
        'date': date.iso,
        'mode': 'custom',
        'times': [
          {'startTime': '18:00', 'endTime': '20:00'}, // after the weekly 17:00
          {'startTime': '09:00', 'endTime': '10:00'},
        ],
      });
      expect(custom.statusCode, 200);
      expect(await changeRows(date), [
        {'StartTime': '09:00:00', 'EndTime': '10:00:00'},
        {'StartTime': '18:00:00', 'EndTime': '20:00:00'},
      ]);
      expect(await studentSlots(date), ['09:00', '18:00', '19:00']);

      final usual = await putDate({'date': date.iso, 'mode': 'usual'});
      expect(usual.statusCode, 200);
      expect(await changeRows(date), isEmpty);
      expect(await studentSlots(date), hasLength(9));
    },
  );

  test('a booked lesson keeps its time open', () async {
    final date = quietDate ?? freeDates[2];
    await addBooking(date, '10:00:00', '11:00:00');

    // The calendar shows the lesson so the app can lock that hour.
    final profile = await call(
      profile_route.onRequest,
      'GET',
      '/TutorLandingpage/Profile',
    );
    final calendar =
        (await profile.json() as Map)['availabilityCalendar'] as Map;
    expect(
      calendar['bookings'],
      contains(
        equals({'date': date.iso, 'startTime': '10:00', 'endTime': '11:00'}),
      ),
    );

    final off = await putDate({'date': date.iso, 'mode': 'off'});
    expect(off.statusCode, 409);
    expect(((await off.json()) as Map)['error'], contains('lesson booked'));
    expect(await changeRows(date), isEmpty); // nothing saved

    final without = await putDate({
      'date': date.iso,
      'mode': 'custom',
      'times': [
        {'startTime': '13:00', 'endTime': '15:00'},
      ],
    });
    expect(without.statusCode, 409);

    final around = await putDate({
      'date': date.iso,
      'mode': 'custom',
      'times': [
        {'startTime': '10:00', 'endTime': '12:00'},
      ],
    });
    expect(around.statusCode, 200);
    expect(await changeRows(date), [
      {'StartTime': '10:00:00', 'EndTime': '12:00:00'},
    ]);
  });

  test(
    'the weekly grid can change around a lesson kept by a date change',
    () async {
      // quietDate has the 10:00 lesson, now covered by its own 10-12 hours,
      // so its weekday no longer needs the weekly hours.
      final date = quietDate;
      if (date == null) {
        markTestSkipped('Every weekday has a real lesson in this database');
        return;
      }
      const names = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
      ];
      final others = [
        for (final d in names)
          if (d != names[date.weekday - 1]) d,
      ];
      // Keep every other weekday so other lessons in the database stay covered.
      final response = await call(
        availability_route.onRequest,
        'PUT',
        '/TutorLandingpage/Profile/availability',
        body: {
          'availability': {
            for (final d in others) d: ['Morning', 'Afternoon', 'Evening'],
          },
        },
      );
      expect(response.statusCode, 200, reason: await response.body());
      expect(await studentSlots(date), ['10:00', '11:00']);
    },
  );
}
