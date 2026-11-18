// Database-backed test of MySqlAdminPayoutsRepository: payout generation,
// the Pending -> Approved -> Paid workflow, the audit trail, refunds after a
// payout and the schema's own guards. Like the other integration tests it
// only connects to the isolated `theotutoring_test` database, refuses to run
// anywhere else, and only runs when THEO_TEST_DB_PASSWORD is set. Migration
// 013_payout_payment_tracking must have been applied to that database.
//
// Generation scans the whole test database, so it may also create payouts
// for other test data; tearDownAll removes every payout this run generated
// (identified by its 'Generated' audit row) along with this run's rows.
import 'dart:io';

import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_payouts.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/payout_finance.dart';

import '../support/test_database.dart';

const _testDatabase = 'theotutoring_test';
final _password = Platform.environment['THEO_TEST_DB_PASSWORD'];

void main() {
  group(
    'payouts against $_testDatabase',
    () {
      late MySQLConnection db;
      late String tag;
      late AdminIdentity admin;
      late int tutorId;
      late int studentId;
      late int subjectId;
      final userIds = <int>[];
      final purchaseIds = <int>[];
      final bookings = <String, int>{};

      Future<MySQLConnection> connect() async {
        final connection = await MySQLConnection.createConnection(
          host: Platform.environment['THEO_TEST_DB_HOST'] ?? '127.0.0.1',
          port: int.parse(Platform.environment['THEO_TEST_DB_PORT'] ?? '3306'),
          userName: Platform.environment['THEO_TEST_DB_USER'] ?? 'theo_app',
          password: _password!,
          databaseName: _testDatabase,
          // ignore: avoid_redundant_argument_values, as the other DB tests
          secure: true,
          securityContext: testDatabaseSecurityContext(),
        );
        await connection.connect();
        return connection;
      }

      final repo = MySqlAdminPayoutsRepository(connectionFactory: connect);

      Future<int> insert(String sql, Map<String, dynamic> params) async =>
          (await db.execute(sql, params)).lastInsertID.toInt();

      Future<List<Map<String, String?>>> rows(
        String sql, [
        Map<String, dynamic>? params,
      ]) async => (await db.execute(
        sql,
        params,
      )).rows.map((row) => row.textAssoc()).toList();

      Future<int> createUser(String label, String role) async {
        final id = await insert(
          'INSERT INTO `user` (FirebaseUid, Name, PhoneNum, Email, Role, '
          "AccountStatus) VALUES (:uid, :name, '0000000000', :email, :role, "
          "'Active')",
          {
            'uid': 'itest-uid-$tag-$label',
            'name': 'itest $label',
            'email': '$tag-$label@example.test',
            'role': role,
          },
        );
        userIds.add(id);
        return id;
      }

      /// South African calendar date [days] from today, as YYYY-MM-DD.
      String saDate(int days) {
        final sa = DateTime.now().toUtc().add(const Duration(hours: 2));
        return DateTime.utc(sa.year, sa.month, sa.day)
            .add(Duration(days: days))
            .toIso8601String()
            .substring(0, 10);
      }

      /// A paid purchase of [lessons] (label -> (days from today, status))
      /// at R175.00 a lesson with commission [rate] captured.
      Future<void> paidPurchase(
        String rate,
        Map<String, (int, String)> lessons,
      ) async {
        final count = lessons.length;
        final total = '${175 * count}.00';
        final purchaseId = await insert(
          'INSERT INTO bookingpurchase (StudentID, TutorID, SubjectID, '
          'PurchaseType, LessonCount, RatePerLesson, SubtotalAmount, '
          'DiscountPercent, DiscountAmount, TotalAmount, '
          'CommissionPercentage, CommissionSource, PurchaseStatus, '
          'CreatedAtUtc) VALUES (:s, :t, :sub, :type, :n, 175.00, :total, '
          "0, 0, :total, :rate, 'Purchase', 'Paid', UTC_TIMESTAMP(6))",
          {
            's': studentId,
            't': tutorId,
            'sub': subjectId,
            'type': count == 1 ? 'Single' : 'Package',
            'n': count,
            'total': total,
            'rate': rate,
          },
        );
        purchaseIds.add(purchaseId);
        final attemptId = await insert(
          'INSERT INTO paymentattempt (PurchaseID, AttemptNumber, '
          'IdempotencyKey, PaymentMethod, PaymentMode, DemoOutcome, '
          'PaymentStatus, Amount, CreatedAtUtc, UpdatedAtUtc, ResolvedAtUtc) '
          "VALUES (:p, 1, :key, 'CreditDebitCard', 'Demo', "
          "'SimulatedSuccess', 'Successful', :total, UTC_TIMESTAMP(6), "
          'UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))',
          {'p': purchaseId, 'key': '$tag-$purchaseId', 'total': total},
        );
        await insert(
          'INSERT INTO purchasepayment (PurchaseID, PaymentAttemptID, Amount, '
          'CreatedAtUtc) VALUES (:p, :a, :total, UTC_TIMESTAMP(6))',
          {'p': purchaseId, 'a': attemptId, 'total': total},
        );
        var number = 0;
        for (final MapEntry(key: label, value: (days, status))
            in lessons.entries) {
          bookings[label] = await insert(
            'INSERT INTO booking (StudentID, TutorID, SubjectID, PurchaseID, '
            'LessonNumber, LessonPriceAtPurchase, `Date`, StartTime, EndTime, '
            "Status) VALUES (:s, :t, :sub, :p, :n, 175.00, :date, '10:00:00', "
            "'11:00:00', :status)",
            {
              's': studentId,
              't': tutorId,
              'sub': subjectId,
              'p': purchaseId,
              'n': ++number,
              'date': saDate(days),
              'status': status,
            },
          );
        }
      }

      Future<Map<String, String?>?> payoutFor(String label) async {
        final found = await rows(
          'SELECT PayoutID, Status, Amount, CommissionAmount, NetAmount, '
          'AdminID, ApprovedAt, PaidAt, PaidByAdminID, PaymentReference '
          'FROM payout WHERE BookingID = :b',
          {'b': bookings[label]},
        );
        return found.isEmpty ? null : found.single;
      }

      Future<int> payoutId(String label) async =>
          int.parse((await payoutFor(label))!['PayoutID']!);

      setUpAll(() async {
        db = await connect();
        final selected = await rows('SELECT DATABASE() AS db');
        if (selected.single['db'] != _testDatabase) {
          throw StateError('Refusing to run: connected to the wrong database.');
        }
        final migrated = await rows(
          'SELECT COUNT(*) AS n FROM information_schema.COLUMNS '
          'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t '
          "AND COLUMN_NAME = 'PaidByAdminID'",
          {'t': 'payout'},
        );
        if (migrated.single['n'] != '1') {
          throw StateError(
            'Apply migration 013_payout_payment_tracking to $_testDatabase.',
          );
        }
        tag = 'itest${DateTime.now().millisecondsSinceEpoch}';
        final adminUser = await createUser('admin', 'admin');
        admin = AdminIdentity(
          id: await insert(
            "INSERT INTO admin (UserId, RoleKey) VALUES (:u, 'super_admin')",
            {'u': adminUser},
          ),
          name: 'itest admin',
          roleKey: 'super_admin',
        );
        subjectId = await insert(
          'INSERT INTO subjects (subjectName) VALUES (:name)',
          {'name': '$tag-subject'},
        );
        tutorId = await insert(
          'INSERT INTO tutorprofile (Bio, Experience, VerificationStat, '
          "UserID) VALUES ('itest', '1 year', 'Approved', :u)",
          {'u': await createUser('tutor', 'tutor')},
        );
        studentId = await insert(
          'INSERT INTO studentprofile (Address, ProofOfReg, InstitutionYear, '
          'Course, Subject_of_interest, UserID) VALUES '
          "('itest', 'itest', '1', 'itest', 'itest', :u)",
          {'u': await createUser('student', 'student')},
        );
        await paidPurchase('10.00', {
          'finished': (-2, 'Confirmed'),
          'upcoming': (3, 'Confirmed'),
          'cancelled': (4, 'Cancelled'),
          'refunded-later': (-1, 'Confirmed'),
          'finishes-later': (2, 'Confirmed'),
        });
        await paidPurchase('15.00', {'other-rate': (-3, 'Completed')});
        await db.execute(
          'INSERT INTO refund (BookingID, RefundPercentage, RefundAmount, '
          "RefundStatus) VALUES (:b, 50, 87.50, 'Approved')",
          {'b': bookings['cancelled']},
        );
        // For the concurrency and classification tests. The race-* and
        // rollback lessons are upcoming until their test moves them into the
        // past, so earlier generations leave them alone.
        await paidPurchase('10.00', {
          'race-cancel': (6, 'Confirmed'),
          'race-refund': (6, 'Confirmed'),
          'pay-race': (6, 'Confirmed'),
          'rollback': (6, 'Confirmed'),
          'tutor-cancel': (7, 'Confirmed'),
          'no-refund-record': (5, 'Cancelled'),
          'postponed-past': (-2, 'Postponed'),
        });
        // An exception refund awaiting a decision on a lesson that ran.
        await db.execute(
          'INSERT INTO refund (BookingID, RefundPercentage, RefundAmount, '
          "RefundStatus) VALUES (:b, 100, 175.00, 'Pending')",
          {'b': bookings['race-refund']},
        );
      });

      tearDownAll(() async {
        final generated = [
          for (final r in await rows(
            'SELECT PayoutID FROM payoutadminaction '
            "WHERE AdminID = :a AND Action = 'Generated'",
            {'a': admin.id},
          ))
            r['PayoutID']!,
        ];
        final payoutIds = generated.isEmpty ? '0' : generated.join(',');
        final bookingIds = bookings.isEmpty ? '0' : bookings.values.join(',');
        final purchases = purchaseIds.isEmpty ? '0' : purchaseIds.join(',');
        final audits = 'PayoutID IN ($payoutIds) OR AdminID = ${admin.id}';
        final payouts =
            'PayoutID IN ($payoutIds) OR BookingID IN ($bookingIds)';
        final refundActions =
            'RefundID IN (SELECT RefundID FROM refund '
            'WHERE BookingID IN ($bookingIds))';
        for (final sql in [
          'DELETE FROM payoutadminaction WHERE $audits',
          'DELETE FROM payout WHERE $payouts',
          // The real refund repository audits its decisions (deny above).
          'DELETE FROM refundadminaction WHERE $refundActions',
          'DELETE FROM refund WHERE BookingID IN ($bookingIds)',
          'DELETE FROM purchasepayment WHERE PurchaseID IN ($purchases)',
          'DELETE FROM payment WHERE BookingId IN ($bookingIds)',
          'DELETE FROM paymentattempt WHERE PurchaseID IN ($purchases)',
          'DELETE FROM booking WHERE Booking_id IN ($bookingIds)',
          'DELETE FROM bookingpurchase WHERE PurchaseID IN ($purchases)',
          'DELETE FROM tutorprofile WHERE TutorID = $tutorId',
          'DELETE FROM studentprofile WHERE StudentID = $studentId',
          'DELETE FROM admin WHERE AdminID = ${admin.id}',
          'DELETE FROM subjects WHERE subjectId = $subjectId',
          'DELETE FROM `user` WHERE UserId IN (${userIds.join(',')})',
        ]) {
          await db.execute(sql);
        }
        await db.close();
      });

      test('generation creates Pending payouts only for eligible lessons, '
          "each at its purchase's captured rate", () async {
        final generated = await repo.generate(admin);
        expect(generated, greaterThanOrEqualTo(3));

        final finished = (await payoutFor('finished'))!;
        expect(finished['Status'], 'Pending');
        expect(finished['Amount'], '175.00');
        expect(finished['CommissionAmount'], '17.50');
        expect(finished['NetAmount'], '157.50');
        final otherRate = (await payoutFor('other-rate'))!;
        expect(otherRate['CommissionAmount'], '26.25');
        expect(otherRate['NetAmount'], '148.75');
        expect(await payoutFor('refunded-later'), isNotNull);
        expect(await payoutFor('upcoming'), isNull);
        expect(await payoutFor('cancelled'), isNull);
        expect(await payoutFor('finishes-later'), isNull);

        final audit = await rows(
          'SELECT AdminID, Action, NetAmount FROM payoutadminaction '
          'WHERE PayoutID = :id',
          {'id': finished['PayoutID']},
        );
        expect(audit, [
          {
            'AdminID': '${admin.id}',
            'Action': 'Generated',
            'NetAmount': '157.50',
          },
        ]);
      });

      test('generating again adds nothing and changes no amount', () async {
        final before = await payoutFor('finished');
        expect(await repo.generate(admin), 0);
        expect(await payoutFor('finished'), before);
      });

      test('concurrent generation never duplicates a payout', () async {
        // The last lesson becomes finished; two admins generate at once.
        await db.execute(
          'UPDATE booking SET `Date` = :d WHERE Booking_id = :b',
          {'d': saDate(-1), 'b': bookings['finishes-later']},
        );
        final results = await Future.wait([
          for (var i = 0; i < 2; i++)
            repo
                .generate(admin)
                .then<Object>((n) => n, onError: (Object e) => e),
        ]);
        final created = results.whereType<int>().fold<int>(0, (a, b) => a + b);
        expect(created, 1);
        expect(
          results.where((r) => r is! int),
          everyElement(isA<AdminPayoutConflict>()),
        );
        final count = await rows(
          'SELECT COUNT(*) AS n FROM payout WHERE BookingID = :b',
          {'b': bookings['finishes-later']},
        );
        expect(count.single['n'], '1');
      });

      test('Pending -> Approved -> Paid, recorded and audited; no skipping '
          'and no repeating', () async {
        final id = await payoutId('finished');
        await expectLater(
          repo.markPaid(id, admin),
          throwsA(isA<AdminPayoutConflict>()),
        );
        await repo.approve(id, admin);
        await expectLater(
          repo.approve(id, admin),
          throwsA(isA<AdminPayoutConflict>()),
        );
        await repo.markPaid(id, admin, reference: 'EFT-$tag');
        await expectLater(
          repo.markPaid(id, admin, reference: 'EFT-again'),
          throwsA(isA<AdminPayoutConflict>()),
        );

        final paid = (await payoutFor('finished'))!;
        expect(paid['Status'], 'Paid');
        expect(paid['AdminID'], '${admin.id}');
        expect(paid['ApprovedAt'], isNotNull);
        expect(paid['PaidAt'], isNotNull);
        expect(paid['PaidByAdminID'], '${admin.id}');
        expect(paid['PaymentReference'], 'EFT-$tag');
        final audit = await rows(
          'SELECT Action, PaymentReference FROM payoutadminaction '
          'WHERE PayoutID = :id ORDER BY PayoutAdminActionID',
          {'id': id},
        );
        expect(audit.map((r) => (r['Action'], r['PaymentReference'])), [
          ('Generated', null),
          ('Approved', null),
          ('Paid', 'EFT-$tag'),
        ]);
      });

      test('two admins paying at once: exactly one succeeds', () async {
        final id = await payoutId('other-rate');
        await repo.approve(id, admin);
        final results = await Future.wait([
          for (var i = 0; i < 2; i++)
            repo
                .markPaid(id, admin, reference: 'R$i')
                .then<Object>((_) => 'paid', onError: (Object e) => e),
        ]);
        expect(results.where((r) => r == 'paid'), hasLength(1));
        expect(results.whereType<AdminPayoutConflict>(), hasLength(1));
        final paidSteps = await rows(
          'SELECT COUNT(*) AS n FROM payoutadminaction '
          "WHERE PayoutID = :id AND Action = 'Paid'",
          {'id': id},
        );
        expect(paidSteps.single['n'], '1');
      });

      test('a refund approved after the payout is flagged; the payout is '
          'left unchanged', () async {
        final before = await payoutFor('refunded-later');
        await db.execute(
          'INSERT INTO refund (BookingID, RefundPercentage, RefundAmount, '
          "RefundStatus) VALUES (:b, 100, 175.00, 'Approved')",
          {'b': bookings['refunded-later']},
        );
        final listed = await repo.list(const AdminPayoutQuery(pageSize: 100));
        final id = int.parse(before!['PayoutID']!);
        final payout = (listed['payouts']! as List)
            .cast<Map<String, Object?>>()
            .singleWhere((p) => p['payoutId'] == id);
        expect(payout['flagged'], isTrue);
        expect(payout['refund'], {'status': 'approved', 'amount': 175.0});
        final issues = ((listed['finance']! as Map)['issues']! as List)
            .map((i) => (i as Map)['code']);
        expect(issues, contains('refund_after_payout'));
        expect(await payoutFor('refunded-later'), before);
      });

      test('the schema itself refuses a repeated step and a reference on an '
          'unpaid payout', () async {
        final id = await payoutId('finishes-later');
        await expectLater(
          db.execute(
            'INSERT INTO payoutadminaction (PayoutID, AdminID, Action, '
            "NetAmount, CreatedAtUtc) VALUES (:id, :a, 'Generated', 0, "
            'UTC_TIMESTAMP(6))',
            {'id': id, 'a': admin.id},
          ),
          throwsA(
            isA<MySQLServerException>().having(
              (e) => e.errorCode,
              'errorCode',
              1062,
            ),
          ),
        );
        await expectLater(
          db.execute(
            "UPDATE payout SET PaymentReference = 'X' WHERE PayoutID = :id",
            {'id': id},
          ),
          throwsA(
            isA<MySQLServerException>().having(
              (e) => e.errorCode,
              'errorCode',
              3819, // check constraint violated
            ),
          ),
        );
      });

      // ------------------------------------------------ concurrency
      Future<void> moveIntoPast(String label) => db.execute(
        'UPDATE booking SET `Date` = :d WHERE Booking_id = :b',
        {'d': saDate(-1), 'b': bookings[label]},
      );

      /// Runs [action] while [other] holds an open transaction, checks that
      /// it is still waiting after [wait], then commits [other] and returns
      /// the action's outcome (a value or the error).
      Future<Object?> whileHeld(
        MySQLConnection other,
        Future<Object?> Function() action, {
        Duration wait = const Duration(seconds: 2),
      }) async {
        var done = false;
        final outcome = action()
            .then<Object?>((v) => v, onError: (Object e) => e)
            .whenComplete(() => done = true);
        await Future<void>.delayed(wait);
        expect(done, isFalse, reason: 'it should wait for the row lock');
        await other.execute('COMMIT');
        return outcome;
      }

      test('generation waits for an in-flight cancellation and then creates '
          'no payout for it', () async {
        await moveIntoPast('race-cancel');
        final other = await connect();
        try {
          // A cancellation in progress, in the app's lock order: the booking
          // first, then its refund, then the status.
          await other.execute('START TRANSACTION');
          await other.execute(
            'SELECT Booking_id FROM booking WHERE Booking_id = :b FOR UPDATE',
            {'b': bookings['race-cancel']},
          );
          await other.execute(
            'INSERT INTO refund (BookingID, RefundPercentage, RefundAmount, '
            "RefundStatus) VALUES (:b, 100, 175.00, 'Pending')",
            {'b': bookings['race-cancel']},
          );
          await other.execute(
            "UPDATE booking SET Status = 'Cancelled' WHERE Booking_id = :b",
            {'b': bookings['race-cancel']},
          );
          // Generation's snapshot still sees a Confirmed, finished lesson.
          final outcome = await whileHeld(other, () => repo.generate(admin));
          expect(outcome, isA<int>());
        } finally {
          await other.close();
        }
        expect(await payoutFor('race-cancel'), isNull);
      });

      test('a refund decision and generation do not deadlock; generation '
          'uses the decided state', () async {
        await moveIntoPast('race-refund'); // refund still Pending: ineligible
        expect(await repo.generate(admin), 0);
        expect(await payoutFor('race-refund'), isNull);
        final refundId = (await rows(
          'SELECT RefundID FROM refund WHERE BookingID = :b',
          {'b': bookings['race-refund']},
        )).single['RefundID']!;
        // The real refund repository (booking -> refund lock order) and a
        // generation at the same time: both finish, neither deadlocks.
        final refunds = MySqlAdminRefundsRepository(connectionFactory: connect);
        final results = await Future.wait([
          refunds
              .deny(int.parse(refundId), admin, 'The lesson took place.')
              .then<Object?>((_) => 'denied', onError: (Object e) => e),
          repo
              .generate(admin)
              .then<Object?>((n) => n, onError: (Object e) => e),
        ]);
        expect(results.first, 'denied');
        expect(results.last, isA<int>());
        // Once rejected, the refund no longer blocks the payout.
        await repo.generate(admin);
        expect(await payoutFor('race-refund'), isNotNull);
      });

      test('a refund recorded while mark-paid waits blocks the payment',
          () async {
        await moveIntoPast('pay-race');
        await repo.generate(admin);
        final id = await payoutId('pay-race');
        await repo.approve(id, admin);
        final other = await connect();
        try {
          await other.execute('START TRANSACTION');
          await other.execute(
            'SELECT Booking_id FROM booking WHERE Booking_id = :b FOR UPDATE',
            {'b': bookings['pay-race']},
          );
          await other.execute(
            'INSERT INTO refund (BookingID, RefundPercentage, RefundAmount, '
            "RefundStatus) VALUES (:b, 100, 175.00, 'Approved')",
            {'b': bookings['pay-race']},
          );
          final outcome = await whileHeld(
            other,
            () => repo.markPaid(id, admin, reference: 'EFT-race'),
          );
          expect(outcome, isA<AdminPayoutConflict>());
        } finally {
          await other.close();
        }
        final payout = (await payoutFor('pay-race'))!;
        expect(payout['Status'], 'Approved'); // not paid, not reversed
        expect(payout['PaymentReference'], isNull);
      });

      test('an unresolved refund blocks approval and payment; a rejected '
          'refund does not', () async {
        // 'refunded-later' has an Approved refund (added after its payout).
        await expectLater(
          repo.approve(await payoutId('refunded-later'), admin),
          throwsA(isA<AdminPayoutConflict>()),
        );
        // 'finishes-later': Pending blocks, Rejected releases it.
        final id = await payoutId('finishes-later');
        await db.execute(
          'INSERT INTO refund (BookingID, RefundPercentage, RefundAmount, '
          "RefundStatus) VALUES (:b, 100, 175.00, 'Pending')",
          {'b': bookings['finishes-later']},
        );
        await expectLater(
          repo.approve(id, admin),
          throwsA(isA<AdminPayoutConflict>()),
        );
        await db.execute(
          "UPDATE refund SET RefundStatus = 'Rejected', RefundAmount = NULL "
          'WHERE BookingID = :b',
          {'b': bookings['finishes-later']},
        );
        await repo.approve(id, admin);
        await repo.markPaid(id, admin);
        expect((await payoutFor('finishes-later'))!['Status'], 'Paid');
      });

      test('a failed generation rolls back completely and releases the lock',
          () async {
        await moveIntoPast('rollback');
        // No admin 0 exists: the audit insert fails after the payout insert.
        const ghost = AdminIdentity(id: 0, name: 'x', roleKey: 'super_admin');
        await expectLater(
          repo.generate(ghost),
          throwsA(isA<MySQLServerException>()),
        );
        expect(await payoutFor('rollback'), isNull);
        final free = await rows(
          'SELECT IS_FREE_LOCK(:name) AS free',
          {'name': payoutGenerationLock},
        );
        expect(free.single['free'], '1');
        // The next run succeeds.
        await repo.generate(admin);
        expect(await payoutFor('rollback'), isNotNull);
      });

      // ------------------------------------------------ classification
      Future<Map<String, Object?>> finance() async =>
          (await repo.list(const AdminPayoutQuery()))['finance']!
              as Map<String, Object?>;

      List<Object?> codes(Map<String, Object?> f) =>
          [for (final i in f['issues']! as List) (i as Map)['code']];

      test('a cancelled paid lesson without a refund record and a lesson '
          'still Postponed after its end are flagged, never paid out',
          () async {
        final f = await finance();
        expect(
          codes(f),
          containsAll([
            'cancelled_without_refund_record',
            'postponed_past_end',
          ]),
        );
        await repo.generate(admin);
        expect(await payoutFor('no-refund-record'), isNull);
        expect(await payoutFor('postponed-past'), isNull);
      });

      test('a tutor-initiated cancellation records a full Pending refund',
          () async {
        final before = parseCents(
          (await finance())['awaitingRefundDecision']! as String,
        )!;
        await tutorCancelBooking(
          db,
          tutorId,
          bookings['tutor-cancel']!,
          TutorCancelKind.cancel,
        );
        final refund = (await rows(
          'SELECT RefundPercentage, RefundAmount, RefundStatus FROM refund '
          'WHERE BookingID = :b',
          {'b': bookings['tutor-cancel']},
        )).single;
        expect(refund['RefundPercentage'], '100.00');
        expect(refund['RefundAmount'], '175.00');
        expect(refund['RefundStatus'], 'Pending');
        final after = parseCents(
          (await finance())['awaitingRefundDecision']! as String,
        )!;
        expect(after - before, 17500);
      });

      test('a legacy payment linked to a purchase settlement is not counted '
          'twice', () async {
        final legacyBooking = await insert(
          'INSERT INTO booking (StudentID, TutorID, SubjectID, `Date`, '
          "StartTime, EndTime, Status) VALUES (:s, :t, :sub, :d, '10:00:00', "
          "'11:00:00', 'Confirmed')",
          {
            's': studentId,
            't': tutorId,
            'sub': subjectId,
            'd': saDate(9),
          },
        );
        bookings['legacy'] = legacyBooking;
        final paymentId = await insert(
          'INSERT INTO payment (BookingId, PaymentMethod, PaymentStatus, '
          "Paid_At, Amount) VALUES (:b, 'Card', 'Successful', NOW(), 200.00)",
          {'b': legacyBooking},
        );
        final counted = parseCents(
          (await finance())['moneyReceived']! as String,
        )!;
        // Link it to one of this run's settlements: it is now part of that
        // purchase's money and must drop out of the legacy total.
        await db.execute(
          'UPDATE purchasepayment SET PaymentID = :p WHERE PurchaseID = :pid',
          {'p': paymentId, 'pid': purchaseIds.first},
        );
        final linked = parseCents(
          (await finance())['moneyReceived']! as String,
        )!;
        expect(counted - linked, 20000);
        await db.execute(
          'UPDATE purchasepayment SET PaymentID = NULL WHERE PurchaseID = :pid',
          {'pid': purchaseIds.first},
        );
      });
    },
    skip: _password == null
        ? 'Set THEO_TEST_DB_PASSWORD to run against theotutoring_test'
        : false,
  );
}
