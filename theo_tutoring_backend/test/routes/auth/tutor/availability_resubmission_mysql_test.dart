import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:test/test.dart';

import '../../../../routes/auth/tutor/availability.dart' as availability;
import '../../../../lib/firebase_auth.dart';

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

const _testDatabase = 'theotutoring_test';
final _testPassword = Platform.environment['THEO_TEST_DB_PASSWORD'];

void main() {
  test(
    'resubmission preserves the rejected row and creates one pending row',
    () async {
      final password = _testPassword!;
      final connection = await MySQLConnection.createConnection(
        host: Platform.environment['THEO_TEST_DB_HOST'] ?? '127.0.0.1',
        port: int.parse(Platform.environment['THEO_TEST_DB_PORT'] ?? '3306'),
        userName: Platform.environment['THEO_TEST_DB_USER'] ?? 'theo_app',
        password: password,
        databaseName: _testDatabase,
        secure: true,
      );
      await connection.connect();

      final tag = DateTime.now().microsecondsSinceEpoch.toString();
      final uid = 'tutor-resubmit-$tag';
      final email = 'tutor-resubmit-$tag@example.test';
      int? userId;
      int? tutorId;
      int? subjectId;

      Future<int> insert(String sql, Map<String, dynamic> params) async =>
          (await connection.execute(sql, params)).lastInsertID.toInt();

      Future<Response> submit() async {
        final context = _MockRequestContext();
        final request = _MockRequest();
        when(() => context.request).thenReturn(request);
        when(() => request.method).thenReturn(HttpMethod.post);
        when(
          () => request.headers,
        ).thenReturn({'Authorization': 'Bearer test'});
        when(request.json).thenAnswer(
          (_) async => {
            'availability': [
              {'day': 'Monday', 'startTime': '09:00', 'endTime': '10:00'},
            ],
          },
        );
        return availability.handleTutorAvailability(
          context,
          tokenVerifier: (_) async => FirebaseUser(
            uid: uid,
            email: email,
            emailVerified: true,
          ),
          connectionFactory: () async => connection,
        );
      }

      try {
        userId = await insert(
          'INSERT INTO `user` '
          '(FirebaseUid, Name, PhoneNum, Email, Role, AccountStatus) '
          "VALUES (:uid, 'Integration Tutor', '0000000000', :email, 'tutor', 'Rejected')",
          {'uid': uid, 'email': email},
        );
        tutorId = await insert(
          'INSERT INTO tutorprofile '
          '(UserID, Bio, Experience, Certificate, VerificationStat) '
          "VALUES (:userId, 'Bio', '3 years', 'https://example.test/cert.pdf', 'Rejected')",
          {'userId': userId},
        );
        subjectId = await insert(
          'INSERT INTO subjects (subjectName) VALUES (:name)',
          {'name': 'Resubmit $tag'},
        );
        await connection.execute(
          'INSERT INTO tutorsubjects (TutorID, SubjectID) '
          'VALUES (:tutorId, :subjectId)',
          {'tutorId': tutorId, 'subjectId': subjectId},
        );
        await connection.execute(
          'INSERT INTO qualification (TutorID, Degree, Institution) '
          "VALUES (:tutorId, 'BSc', 'Test University')",
          {'tutorId': tutorId},
        );
        await connection.execute(
          'INSERT INTO tutorapplication '
          '(TutorID, Status, AdminFeedback, Review_at) '
          "VALUES (:tutorId, 'Rejected', 'Upload a clearer certificate.', NOW())",
          {'tutorId': tutorId},
        );
        await connection.execute(
          'INSERT INTO tutavailability (TutorID, Day, StartTime, end_Time) '
          "VALUES (:tutorId, 'Monday', '08:00', '09:00')",
          {'tutorId': tutorId},
        );

        // Step 3 is refused, and nothing changes, until Google Meet is
        // connected (TutorProfile.MeetLink).
        final noMeet = await submit();
        expect(noMeet.statusCode, HttpStatus.badRequest);
        expect(
          await noMeet.json(),
          {'error': 'Please connect Google Meet first.'},
        );
        final stillRejected = await connection.execute(
          'SELECT COUNT(*) AS n FROM tutorapplication WHERE TutorID = :tutorId',
          {'tutorId': tutorId},
        );
        expect(stillRejected.rows.single.str('n'), '1');

        await connection.execute(
          'UPDATE tutorprofile SET MeetLink = :link WHERE TutorID = :tutorId',
          {'link': 'https://meet.google.com/abc-mnop-xyz', 'tutorId': tutorId},
        );

        final first = await submit();
        expect(first.statusCode, HttpStatus.ok);

        final applications = await connection.execute(
          'SELECT Status, AdminFeedback FROM tutorapplication '
          'WHERE TutorID = :tutorId ORDER BY TutApplication DESC',
          {'tutorId': tutorId},
        );
        expect(applications.rows.length, 2);
        expect(applications.rows.first.str('Status'), 'Pending');
        expect(applications.rows.last.str('Status'), 'Rejected');
        expect(
          applications.rows.last.str('AdminFeedback'),
          'Upload a clearer certificate.',
        );

        final user = await connection.execute(
          'SELECT AccountStatus FROM `user` WHERE UserId = :userId',
          {'userId': userId},
        );
        final profile = await connection.execute(
          'SELECT VerificationStat FROM tutorprofile WHERE TutorID = :tutorId',
          {'tutorId': tutorId},
        );
        expect(user.rows.single.str('AccountStatus'), 'Pending');
        expect(profile.rows.single.str('VerificationStat'), 'Pending');

        final slots = await connection.execute(
          'SELECT Day, StartTime, end_Time FROM tutavailability '
          'WHERE TutorID = :tutorId',
          {'tutorId': tutorId},
        );
        expect(slots.rows.length, 1);
        expect(slots.rows.single.str('StartTime'), '09:00:00');

        final duplicate = await submit();
        expect(duplicate.statusCode, HttpStatus.ok);
        final duplicateCheck = await connection.execute(
          'SELECT COUNT(*) AS n FROM tutorapplication WHERE TutorID = :tutorId',
          {'tutorId': tutorId},
        );
        expect(duplicateCheck.rows.single.str('n'), '2');
      } finally {
        if (tutorId != null) {
          for (final table in [
            'tutavailability',
            'qualification',
            'tutorsubjects',
            'tutorapplication',
          ]) {
            await connection.execute(
              'DELETE FROM $table WHERE TutorID = :tutorId',
              {'tutorId': tutorId},
            );
          }
          await connection.execute(
            'DELETE FROM tutorprofile WHERE TutorID = :tutorId',
            {'tutorId': tutorId},
          );
        }
        if (userId != null) {
          await connection.execute(
            'DELETE FROM `user` WHERE UserId = :userId',
            {'userId': userId},
          );
        }
        if (subjectId != null) {
          await connection.execute(
            'DELETE FROM subjects WHERE subjectId = :subjectId',
            {'subjectId': subjectId},
          );
        }
        await connection.close();
      }
    },
    skip: _testPassword == null
        ? 'Set THEO_TEST_DB_PASSWORD to use the isolated test database'
        : false,
  );
}
