import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';
import 'package:theo_tutoring_backend/student_reports.dart';

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

/// Answers each query by its SQL text and records every call, so the tests
/// can check exactly what reached Report.
class _Database {
  _Database({
    this.student = const {'UserId': '10', 'StudentID': '3'},
    this.lessonTutorUserId = '20',
    this.profileTutorUserId = '21',
    this.hasOpenDuplicate = false,
  });

  final Map<String, String?>? student;
  final String? lessonTutorUserId;
  final String? profileTutorUserId;
  final bool hasOpenDuplicate;
  final calls = <(String, Map<String, dynamic>?)>[];

  late final MySQLConnection connection = _build();

  MySQLConnection _build() {
    // Results are built first: mocktail cannot stub inside another stub.
    final studentResult = _result([if (student case final row?) row]);
    final lessonResult = _result([
      if (lessonTutorUserId != null) {'ReportedUserID': lessonTutorUserId},
    ]);
    final tutorResult = _result([
      if (profileTutorUserId != null) {'UserID': profileTutorUserId},
    ]);
    final duplicateResult = _result([
      if (hasOpenDuplicate) {'1': '1'},
    ]);
    final insertResult = _result([], lastInsertId: 77);

    final connection = _MockConnection();
    when(() => connection.execute(any(), any())).thenAnswer((invocation) async {
      final sql = invocation.positionalArguments[0] as String;
      calls.add((
        sql,
        invocation.positionalArguments[1] as Map<String, dynamic>?,
      ));
      if (sql.contains('FROM `user` u')) return studentResult;
      if (sql.contains('FROM booking b')) return lessonResult;
      if (sql.contains('FROM tutorprofile')) return tutorResult;
      if (sql.contains('FROM report')) return duplicateResult;
      if (sql.contains('INSERT INTO report')) return insertResult;
      fail('Unexpected query: $sql');
    });
    return connection;
  }

  (String, Map<String, dynamic>?)? call(String fragment) {
    for (final call in calls) {
      if (call.$1.contains(fragment)) return call;
    }
    return null;
  }
}

IResultSet _result(List<Map<String, String?>> rows, {int lastInsertId = 0}) {
  final resultRows = [for (final values in rows) _row(values)];
  final result = _MockResult();
  when(() => result.rows).thenReturn(resultRows);
  when(() => result.lastInsertID).thenReturn(BigInt.from(lastInsertId));
  return result;
}

ResultSetRow _row(Map<String, String?> values) {
  final row = _MockRow();
  when(() => row.colByName(any())).thenAnswer(
    (invocation) => values[invocation.positionalArguments.first as String],
  );
  return row;
}

Matcher _lessonError(int statusCode, String message) =>
    isA<LessonActionException>()
        .having((e) => e.statusCode, 'statusCode', statusCode)
        .having((e) => e.message, 'message', message);

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  group('reportLesson', () {
    test(
      'files a Report with the submitted reason and UTC time',
      () async {
        final db = _Database();
        final id = await MySqlStudentReportsRepository(
          db.connection,
        ).reportLesson('student-uid', 5, 'The tutor did not show up');

        expect(id, 77);
        final insert = db.call('INSERT INTO report')!;
        expect(
          insert.$1,
          contains('ReporterID, ReportedUserID, BookingID'),
        );
        expect(insert.$1, contains('Reason, Status, Created_at'));
        expect(insert.$1, contains("'Open'"));
        expect(insert.$1, contains('UTC_TIMESTAMP()'));
        expect(insert.$2, {
          'reporterId': 10,
          'reportedUserId': 20,
          'bookingId': 5,
          'reason': 'The tutor did not show up',
        });
        expect(db.call('INSERT INTO userreport'), isNull);
      },
    );

    test('checks for an unresolved Report on the same lesson', () async {
      final db = _Database();
      await MySqlStudentReportsRepository(
        db.connection,
      ).reportLesson('student-uid', 5, 'The tutor did not show up');

      final check = db.call('FROM report')!;
      expect(check.$1, contains('ReporterID = :reporterId'));
      expect(check.$1, contains("Status <> 'Resolved'"));
      expect(check.$2, {
        'reporterId': 10,
        'reportedUserId': 20,
        'bookingId': 5,
      });
    });

    test('an open duplicate is a 409 and nothing is inserted', () async {
      final db = _Database(hasOpenDuplicate: true);
      await expectLater(
        MySqlStudentReportsRepository(
          db.connection,
        ).reportLesson('student-uid', 5, 'The tutor did not show up'),
        throwsA(
          _lessonError(
            409,
            'You have already reported this lesson. '
            'An administrator will review it.',
          ),
        ),
      );
      expect(db.call('INSERT INTO report'), isNull);
    });

    test("another student's lesson is a 404 before any report query", () async {
      final db = _Database(lessonTutorUserId: null);
      await expectLater(
        MySqlStudentReportsRepository(
          db.connection,
        ).reportLesson('student-uid', 5, 'The tutor did not show up'),
        throwsA(_lessonError(404, 'Lesson not found.')),
      );
      expect(db.call('FROM booking b'), isNotNull);
      expect(db.call('FROM report'), isNull);
      expect(db.call('INSERT INTO report'), isNull);
    });
  });

  group('reportTutor', () {
    test('files a tutor report without a lesson', () async {
      final db = _Database();
      final id = await MySqlStudentReportsRepository(
        db.connection,
      ).reportTutor('student-uid', 8, 'Rude in messages');

      expect(id, 77);
      expect(db.call('FROM report')!.$2?['bookingId'], isNull);
      expect(db.call('INSERT INTO report')!.$2, {
        'reporterId': 10,
        'reportedUserId': 21,
        'bookingId': null,
        'reason': 'Rude in messages',
      });
      expect(db.call('INSERT INTO userreport'), isNull);
    });

    test('an open duplicate tutor report is a 409', () async {
      final db = _Database(hasOpenDuplicate: true);
      await expectLater(
        MySqlStudentReportsRepository(
          db.connection,
        ).reportTutor('student-uid', 8, 'Rude in messages'),
        throwsA(
          _lessonError(
            409,
            'You have already reported this tutor. '
            'An administrator will review it.',
          ),
        ),
      );
      expect(db.call('INSERT INTO report'), isNull);
    });

    test('an unknown tutor is a 404', () async {
      final db = _Database(profileTutorUserId: null);
      await expectLater(
        MySqlStudentReportsRepository(
          db.connection,
        ).reportTutor('student-uid', 8, 'Rude in messages'),
        throwsA(_lessonError(404, 'Tutor not found.')),
      );
      expect(db.call('Report'), isNull);
    });
  });

  test('a non-student account is denied before any report query', () async {
    final db = _Database(student: null);
    await expectLater(
      MySqlStudentReportsRepository(
        db.connection,
      ).reportTutor('tutor-uid', 8, 'Rude in messages'),
      throwsA(isA<StudentDashboardDenied>()),
    );
    expect(db.call('Report'), isNull);
  });
}
