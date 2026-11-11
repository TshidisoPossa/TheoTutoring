import 'dart:io';

import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';

// Runs the student join rules (Google Meet design, section 3) against the
// real database from .env. Opt in, so a normal `dart test` never touches it:
//   JOIN_MYSQL_TEST_TUTOR_ID=1 dart test test/routes/students/join_lesson_mysql_test.dart
//
// Needs migration 008 (TutorProfile.MeetLink and the Postponed status).
// It adds sample bookings, payments and one package purchase for that tutor
// and the first active student, sets the tutor's MeetLink, and puts
// everything back afterwards. The Firebase login check is skipped: the
// repository is called with the student's FirebaseUid directly.

final _tutorId = int.tryParse(
  Platform.environment['JOIN_MYSQL_TEST_TUTOR_ID'] ?? '',
);

const _tutorLink = 'https://meet.google.com/aaa-bbbb-ccc';
const _bookingLink = 'https://meet.google.com/old-link-xyz';

void main() {
  if (_tutorId == null) {
    test(
      'Join rules against MySQL',
      () {},
      skip: 'Set JOIN_MYSQL_TEST_TUTOR_ID to run against the database',
    );
    return;
  }
  // Lessons are placed up to 2 hours either side of now (South African
  // time), so none of them may cross midnight.
  final sast = DateTime.now().toUtc().add(const Duration(hours: 2));
  if (sast.hour < 3 || sast.hour >= 21) {
    test(
      'Join rules against MySQL',
      () {},
      skip: 'Run between 03:00 and 21:00',
    );
    return;
  }

  late MySQLConnection conn;
  late MySqlStudentLessonsRepository repo;
  late String studentUid;
  late int studentId;
  int? otherStudentId;
  late int subjectId;
  String? savedMeetLink;
  int? purchaseId;
  int? attemptId;
  final ids = <String, int>{}; // name -> Booking_id

  // Adds a booking starting [startOffsetSeconds] from now (SAST) and lasting
  // an hour, using the database clock so the test and the rules agree.
  Future<void> add(
    String name, {
    required String status,
    required int startOffsetSeconds,
    int? forStudent,
    String? link,
    int? purchase,
  }) async {
    final result = await conn.execute(
      '''
      INSERT INTO booking (StudentID, TutorID, SubjectID, PurchaseID,
        LessonNumber, LessonPriceAtPurchase, `Date`, StartTime, EndTime,
        Note, Status, Link)
      SELECT :student, :tutor, :subject, :purchase,
        IF(:purchase IS NULL, NULL, 1), IF(:purchase IS NULL, NULL, 250.00),
        DATE(t.s), TIME(t.s), TIME(t.s + INTERVAL 1 HOUR),
        :note, :status, :link
      FROM (
        SELECT UTC_TIMESTAMP() + INTERVAL 2 HOUR
          + INTERVAL :offset SECOND AS s
      ) t
      ''',
      {
        'student': forStudent ?? studentId,
        'tutor': _tutorId,
        'subject': subjectId,
        'purchase': purchase,
        'note': 'join-mysql-test $name',
        'status': status,
        'link': link,
        'offset': startOffsetSeconds,
      },
    );
    ids[name] = result.lastInsertID.toInt();
  }

  Future<void> pay(String name) => conn.execute(
    'INSERT INTO payment (BookingId, PaymentMethod, PaymentStatus, '
    'Paid_At, Amount) '
    "VALUES (:b, 'Card', 'Successful', NOW(), 250)",
    {'b': ids[name]},
  );

  // Expects joinLink to refuse with [status] and [message].
  Future<void> refused(String name, int status, String message) async {
    await expectLater(
      repo.joinLink(studentUid, ids[name]!),
      throwsA(
        isA<LessonActionException>()
            .having((e) => e.statusCode, 'statusCode', status)
            .having((e) => e.message, 'message', message),
      ),
    );
  }

  setUpAll(() async {
    conn = await getConnection();
    repo = MySqlStudentLessonsRepository(conn);

    final students = await conn.execute(
      'SELECT sp.StudentID, u.FirebaseUid FROM studentprofile sp '
      'JOIN `user` u ON u.UserId = sp.UserID '
      "WHERE u.Role = 'student' AND u.AccountStatus = 'Active' "
      'ORDER BY sp.StudentID LIMIT 2',
    );
    studentId = int.parse(students.rows.first.reqStr('StudentID'));
    studentUid = students.rows.first.reqStr('FirebaseUid');
    if (students.rows.length > 1) {
      otherStudentId = int.parse(students.rows.last.reqStr('StudentID'));
    }
    final subject = await conn.execute(
      'SELECT subjectId FROM subjects ORDER BY subjectId LIMIT 1',
    );
    subjectId = int.parse(subject.rows.first.reqStr('subjectId'));

    final tutor = await conn.execute(
      'SELECT MeetLink FROM tutorprofile WHERE TutorID = :t',
      {'t': _tutorId},
    );
    savedMeetLink = tutor.rows.first.str('MeetLink');
    await conn.execute(
      'UPDATE tutorprofile SET MeetLink = :link WHERE TutorID = :t',
      {'link': _tutorLink, 't': _tutorId},
    );

    // A paid two-lesson package, for the Postponed package lesson.
    final purchase = await conn.execute(
      '''
      INSERT INTO bookingpurchase (StudentID, TutorID, SubjectID,
        PurchaseType, LessonCount, RatePerLesson, SubtotalAmount,
        DiscountPercent, DiscountAmount, TotalAmount, PurchaseStatus,
        CreatedAtUtc)
      VALUES (:s, :t, :subj, 'Package', 2, 250.00, 500.00, 0, 0, 500.00,
        'Paid', UTC_TIMESTAMP(6))
      ''',
      {'s': studentId, 't': _tutorId, 'subj': subjectId},
    );
    purchaseId = purchase.lastInsertID.toInt();
    final attempt = await conn.execute(
      '''
      INSERT INTO paymentattempt (PurchaseID, AttemptNumber, IdempotencyKey,
        PaymentMethod, DemoOutcome, PaymentStatus, Amount, CreatedAtUtc,
        UpdatedAtUtc)
      VALUES (:p, 1, 'join-mysql-test', 'CreditDebitCard', 'SimulatedSuccess',
        'Successful', 500.00, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))
      ''',
      {'p': purchaseId},
    );
    attemptId = attempt.lastInsertID.toInt();
    await conn.execute(
      '''
      INSERT INTO purchasepayment (PurchaseID, PaymentAttemptID, Amount,
        CreatedAtUtc)
      VALUES (:p, :a, 500.00, UTC_TIMESTAMP(6))
      ''',
      {'p': purchaseId, 'a': attemptId},
    );

    await add('open', status: 'Confirmed', startOffsetSeconds: 10 * 60);
    await add('exactly15', status: 'Confirmed', startOffsetSeconds: 15 * 60);
    await add('tooEarly', status: 'Confirmed', startOffsetSeconds: 16 * 60);
    await add('inProgress', status: 'Confirmed', startOffsetSeconds: -10 * 60);
    await add('ended', status: 'Confirmed', startOffsetSeconds: -2 * 3600);
    await add('cancelled', status: 'Cancelled', startOffsetSeconds: 5 * 60);
    await add('pending', status: 'Pending', startOffsetSeconds: 5 * 60);
    await add('postponedUnpaid', status: 'Postponed', startOffsetSeconds: 300);
    await add('postponedPaid', status: 'Postponed', startOffsetSeconds: 300);
    await pay('postponedPaid');
    await add(
      'postponedPackage',
      status: 'Postponed',
      startOffsetSeconds: 300,
      purchase: purchaseId,
    );
    await add(
      'bookingLink',
      status: 'Confirmed',
      startOffsetSeconds: 300,
      link: _bookingLink,
    );
    if (otherStudentId != null) {
      await add(
        'otherStudent',
        status: 'Confirmed',
        startOffsetSeconds: 300,
        forStudent: otherStudentId,
      );
    }
  });

  tearDownAll(() async {
    for (final id in ids.values) {
      await conn.execute('DELETE FROM payment WHERE BookingId = :id', {
        'id': id,
      });
      await conn.execute('DELETE FROM booking WHERE Booking_id = :id', {
        'id': id,
      });
    }
    if (purchaseId != null) {
      await conn.execute('DELETE FROM purchasepayment WHERE PurchaseID = :p', {
        'p': purchaseId,
      });
      await conn.execute('DELETE FROM paymentattempt WHERE PurchaseID = :p', {
        'p': purchaseId,
      });
      await conn.execute('DELETE FROM bookingpurchase WHERE PurchaseID = :p', {
        'p': purchaseId,
      });
    }
    await conn.execute(
      'UPDATE tutorprofile SET MeetLink = :link WHERE TutorID = :t',
      {'link': savedMeetLink, 't': _tutorId},
    );
    await conn.close();
  });

  test("a Confirmed lesson inside the window gets the tutor's link", () async {
    expect(await repo.joinLink(studentUid, ids['open']!), _tutorLink);
  });

  test('the window opens at exactly 15 minutes before the start', () async {
    expect(await repo.joinLink(studentUid, ids['exactly15']!), _tutorLink);
  });

  test('more than 15 minutes before the start is refused', () async {
    await refused(
      'tooEarly',
      409,
      'This session opens 15 minutes before it starts.',
    );
  });

  test('a lesson that has started but not ended can be joined', () async {
    expect(await repo.joinLink(studentUid, ids['inProgress']!), _tutorLink);
  });

  test('a lesson after its end time is refused', () async {
    await refused('ended', 409, 'This session has ended.');
  });

  test('Cancelled and Pending lessons are refused', () async {
    await refused('cancelled', 409, "This lesson can't be joined.");
    await refused('pending', 409, "This lesson can't be joined.");
  });

  test('an unpaid Postponed lesson is refused', () async {
    await refused('postponedUnpaid', 409, "This lesson can't be joined.");
  });

  test('a Postponed lesson paid directly can be joined', () async {
    expect(await repo.joinLink(studentUid, ids['postponedPaid']!), _tutorLink);
  });

  test('a Postponed lesson paid by package can be joined', () async {
    expect(
      await repo.joinLink(studentUid, ids['postponedPackage']!),
      _tutorLink,
    );
  });

  test("an older lesson's own Booking.Link wins over MeetLink", () async {
    expect(await repo.joinLink(studentUid, ids['bookingLink']!), _bookingLink);
  });

  test("another student's lesson is not found", () async {
    if (otherStudentId == null) {
      markTestSkipped('Needs a second active student in the database');
      return;
    }
    await refused('otherStudent', 404, 'Lesson not found.');
  });

  test('a booking id that does not exist is not found', () async {
    await expectLater(
      repo.joinLink(studentUid, 2147483647),
      throwsA(
        isA<LessonActionException>().having(
          (e) => e.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('a tutor with no link is refused', () async {
    await conn.execute(
      'UPDATE tutorprofile SET MeetLink = NULL WHERE TutorID = :t',
      {'t': _tutorId},
    );
    try {
      await refused(
        'open',
        409,
        "Your tutor hasn't connected Google Meet yet.",
      );
    } finally {
      await conn.execute(
        'UPDATE tutorprofile SET MeetLink = :link WHERE TutorID = :t',
        {'link': _tutorLink, 't': _tutorId},
      );
    }
  });
}
