// Database-backed test of MySqlAccountSuspensionRepository: the real SQL,
// constraints, locking and rollback. Like booking_flow_db_test.dart it only
// connects to the isolated `theotutoring_test` database and only runs when
// THEO_TEST_DB_PASSWORD is set. Migration 012_account_suspension_appeal must
// have been applied to that database.
import 'dart:io';

import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/db_row.dart';

const _testDatabase = 'theotutoring_test';
final _password = Platform.environment['THEO_TEST_DB_PASSWORD'];

void main() {
  group(
    'account suspensions against $_testDatabase',
    () {
      late MySQLConnection db;
      late String tag;
      late AdminIdentity admin;
      late int studentId;
      late String studentUid;
      late int tutorId;
      final userIds = <int>[];

      Future<MySQLConnection> connect() async {
        final connection = await MySQLConnection.createConnection(
          host: Platform.environment['THEO_TEST_DB_HOST'] ?? '127.0.0.1',
          port: int.parse(Platform.environment['THEO_TEST_DB_PORT'] ?? '3306'),
          userName: Platform.environment['THEO_TEST_DB_USER'] ?? 'theo_app',
          password: _password!,
          databaseName: _testDatabase,
          secure: true,
        );
        await connection.connect();
        return connection;
      }

      final repo = MySqlAccountSuspensionRepository(connectionFactory: connect);

      Future<int> insert(String sql, Map<String, dynamic> params) async =>
          (await db.execute(sql, params)).lastInsertID.toInt();

      Future<int> createUser(String label, String role, String status) async {
        final id = await insert(
          'INSERT INTO `user` (FirebaseUid, Name, PhoneNum, Email, Role, '
          'AccountStatus) VALUES (:uid, :name, :phone, :email, :role, :status)',
          {
            'uid': 'itest-uid-$tag-$label',
            'name': 'itest $label',
            'phone': '0000000000',
            'email': '$tag-$label@example.test',
            'role': role,
            'status': status,
          },
        );
        userIds.add(id);
        return id;
      }

      Future<String?> scalar(String sql, [Map<String, dynamic>? p]) async {
        final r = await db.execute(sql, p);
        return r.rows.isEmpty ? null : r.rows.first.colAt(0) as String?;
      }

      Future<String?> accountStatus(String uid) => scalar(
        'SELECT AccountStatus FROM `user` WHERE FirebaseUid = :uid',
        {'uid': uid},
      );

      Future<AccountStatusChange> suspendStudent() => repo.changeStatus(
        admin: admin,
        role: 'student',
        profileId: studentId,
        status: 'Suspended',
        reason: 'Repeated no-shows for booked lessons.',
      );

      setUpAll(() async {
        db = await connect();
        tag = 'itest${DateTime.now().millisecondsSinceEpoch}';
        final adminUser = await createUser('admin', 'admin', 'Active');
        admin = AdminIdentity(
          id: await insert(
            "INSERT INTO admin (UserId, RoleKey) VALUES (:u, 'super_admin')",
            {'u': adminUser},
          ),
          name: 'itest admin',
          roleKey: 'super_admin',
        );
        final studentUser = await createUser('student', 'student', 'Active');
        studentUid = 'itest-uid-$tag-student';
        studentId = await insert(
          'INSERT INTO studentprofile (Address, ProofOfReg, InstitutionYear, '
          'Course, Subject_of_interest, UserID) VALUES '
          "('itest', 'itest', '1', 'itest', 'itest', :userId)",
          {'userId': studentUser},
        );
        final tutorUser = await createUser('tutor', 'tutor', 'Pending');
        tutorId = await insert(
          'INSERT INTO tutorprofile (Bio, Experience, VerificationStat, '
          "UserID) VALUES ('itest', '1 year', 'Pending', :userId)",
          {'userId': tutorUser},
        );
      });

      tearDownAll(() async {
        final ids = userIds.join(', ');
        if (ids.isNotEmpty) {
          for (final sql in [
            'DELETE FROM suspensionappeal WHERE UserID IN ($ids)',
            'DELETE FROM accountsuspension WHERE UserID IN ($ids)',
            'DELETE FROM notification WHERE UserID IN ($ids)',
            'DELETE FROM studentprofile WHERE UserID IN ($ids)',
            'DELETE FROM tutorprofile WHERE UserID IN ($ids)',
            'DELETE FROM admin WHERE UserId IN ($ids)',
            'DELETE FROM `user` WHERE UserId IN ($ids)',
          ]) {
            await db.execute(sql);
          }
        }
        await db.close();
      });

      test('suspending writes the status, suspension and notice together',
          () async {
        final change = await suspendStudent();
        expect(change.previousStatus, 'Active');
        expect(await accountStatus(studentUid), 'Suspended');
        final row = (await db.execute(
          'SELECT SuspendedByAdminID, Reason, PreviousAccountStatus, Status, '
          'NotificationID FROM accountsuspension s INNER JOIN `user` u '
          'ON u.UserId = s.UserID WHERE u.FirebaseUid = :uid',
          {'uid': studentUid},
        )).rows.single;
        expect(row.str('SuspendedByAdminID'), '${admin.id}');
        expect(row.str('Reason'), 'Repeated no-shows for booked lessons.');
        expect(row.str('PreviousAccountStatus'), 'Active');
        expect(row.str('Status'), 'Active');
        expect(row.str('NotificationID'), '${change.notice!.notificationId}');
        expect(
          await scalar(
            'SELECT Type FROM notification WHERE NotificationID = :id',
            {'id': change.notice!.notificationId},
          ),
          'AccountSuspended',
        );

        // A second suspension is refused and nothing is added
        await expectLater(suspendStudent(), throwsA(isA<SuspensionConflict>()));
        expect(
          await scalar(
            'SELECT COUNT(*) FROM accountsuspension s INNER JOIN `user` u '
            'ON u.UserId = s.UserID WHERE u.FirebaseUid = :uid',
            {'uid': studentUid},
          ),
          '1',
        );
      });

      test('the notice is undelivered until marked, then not offered again',
          () async {
        final pending = await repo.undeliveredNotices(studentUid);
        expect(pending.single.firestoreId, startsWith('suspension-'));
        await repo.markDelivered(
          pending.single.notificationId,
          pending.single.firestoreId,
        );
        expect(await repo.undeliveredNotices(studentUid), isEmpty);
      });

      late int appealId;

      test('one appeal per suspension, also enforced by the schema', () async {
        final appeal = await repo.submitAppeal(
          studentUid,
          'I was in hospital that week and could not attend.',
        );
        appealId = appeal['appealId']! as int;
        await expectLater(
          repo.submitAppeal(studentUid, 'A second appeal about the same.'),
          throwsA(isA<SuspensionConflict>()),
        );
        // Bypassing the repository still cannot add a second appeal
        await expectLater(
          db.execute(
            'INSERT INTO suspensionappeal (SuspensionID, UserID, Explanation, '
            'SubmittedAtUtc, Status) SELECT SuspensionID, UserID, '
            "'A sneaky second appeal text', UTC_TIMESTAMP(6), 'Pending' "
            'FROM suspensionappeal WHERE AppealID = :id',
            {'id': appealId},
          ),
          throwsA(
            isA<MySQLServerException>().having(
              (e) => e.errorCode,
              'errorCode',
              1062,
            ),
          ),
        );
        expect(await accountStatus(studentUid), 'Suspended');
        final view = await repo.suspensionFor(studentUid);
        expect((view!['appeal']! as Map)['status'], 'Pending');
        expect(view['canAppeal'], isFalse);
      });

      test('a failure part-way through a decision rolls everything back',
          () async {
        final before = await scalar('SELECT COUNT(*) FROM notification');
        // AdminID 0 does not exist: the appeal update fails its foreign key
        // after the notice row was inserted
        await expectLater(
          repo.decideAppeal(
            admin: const AdminIdentity(
              id: 0,
              name: 'x',
              roleKey: 'super_admin',
            ),
            appealId: appealId,
            approve: true,
            note: null,
            roles: suspendableRoles,
          ),
          throwsA(isA<MySQLServerException>()),
        );
        expect(await scalar('SELECT COUNT(*) FROM notification'), before);
        expect(await accountStatus(studentUid), 'Suspended');
        expect(
          await scalar(
            'SELECT Status FROM suspensionappeal WHERE AppealID = :id',
            {'id': appealId},
          ),
          'Pending',
        );
      });

      test('two admins deciding at once: one wins, the state is consistent',
          () async {
        final results = await Future.wait([
          repo
              .decideAppeal(
                admin: admin,
                appealId: appealId,
                approve: true,
                note: null,
                roles: suspendableRoles,
              )
              .then<Object>((r) => r, onError: (Object e) => e),
          repo
              .decideAppeal(
                admin: admin,
                appealId: appealId,
                approve: false,
                note: 'The missed lessons were confirmed.',
                roles: suspendableRoles,
              )
              .then<Object>((r) => r, onError: (Object e) => e),
        ]);
        expect(results.whereType<AppealDecision>(), hasLength(1));
        expect(results.whereType<SuspensionConflict>(), hasLength(1));
        final decision = results.whereType<AppealDecision>().single;
        final approved = decision.appeal['status'] == 'Approved';
        expect(
          await accountStatus(studentUid),
          approved ? 'Active' : 'Suspended',
        );
        expect(
          await scalar(
            'SELECT s.Status FROM accountsuspension s INNER JOIN '
            'suspensionappeal a ON a.SuspensionID = s.SuspensionID '
            'WHERE a.AppealID = :id',
            {'id': appealId},
          ),
          approved ? 'Lifted' : 'Active',
        );
      });

      test('approval restores the previous status (a Pending tutor)', () async {
        final tutorUid = 'itest-uid-$tag-tutor';
        await repo.changeStatus(
          admin: admin,
          role: 'tutor',
          profileId: tutorId,
          status: 'Suspended',
          reason: 'Asked students to pay outside the platform.',
        );
        final appeal = await repo.submitAppeal(
          tutorUid,
          'That was a misunderstanding about the payment page.',
        );
        await repo.decideAppeal(
          admin: admin,
          appealId: appeal['appealId']! as int,
          approve: true,
          note: null,
          roles: {'tutor'},
        );
        expect(await accountStatus(tutorUid), 'Pending');
      });

      test('a student appeal cannot be decided with only tutor rights',
          () async {
        // Fresh suspension and appeal for the student
        if (await accountStatus(studentUid) != 'Suspended') {
          await suspendStudent();
        } else {
          await repo.changeStatus(
            admin: admin,
            role: 'student',
            profileId: studentId,
            status: 'Active',
          );
          await suspendStudent();
        }
        final appeal = await repo.submitAppeal(
          studentUid,
          'Please look at my case again; I have new evidence.',
        );
        await expectLater(
          repo.decideAppeal(
            admin: admin,
            appealId: appeal['appealId']! as int,
            approve: true,
            note: null,
            roles: {'tutor'},
          ),
          throwsA(isA<AdminPermissionDenied>()),
        );
        expect(await accountStatus(studentUid), 'Suspended');

        // Reinstating closes it and keeps the history
        await repo.changeStatus(
          admin: admin,
          role: 'student',
          profileId: studentId,
          status: 'Active',
        );
        expect(
          await scalar(
            'SELECT Status FROM suspensionappeal WHERE AppealID = :id',
            {'id': appeal['appealId']},
          ),
          'Closed',
        );
        final listed = await repo.listAppeals(
          status: 'all',
          roles: suspendableRoles,
        );
        expect(
          (listed['appeals']! as List)
              .where((a) => ((a as Map)['user'] as Map)['userId'] != null),
          isNotEmpty,
        );
      });
    },
    skip: _password == null
        ? 'Set THEO_TEST_DB_PASSWORD to run against theotutoring_test'
        : false,
  );
}
