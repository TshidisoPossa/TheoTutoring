import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';

import '../../../routes/students/register.dart' as route;

void main() {
  test(
    'persists student records and rolls back failed profile inserts',
    () async {
    final env = Platform.environment;
    final database = env['STUDENT_REGISTRATION_TEST_DATABASE'];
    final host = env['STUDENT_REGISTRATION_TEST_HOST'];
    final user = env['STUDENT_REGISTRATION_TEST_USER'];
    final password = env['STUDENT_REGISTRATION_TEST_PASSWORD'];
    final port = int.tryParse(env['STUDENT_REGISTRATION_TEST_PORT'] ?? '');
    if (database == null ||
        host == null ||
        user == null ||
        password == null ||
        port == null ||
        port < 1 ||
        port > 65535) {
      fail(
        'All valid student-registration test connection settings are required.',
      );
    }
    if (!database.startsWith('theotutoring_test_') ||
        (host != '127.0.0.1' && host != 'localhost')) {
      fail(
        'Test connection must target a local theotutoring_test_ database.',
      );
    }

    final connection = await MySQLConnection.createConnection(
      host: host,
      port: port,
      userName: user,
      password: password,
      databaseName: database,
    );
    await connection.connect();

    int? userId;
    int? studentId;
    final marker = DateTime.now().microsecondsSinceEpoch;
    final uid = 'registration-test-$marker';
    final email = 'registration-$marker@example.invalid';
    final rollbackUid = 'rollback-test-$marker';
    final rollbackEmail = 'rollback-$marker@example.invalid';

    Future<Response> register({
      required String firebaseUid,
      required String registrationEmail,
      String address = 'Test address',
    }) =>
        route.createStudentRecords(
          connection,
          firebaseUid: firebaseUid,
          fullName: 'Integration Test',
          email: registrationEmail,
          phone: '0000000000',
          address: address,
          course: 'Integration',
          tutoringModule: 'Testing',
          institutionYear: 'Year 1',
          profilePhotoUrl: null,
          proofOfRegistrationUrl: 'https://example.invalid/proof',
        );

    try {
      final selected = await connection.execute('SELECT DATABASE() AS db');
      if (selected.rows.isEmpty ||
          selected.rows.first.assoc()['db'] != database ||
          !database.startsWith('theotutoring_test_')) {
        fail(
          'Connected database does not match the configured scratch database.',
        );
      }

      final response =
          await register(firebaseUid: uid, registrationEmail: email);
      expect(response.statusCode, 201);
      final result = jsonDecode(await response.body()) as Map<String, dynamic>;
      userId = int.tryParse(result['userId'].toString());
      studentId = int.tryParse(result['studentId'].toString());
      expect(userId, isNotNull);
      expect(studentId, isNotNull);

      final rows = await connection.execute(
        '''
        SELECT u.UserId, sp.StudentID, u.Role, u.Password, sp.ProofofReg
        FROM User u JOIN StudentProfile sp ON sp.UserID = u.UserId
        WHERE u.UserId = :userId AND sp.StudentID = :studentId
          AND u.FirebaseUid = :uid AND u.Email = :email
        ''',
        {'userId': userId, 'studentId': studentId, 'uid': uid, 'email': email},
      );
      expect(rows.rows, hasLength(1));
      expect(rows.rows.first.assoc()['Role'], 'student');
      expect(rows.rows.first.assoc()['Password'], isNull);
      expect(
        rows.rows.first.assoc()['ProofofReg'],
        'https://example.invalid/proof',
      );
      expect(
        (await register(firebaseUid: uid, registrationEmail: email)).statusCode,
        409,
      );

      await connection.execute("SET SESSION sql_mode = 'STRICT_ALL_TABLES'");
      await expectLater(
        register(
          firebaseUid: rollbackUid,
          registrationEmail: rollbackEmail,
          address: List.filled(256, 'x').join(),
        ),
        throwsA(isA<MySQLServerException>()),
      );
      final rolledBack = await connection.execute(
        'SELECT UserId FROM User WHERE FirebaseUid = :uid',
        {'uid': rollbackUid},
      );
      expect(rolledBack.rows, isEmpty);
    } finally {
      try {
        if (userId != null && studentId != null) {
          final owned = await connection.execute(
            '''
            SELECT u.UserId, sp.StudentID
            FROM User u JOIN StudentProfile sp ON sp.UserID = u.UserId
            WHERE u.UserId = :userId AND sp.StudentID = :studentId
              AND u.FirebaseUid = :uid AND u.Email = :email
            ''',
            {
              'userId': userId,
              'studentId': studentId,
              'uid': uid,
              'email': email,
            },
          );
          if (owned.rows.length != 1) {
            fail('Cannot confirm ownership; leaving records untouched.');
          }
          await connection.execute(
            'DELETE FROM StudentProfile WHERE StudentID = :studentId '
            'AND UserID = :userId',
            {'studentId': studentId, 'userId': userId},
          );
          await connection.execute(
            'DELETE FROM User WHERE UserId = :userId '
            'AND FirebaseUid = :uid AND Email = :email',
            {'userId': userId, 'uid': uid, 'email': email},
          );
        }
      } finally {
        await connection.close();
      }
    }
  }, skip: Platform.environment['STUDENT_REGISTRATION_TEST_DATABASE'] == null);
}
