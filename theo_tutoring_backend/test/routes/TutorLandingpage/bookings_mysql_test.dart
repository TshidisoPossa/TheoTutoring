import 'dart:io';

import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/tutor_bookings.dart';

// Runs the bookings list query against the real database from .env, as one
// tutor. bookings_test.dart uses a fake repository, so only this checks the
// SQL. Opt in, so a normal `dart test` never touches the database:
//   BOOKINGS_MYSQL_TEST_TUTOR_ID=1 dart test test/routes/TutorLandingpage/bookings_mysql_test.dart
// It adds two sample bookings for that tutor and deletes them afterwards, and
// sets the tutor's MeetLink and puts it back.

final _tutorId = int.tryParse(
  Platform.environment['BOOKINGS_MYSQL_TEST_TUTOR_ID'] ?? '',
);

const _meetLink = 'https://meet.google.com/aaa-bbbb-ccc';
const _ownLink =
    'https://zoom.us/j/123456789'; // an older lesson's Booking.Link

void main() {
  if (_tutorId == null) {
    test(
      'Bookings list against MySQL',
      () {},
      skip: 'Set BOOKINGS_MYSQL_TEST_TUTOR_ID to run against the database',
    );
    return;
  }

  late MySQLConnection conn;
  final ids = <String, int>{}; // name -> Booking_id of each test booking
  String? savedMeetLink;

  setUpAll(() async {
    conn = await getConnection();

    final tutor = await conn.execute(
      'SELECT MeetLink FROM TutorProfile WHERE TutorID = :t',
      {'t': _tutorId},
    );
    savedMeetLink = tutor.rows.first.str('MeetLink');
    await conn.execute(
      'UPDATE TutorProfile SET MeetLink = :link WHERE TutorID = :t',
      {'link': _meetLink, 't': _tutorId},
    );

    final subject = await conn.execute(
      'SELECT subjectId FROM Subjects ORDER BY subjectId LIMIT 1',
    );
    final student = await conn.execute(
      'SELECT StudentID FROM StudentProfile ORDER BY StudentID LIMIT 1',
    );

    // Far in the future, so they are the newest and inside the list's limit.
    Future<void> add(String name, {String? link}) async {
      final result = await conn.execute(
        'INSERT INTO Booking (StudentID, TutorID, SubjectID, `Date`, '
        'StartTime, EndTime, Note, Link, Status) '
        "VALUES (:st, :t, :subj, '2099-01-01', '10:00:00', '11:00:00', "
        ":note, :link, 'Confirmed')",
        {
          'st': student.rows.first.str('StudentID'),
          't': _tutorId,
          'subj': subject.rows.first.str('subjectId'),
          'note': 'bookings-mysql-test $name',
          'link': link,
        },
      );
      ids[name] = result.lastInsertID.toInt();
    }

    await add('meet room');
    await add('own link', link: _ownLink);
  });

  tearDownAll(() async {
    for (final id in ids.values) {
      await conn.execute(
        'DELETE FROM Booking WHERE Booking_id = :id',
        {'id': id},
      );
    }
    await conn.execute(
      'UPDATE TutorProfile SET MeetLink = :link WHERE TutorID = :t',
      {'link': savedMeetLink, 't': _tutorId},
    );
    await conn.close();
  });

  test(
    "link is the tutor's Meet room, unless the booking has its own",
    () async {
      final bookings = await MySqlTutorBookingsRepository(
        conn,
      ).listForTutor(_tutorId!);
      String? linkOf(String name) =>
          bookings.firstWhere((b) => b.bookingId == ids[name]).link;
      expect(linkOf('meet room'), _meetLink);
      expect(linkOf('own link'), _ownLink);
    },
  );
}
