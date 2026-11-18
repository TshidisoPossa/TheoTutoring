// Runs migration 013 itself against the isolated `theotutoring_test`
// database (MySQL 8.4, lower_case_table_names = 0, like Aiven) and checks
// its schema, its evidence-based commission backfill, its time-zone handling
// and that re-running it is safe. Opt-in: only runs when
// THEO_TEST_DB_PASSWORD is set, and refuses any other database.
//
// The migration must already have been applied once to theotutoring_test
// (this test re-runs it, which is what a rerun must survive). To keep the
// backfill away from other test data, the evidence boundary is moved to 2035
// and this test's purchases are dated around it; platformsettings is
// restored afterwards. The partial-schema case briefly changes and restores
// payout.PaymentReference / chk_payout_reference on the test database only.
import 'dart:io';

import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/db_row.dart';

import '../support/sql_script.dart';

const _testDatabase = 'theotutoring_test';
final _password = Platform.environment['THEO_TEST_DB_PASSWORD'];

void main() {
  group(
    'migration 013 against $_testDatabase',
    () {
      late MySQLConnection db;
      late String tag;
      late int studentId;
      late int tutorId;
      late int subjectId;
      late Map<String, String?> originalSettings;
      final userIds = <int>[];
      final purchaseIds = <int>[];
      final migration = sqlScriptStatements(
        File(
          'database/migrations/013_payout_payment_tracking.sql',
        ).readAsStringSync(),
      );

      Future<MySQLConnection> connect() async {
        final connection = await MySQLConnection.createConnection(
          host: Platform.environment['THEO_TEST_DB_HOST'] ?? '127.0.0.1',
          port: int.parse(Platform.environment['THEO_TEST_DB_PORT'] ?? '3306'),
          userName: Platform.environment['THEO_TEST_DB_USER'] ?? 'theo_app',
          password: _password!,
          databaseName: _testDatabase,
          // ignore: avoid_redundant_argument_values, as the other DB tests
          secure: true,
        );
        await connection.connect();
        return connection;
      }

      Future<List<Map<String, String?>>> rows(
        String sql, [
        Map<String, dynamic>? params,
      ]) async => [
        for (final r in (await db.execute(sql, params)).rows) r.textAssoc(),
      ];

      Future<int> insert(String sql, Map<String, dynamic> params) async =>
          (await db.execute(sql, params)).lastInsertID.toInt();

      /// Runs the migration file on [connection] (default: [db]), after
      /// setting the operator's optional UTC offset for UpdatedAt.
      Future<void> runMigration({
        String? utcOffset,
        MySQLConnection? connection,
      }) async {
        final c = connection ?? db;
        await c.execute(
          'SET @theo_013_settings_utc_offset = :offset',
          {'offset': utcOffset},
        );
        for (final statement in migration) {
          await c.execute(statement);
        }
      }

      /// A Held purchase with no commission rate, created at [createdAtUtc].
      Future<int> unresolvedPurchase(
        String createdAtUtc, {
        String? rate,
        String? source,
      }) async {
        final id = await insert(
          'INSERT INTO bookingpurchase (StudentID, TutorID, SubjectID, '
          'PurchaseType, LessonCount, RatePerLesson, SubtotalAmount, '
          'DiscountPercent, DiscountAmount, TotalAmount, '
          'CommissionPercentage, CommissionSource, PurchaseStatus, '
          "CreatedAtUtc) VALUES (:s, :t, :sub, 'Single', 1, 175.00, 175.00, "
          "0, 0, 175.00, :rate, :source, 'Held', :created)",
          {
            's': studentId,
            't': tutorId,
            'sub': subjectId,
            'rate': rate,
            'source': source,
            'created': createdAtUtc,
          },
        );
        purchaseIds.add(id);
        return id;
      }

      Future<(String?, String?)> commission(int purchaseId) async {
        final r = (await rows(
          'SELECT CommissionPercentage, CommissionSource FROM bookingpurchase '
          'WHERE PurchaseID = :id',
          {'id': purchaseId},
        )).single;
        return (r['CommissionPercentage'], r['CommissionSource']);
      }

      /// Sets the settings row's UpdatedAt (server-local) and rate.
      Future<void> settings(String updatedAt, String rate) => db.execute(
        'UPDATE platformsettings SET UpdatedAt = :at, '
        'CommissionPercentage = :rate WHERE SettingsID = 1',
        {'at': updatedAt, 'rate': rate},
      );

      setUpAll(() async {
        db = await connect();
        final selected = await rows('SELECT DATABASE() AS db');
        if (selected.single['db'] != _testDatabase) {
          throw StateError('Refusing to run: connected to the wrong database.');
        }
        final lctn = await rows(
          'SELECT @@lower_case_table_names AS v, @@version AS version',
        );
        if (lctn.single['v'] != '0') {
          throw StateError(
            'theotutoring_test must use lower_case_table_names = 0, like '
            'Aiven (found ${lctn.single['v']} on ${lctn.single['version']}).',
          );
        }
        originalSettings = (await rows(
          'SELECT UpdatedAt, CommissionPercentage FROM platformsettings '
          'WHERE SettingsID = 1',
        )).single;
        tag = 'm013${DateTime.now().millisecondsSinceEpoch}';
        Future<int> user(String role) async {
          final id = await insert(
            'INSERT INTO `user` (FirebaseUid, Name, PhoneNum, Email, Role, '
            "AccountStatus) VALUES (:uid, :name, '0000000000', :email, "
            ":role, 'Active')",
            {
              'uid': 'itest-uid-$tag-$role',
              'name': 'itest $role',
              'email': '$tag-$role@example.test',
              'role': role,
            },
          );
          userIds.add(id);
          return id;
        }

        subjectId = await insert(
          'INSERT INTO subjects (subjectName) VALUES (:name)',
          {'name': '$tag-subject'},
        );
        tutorId = await insert(
          'INSERT INTO tutorprofile (Bio, Experience, VerificationStat, '
          "UserID) VALUES ('itest', '1 year', 'Approved', :u)",
          {'u': await user('tutor')},
        );
        studentId = await insert(
          'INSERT INTO studentprofile (Address, ProofOfReg, InstitutionYear, '
          'Course, Subject_of_interest, UserID) VALUES '
          "('itest', 'itest', '1', 'itest', 'itest', :u)",
          {'u': await user('student')},
        );
      });

      tearDownAll(() async {
        await db.execute(
          'UPDATE platformsettings SET UpdatedAt = :at, '
          'CommissionPercentage = :rate WHERE SettingsID = 1',
          {
            'at': originalSettings['UpdatedAt'],
            'rate': originalSettings['CommissionPercentage'],
          },
        );
        if (purchaseIds.isNotEmpty) {
          await db.execute(
            'DELETE FROM bookingpurchase WHERE PurchaseID IN '
            '(${purchaseIds.join(',')})',
          );
        }
        await db.execute(
          'DELETE FROM studentprofile WHERE StudentID = $studentId',
        );
        await db.execute('DELETE FROM tutorprofile WHERE TutorID = $tutorId');
        await db.execute('DELETE FROM subjects WHERE subjectId = $subjectId');
        await db.execute(
          'DELETE FROM `user` WHERE UserId IN (${userIds.join(',')})',
        );
        await db.close();
      });

      test('re-running leaves the full schema and the ledger row', () async {
        await runMigration();
        await runMigration();
        final columns = {
          for (final r in await rows(
            'SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE '
            'FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() '
            "AND ((TABLE_NAME = 'bookingpurchase' AND COLUMN_NAME IN "
            "('CommissionPercentage', 'CommissionSource')) OR "
            "(TABLE_NAME = 'payout' AND COLUMN_NAME IN "
            "('PaidByAdminID', 'PaymentReference')))",
          ))
            '${r['TABLE_NAME']}.${r['COLUMN_NAME']}':
                '${r['COLUMN_TYPE']} ${r['IS_NULLABLE']}',
        };
        expect(columns, {
          'bookingpurchase.CommissionPercentage': 'decimal(5,2) YES',
          'bookingpurchase.CommissionSource':
              "enum('Purchase','Backfilled','Manual') YES",
          'payout.PaidByAdminID': 'int YES',
          'payout.PaymentReference': 'varchar(100) YES',
        });
        final constraints = {
          for (final r in await rows(
            'SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, ENFORCED '
            'FROM information_schema.TABLE_CONSTRAINTS '
            'WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME IN '
            "('chk_purchase_commission_rate', "
            "'chk_purchase_commission_source', 'fk_payout_paid_by', "
            "'chk_payout_paid_by', 'chk_payout_reference', "
            "'chk_payout_action_amount', 'chk_payout_action_reference',"
            " 'fk_payout_action_payout', 'fk_payout_action_admin',"
            " 'uq_payout_action_once')",
          ))
            r['CONSTRAINT_NAME']!: '${r['CONSTRAINT_TYPE']} ${r['ENFORCED']}',
        };
        expect(constraints, hasLength(10));
        expect(constraints['uq_payout_action_once'], 'UNIQUE YES');
        expect(constraints['fk_payout_paid_by'], 'FOREIGN KEY YES');
        final ledger = await rows(
          'SELECT COUNT(*) AS n FROM schemamigrations '
          "WHERE Version = '013_payout_payment_tracking'",
        );
        expect(ledger.single['n'], '1');
        final procedures = await rows(
          'SELECT COUNT(*) AS n FROM information_schema.ROUTINES '
          'WHERE ROUTINE_SCHEMA = DATABASE() '
          "AND ROUTINE_NAME = 'apply_013_payout_payment_tracking'",
        );
        expect(procedures.single['n'], '0'); // cleaned up
      });

      test('backfills only purchases created after UpdatedAt, and never '
          'overwrites a recorded rate', () async {
        await settings('2035-01-01 00:00:00', '10.00');
        final before = await unresolvedPurchase('2034-06-01 09:00:00');
        final sameSecond = await unresolvedPurchase('2035-01-01 00:00:00.5');
        final after = await unresolvedPurchase('2035-06-01 09:00:00');
        final captured = await unresolvedPurchase(
          '2035-06-01 09:00:00',
          rate: '12.00',
          source: 'Purchase',
        );
        final manual = await unresolvedPurchase(
          '2034-06-01 09:00:00',
          rate: '9.00',
          source: 'Manual',
        );

        await runMigration(utcOffset: '+00:00');
        expect(await commission(before), (null, null)); // no evidence
        expect(await commission(sameSecond), (null, null)); // 1s margin
        expect(await commission(after), ('10.00', 'Backfilled'));
        expect(await commission(captured), ('12.00', 'Purchase'));
        expect(await commission(manual), ('9.00', 'Manual'));

        // The setting changes later; a rerun keeps every recorded value.
        await settings('2035-08-01 00:00:00', '15.00');
        await runMigration(utcOffset: '+00:00');
        expect(await commission(after), ('10.00', 'Backfilled'));
        expect(await commission(captured), ('12.00', 'Purchase'));
        expect(await commission(manual), ('9.00', 'Manual'));
        expect(await commission(before), (null, null));
        // A purchase after the new boundary gets the new rate.
        final later = await unresolvedPurchase('2035-09-01 09:00:00');
        await runMigration(utcOffset: '+00:00');
        expect(await commission(later), ('15.00', 'Backfilled'));
      });

      test('converts server-local UpdatedAt to UTC with the given offset',
          () async {
        // 02:00 at +02:00 is 00:00 UTC; the purchase is at 00:30 UTC.
        await settings('2036-01-01 02:00:00', '10.00');
        final p = await unresolvedPurchase('2036-01-01 00:30:00');
        await runMigration(utcOffset: '+00:00'); // 02:00 UTC: too early
        expect(await commission(p), (null, null));
        await runMigration(utcOffset: '+02:00');
        expect(await commission(p), ('10.00', 'Backfilled'));
      });

      test('an unknown time zone backfills nothing', () async {
        await settings('2037-01-01 00:00:00', '10.00');
        final p = await unresolvedPurchase('2037-06-01 00:00:00');
        // Not a fixed offset (named zones are not accepted), or garbage.
        for (final offset in ['Africa/Johannesburg', '+2', '+25:00', '']) {
          await runMigration(utcOffset: offset);
          expect(await commission(p), (null, null), reason: offset);
        }
        // No offset given and a session zone other than the server's: the
        // zone UpdatedAt was written in is not known.
        final other = await connect();
        try {
          final zones = (await other.execute(
            'SELECT @@global.time_zone AS g',
          )).rows.first.textAssoc();
          final different = zones['g'] == '+05:45' ? '+03:00' : '+05:45';
          await other.execute("SET SESSION time_zone = '$different'");
          await runMigration(connection: other);
          expect(await commission(p), (null, null));
        } finally {
          await other.close();
        }
        // In the server's own zone the evidence is usable.
        await runMigration();
        expect(await commission(p), ('10.00', 'Backfilled'));
      });

      test('a missing piece is added back; a wrong one stops the migration',
          () async {
        await db.execute('ALTER TABLE payout DROP CHECK chk_payout_reference');
        await runMigration();
        final restored = await rows(
          'SELECT COUNT(*) AS n FROM information_schema.TABLE_CONSTRAINTS '
          'WHERE CONSTRAINT_SCHEMA = DATABASE() '
          "AND CONSTRAINT_NAME = 'chk_payout_reference'",
        );
        expect(restored.single['n'], '1');

        await db.execute(
          'ALTER TABLE payout MODIFY COLUMN PaymentReference VARCHAR(120) NULL',
        );
        try {
          await expectLater(
            runMigration(),
            throwsA(
              isA<MySQLServerException>().having(
                (e) => e.message,
                'message',
                contains('013: payout.PaymentReference'),
              ),
            ),
          );
        } finally {
          await db.execute(
            'DROP PROCEDURE IF EXISTS apply_013_payout_payment_tracking',
          );
          await db.execute(
            'ALTER TABLE payout MODIFY COLUMN PaymentReference '
            'VARCHAR(100) NULL',
          );
        }
        await runMigration(); // complete again
      });
    },
    skip: _password == null
        ? 'Set THEO_TEST_DB_PASSWORD to run against theotutoring_test'
        : false,
  );
}
