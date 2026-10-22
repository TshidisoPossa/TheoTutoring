// Database-backed booking flow test. It only ever connects to the isolated
// `theotutoring_test` database and only runs when THEO_TEST_DB_PASSWORD is set.
// Firebase is mocked through the routes' existing student-id resolver seam;
// ownership checks and the repository SQL are the real production code.
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_availability.dart';
import 'package:theo_tutoring_backend/booking_purchase_repository.dart';
import 'package:theo_tutoring_backend/demo_payment_config.dart';
import 'package:theo_tutoring_backend/env.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/tutor_bookings.dart';
import 'package:theo_tutoring_backend/tutorlanding_session.dart';

import '../../routes/TutorLandingpage/LandingPageScreen.dart' as dashboard;
import '../../routes/StudentlandingPage/availability.dart' as availability;
import '../../routes/StudentlandingPage/booking-purchases/[purchaseId]/payment-attempts.dart'
    as payments;
import '../../routes/StudentlandingPage/booking-purchases/index.dart' as purchases;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

const _testDatabase = 'theotutoring_test';
final _password = Platform.environment['THEO_TEST_DB_PASSWORD'];

typedef _Reply = ({int status, Map<String, dynamic> body});

void main() {
  group(
    'booking flow against $_testDatabase',
    () {
      late MySQLConnection admin;
      late String tag;
      late String lessonDate;
      late String rate;
      late int studentA;
      late int studentB;
      late int tutorA;
      late int tutorB;
      late int subjectId;
      final userIds = <int>[];
      final subjectIds = <int>[];
      final tutorIds = <int>[];
      final studentIds = <int>[];
      final enabled = DemoPaymentConfig.fromSources(
        processEnvironment: const {'APP_ENV': 'test'},
        enabledValue: 'true',
      );

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

      Future<List<Map<String, String?>>> rows(
        String sql, [
        Map<String, dynamic>? params,
      ]) async => (await admin.execute(
        sql,
        params,
      )).rows.map((row) => row.assoc()).toList();

      Future<int> insert(String sql, Map<String, dynamic> params) async =>
          (await admin.execute(sql, params)).lastInsertID.toInt();

      Future<int> createUser(String label, String role) async {
        final id = await insert(
          'INSERT INTO `User` (FirebaseUid, Name, PhoneNum, Email, Role, '
          'AccountStatus) VALUES (:uid, :name, :phone, :email, :role, '
          "'Active')",
          {
            'uid': 'itest-uid-$tag-$label',
            'name': 'itest $label',
            'phone': '0000000000',
            'email': '$tag-$label@example.test',
            'role': role,
          },
        );
        userIds.add(id);
        return id;
      }

      Future<int> createStudent(String label) async {
        final userId = await createUser(label, 'student');
        final id = await insert(
          'INSERT INTO StudentProfile (Address, ProofOfReg, InstitutionYear, '
          'Course, Subject_of_interest, UserID) VALUES '
          "('itest', 'itest', '1', 'itest', 'itest', :userId)",
          {'userId': userId},
        );
        studentIds.add(id);
        return id;
      }

      Future<int> createTutor(String label) async {
        final userId = await createUser(label, 'tutor');
        final id = await insert(
          'INSERT INTO TutorProfile (Bio, Experience, VerificationStat, '
          "UserID) VALUES ('itest', '1 year', 'Approved', :userId)",
          {'userId': userId},
        );
        tutorIds.add(id);
        await admin.execute(
          'INSERT INTO TutorApplication (TutorID, Status) '
          "VALUES (:id, 'Approved')",
          {'id': id},
        );
        await admin.execute(
          'INSERT INTO TutorSubjects (TutorID, SubjectID) VALUES (:t, :s)',
          {'t': id, 's': subjectId},
        );
        await admin.execute(
          'INSERT INTO TutAvailability (TutorID, Day, StartTime, end_Time) '
          "VALUES (:t, :day, '08:00:00', '20:00:00')",
          {'t': id, 'day': _dayName(lessonDate)},
        );
        return id;
      }

      Future<int> resolver(String? authorization) async {
        switch (authorization) {
          case 'Bearer test-student-a':
            return studentA;
          case 'Bearer test-student-b':
            return studentB;
        }
        throw const AuthTokenException('Invalid token');
      }

      final purchaseRepository = MySqlBookingPurchaseRepository(
        connectionFactory: connect,
      );

      Future<_Reply> send(
        Future<Response> Function(RequestContext) handler, {
        HttpMethod method = HttpMethod.post,
        Object? json,
        Uri? uri,
        String token = 'Bearer test-student-a',
      }) async {
        final context = _MockRequestContext();
        final request = _MockRequest();
        when(() => context.request).thenReturn(request);
        when(() => request.method).thenReturn(method);
        when(() => request.uri).thenReturn(uri ?? Uri.parse('/'));
        when(() => request.headers).thenReturn({'Authorization': token});
        when(request.json).thenAnswer((_) async => json);
        final response = await handler(context);
        return (
          status: response.statusCode,
          body: jsonDecode(await response.body()) as Map<String, dynamic>,
        );
      }

      Future<_Reply> slots({String token = 'Bearer test-student-a'}) => send(
        (c) => availability.handleAvailability(
          c,
          repositoryFactory: () async =>
              MySqlBookingAvailabilityRepository(admin),
          studentIdResolver: resolver,
        ),
        method: HttpMethod.get,
        token: token,
        uri: Uri.parse(
          '/StudentlandingPage/availability?tutorId=$tutorA&subjectId=$subjectId'
          '&from=$lessonDate&through=$lessonDate',
        ),
      );

      bool hasSlot(_Reply reply, String start) => (reply.body['slots'] as List)
          .any((s) => s['date'] == lessonDate && s['startTime'] == start);

      Future<_Reply> purchase(
        String start,
        String end,
        String key, {
        String token = 'Bearer test-student-a',
      }) => send(
        (c) => purchases.handleCreateBookingPurchase(
          c,
          repositoryFactory: () async => purchaseRepository,
          studentIdResolver: resolver,
        ),
        token: token,
        json: {
          'tutorId': tutorA,
          'subjectId': subjectId,
          'purchaseType': 'Single',
          'schedulingMode': 'manual',
          'idempotencyKey': key,
          'lessons': [
            {'date': lessonDate, 'startTime': start, 'endTime': end},
          ],
        },
      );

      Future<_Reply> pay(
        Object purchaseId,
        String key,
        String outcome, {
        String token = 'Bearer test-student-a',
      }) => send(
        (c) => payments.handleCreatePaymentAttempt(
          c,
          routePurchaseId: '$purchaseId',
          repositoryFactory: () async => purchaseRepository,
          studentIdResolver: resolver,
          paymentConfig: enabled,
        ),
        token: token,
        json: {
          'idempotencyKey': key,
          'paymentMethod': 'CreditDebitCard',
          'simulatedOutcome': outcome,
        },
      );

      Future<Map<String, String?>> state(Object purchaseId) async {
        final result = await rows(
          'SELECT p.PurchaseStatus, b.Status AS BookingStatus, h.HoldStatus, '
          'b.StudentID, b.TutorID, '
          '(SELECT COUNT(*) FROM PaymentAttempt '
          'WHERE PurchaseID = p.PurchaseID) AS Attempts, '
          '(SELECT COUNT(*) FROM PurchasePayment '
          'WHERE PurchaseID = p.PurchaseID) AS Settlements '
          'FROM BookingPurchase p '
          'JOIN Booking b ON b.PurchaseID = p.PurchaseID '
          'JOIN BookingSlotHold h ON h.PurchaseID = p.PurchaseID '
          'WHERE p.PurchaseID = :id',
          {'id': purchaseId},
        );
        return result.single;
      }

      setUpAll(() async {
        admin = await connect();
        final selected = await rows('SELECT DATABASE() AS db');
        if (selected.single['db'] != _testDatabase) {
          throw StateError('Refusing to run: connected to the wrong database.');
        }
        final settings = await rows(
          'SELECT TutoringRate FROM PlatformSettings WHERE SettingsID = 1',
        );
        rate = settings.single['TutoringRate']!;

        tag = 'itest${DateTime.now().millisecondsSinceEpoch}';
        final johannesburg = DateTime.now().toUtc().add(
          const Duration(hours: 2),
        );
        final date = DateTime.utc(
          johannesburg.year,
          johannesburg.month,
          johannesburg.day,
        ).add(const Duration(days: 5));
        lessonDate = date.toIso8601String().substring(0, 10);

        subjectId = await insert(
          'INSERT INTO Subjects (subjectName) VALUES (:name)',
          {'name': '$tag-subject'},
        );
        subjectIds.add(subjectId);
        studentA = await createStudent('student-a');
        studentB = await createStudent('student-b');
        tutorA = await createTutor('tutor-a');
        tutorB = await createTutor('tutor-b');
      });

      tearDownAll(() async {
        // Removes only the rows created by this run, children first.
        String ids(List<int> values) => values.isEmpty ? '0' : values.join(',');
        final owners =
            'StudentID IN (${ids(studentIds)}) OR TutorID IN (${ids(tutorIds)})';
        final purchaseFilter =
            'SELECT PurchaseID FROM BookingPurchase WHERE $owners';
        for (final sql in [
          'DELETE FROM PurchasePayment WHERE PurchaseID IN ($purchaseFilter)',
          'DELETE FROM PaymentAttempt WHERE PurchaseID IN ($purchaseFilter)',
          'DELETE FROM BookingSlotHold WHERE PurchaseID IN ($purchaseFilter)',
          'DELETE FROM Booking WHERE $owners',
          'DELETE FROM BookingPurchase WHERE $owners',
          'DELETE FROM TutAvailability WHERE TutorID IN (${ids(tutorIds)})',
          'DELETE FROM TutorSubjects WHERE TutorID IN (${ids(tutorIds)})',
          'DELETE FROM TutorApplication WHERE TutorID IN (${ids(tutorIds)})',
          'DELETE FROM TutorProfile WHERE TutorID IN (${ids(tutorIds)})',
          'DELETE FROM StudentProfile WHERE StudentID IN (${ids(studentIds)})',
          'DELETE FROM `User` WHERE UserId IN (${ids(userIds)})',
          'DELETE FROM Subjects WHERE subjectId IN (${ids(subjectIds)})',
        ]) {
          await admin.execute(sql);
        }
        await admin.close();
      });

      late int singleId;
      late int expiringId;
      late int concurrentPayId;

      test('rejects unauthenticated requests on every booking route', () async {
        const bad = 'Bearer nope';
        expect((await slots(token: bad)).status, 401);
        expect(
          (await purchase('10:00', '11:00', '$tag-x', token: bad)).status,
          401,
        );
        expect((await pay(1, '$tag-x', 'success', token: bad)).status, 401);
      });

      test('availability offers the free slot at the platform rate', () async {
        final reply = await slots();
        expect(reply.status, 200);
        expect(reply.body['hourlyRate'], rate);
        expect(hasSlot(reply, '10:00'), isTrue);
      });

      test(
        'purchase creates Held purchase, Pending booking, Active hold',
        () async {
          final reply = await purchase('10:00', '11:00', '$tag-p1');
          expect(reply.status, 201);
          expect(reply.body['purchaseStatus'], 'Held');
          expect(reply.body['totalAmount'], rate);
          singleId = reply.body['purchaseId'] as int;
          final db = await state(singleId);
          expect(db['PurchaseStatus'], 'Held');
          expect(db['BookingStatus'], 'Pending');
          expect(db['HoldStatus'], 'Active');
          expect(db['StudentID'], '$studentA');
          expect(db['TutorID'], '$tutorA');
          expect(db['Attempts'], '0');
        },
      );

      test('the held slot disappears from availability', () async {
        final reply = await slots(token: 'Bearer test-student-b');
        expect(hasSlot(reply, '10:00'), isFalse);
      });

      test(
        'same key replays; changed payload under the same key conflicts',
        () async {
          final replay = await purchase('10:00', '11:00', '$tag-p1');
          expect(replay.status, 200);
          expect(replay.body['purchaseId'], singleId);
          expect((await purchase('11:00', '12:00', '$tag-p1')).status, 409);
          final count = await rows(
            'SELECT COUNT(*) AS n FROM BookingPurchase WHERE StudentID = :s',
            {'s': studentA},
          );
          expect(count.single['n'], '1');
        },
      );

      test('another student cannot book the held slot', () async {
        final reply = await purchase(
          '10:00',
          '11:00',
          '$tag-b1',
          token: 'Bearer test-student-b',
        );
        expect(reply.status, 409);
      });

      test(
        'concurrent submissions with one key create a single purchase',
        () async {
          final replies = await Future.wait([
            purchase('14:00', '15:00', '$tag-c1'),
            purchase('14:00', '15:00', '$tag-c1'),
          ]);
          expect(replies.map((r) => r.status).toSet(), {200, 201});
          expect(replies[0].body['purchaseId'], replies[1].body['purchaseId']);
          concurrentPayId = replies[0].body['purchaseId'] as int;
        },
      );

      test("another student cannot pay someone else's purchase", () async {
        final reply = await pay(
          singleId,
          '$tag-pay-b',
          'success',
          token: 'Bearer test-student-b',
        );
        expect(reply.status, 404);
        expect((await state(singleId))['PurchaseStatus'], 'Held');
      });

      test(
        'failed demo payment leaves purchase Held and booking Pending',
        () async {
          final reply = await pay(singleId, '$tag-pay-1', 'failure');
          expect(reply.status, 201);
          expect(reply.body['paymentStatus'], 'Failed');
          expect(reply.body['settled'], isFalse);
          final db = await state(singleId);
          expect(db['PurchaseStatus'], 'Held');
          expect(db['BookingStatus'], 'Pending');
          expect(db['HoldStatus'], 'Active');
          expect(db['Settlements'], '0');
        },
      );

      test(
        'retry with a new key confirms booking, hold and purchase',
        () async {
          final reply = await pay(singleId, '$tag-pay-2', 'success');
          expect(reply.status, 201);
          expect(reply.body['paymentStatus'], 'Successful');
          expect(reply.body['purchaseStatus'], 'Paid');
          final db = await state(singleId);
          expect(db['PurchaseStatus'], 'Paid');
          expect(db['BookingStatus'], 'Confirmed');
          expect(db['HoldStatus'], 'Consumed');
          expect(db['Attempts'], '2');
          expect(db['Settlements'], '1');
        },
      );

      test('replaying the successful key does not double charge', () async {
        final replay = await pay(singleId, '$tag-pay-2', 'success');
        expect(replay.status, 200);
        expect(replay.body['replayed'], isTrue);
        final db = await state(singleId);
        expect(db['Attempts'], '2');
        expect(db['Settlements'], '1');
        expect((await pay(singleId, '$tag-pay-3', 'success')).status, 409);
      });

      test('concurrent payments with one key settle exactly once', () async {
        final replies = await Future.wait([
          pay(concurrentPayId, '$tag-cpay', 'success'),
          pay(concurrentPayId, '$tag-cpay', 'success'),
        ]);
        expect(replies.map((r) => r.status).toSet(), {200, 201});
        final db = await state(concurrentPayId);
        expect(db['Attempts'], '1');
        expect(db['Settlements'], '1');
        expect(db['PurchaseStatus'], 'Paid');
        expect(db['BookingStatus'], 'Confirmed');
      });

      test('an expired hold cannot be paid and releases the slot', () async {
        final created = await purchase('12:00', '13:00', '$tag-e1');
        expect(created.status, 201);
        expiringId = created.body['purchaseId'] as int;
        await admin.execute(
          'UPDATE BookingSlotHold SET ExpiresAtUtc = '
          'DATE_SUB(UTC_TIMESTAMP(6), INTERVAL 1 MINUTE) '
          'WHERE PurchaseID = :id',
          {'id': expiringId},
        );
        final reply = await pay(expiringId, '$tag-epay', 'success');
        expect(reply.status, 409);
        expect(reply.body['code'], 'hold_expired');
        final db = await state(expiringId);
        expect(db['PurchaseStatus'], 'Expired');
        expect(db['BookingStatus'], 'Cancelled');
        expect(db['HoldStatus'], 'Expired');
        expect(db['Settlements'], '0');
        expect(hasSlot(await slots(), '12:00'), isTrue);
      });

      test(
        'paid booking belongs to its own tutor only, as Confirmed',
        () async {
          final booking = await rows(
            'SELECT TutorID, Status FROM Booking WHERE PurchaseID = :id',
            {'id': singleId},
          );
          expect(booking.single['TutorID'], '$tutorA');
          expect(booking.single['Status'], 'Confirmed');
          final other = await rows(
            'SELECT COUNT(*) AS n FROM Booking '
            "WHERE TutorID = :t AND Status = 'Confirmed'",
            {'t': tutorB},
          );
          expect(other.single['n'], '0');
        },
      );

      test(
        'tutor bookings list shows paid bookings to the owning tutor only',
        () async {
          // An unpaid hold and a legacy Pending request, both for tutor A.
          final held = await purchase('18:00', '19:00', '$tag-held');
          expect(held.status, 201);
          final legacyId = await insert(
            'INSERT INTO Booking (StudentID, TutorID, SubjectID, `Date`, '
            'StartTime, EndTime, Note, Status) VALUES (:s, :t, :sub, '
            ":d, '16:00:00', '17:00:00', 'legacy request', 'Pending')",
            {'s': studentA, 't': tutorA, 'sub': subjectId, 'd': lessonDate},
          );

          final repository = MySqlTutorBookingsRepository(admin);
          final forA = await repository.listForTutor(tutorA);
          final byStatus = {for (final b in forA) b.bookingId: b};

          final paid = await rows(
            'SELECT Booking_id FROM Booking WHERE PurchaseID IN (:p1, :p2)',
            {'p1': singleId, 'p2': concurrentPayId},
          );
          for (final row in paid) {
            final booking = byStatus[int.parse(row['Booking_id']!)];
            expect(booking, isNotNull);
            expect(booking!.status, 'Confirmed');
            expect(booking.studentName, 'itest student-a');
            expect(booking.subject, '$tag-subject');
          }
          expect(byStatus[legacyId]?.status, 'Pending');
          expect(byStatus[legacyId]?.purchaseId, isNull);
          // Held (unpaid) and expired purchase bookings stay hidden.
          expect(
            forA.where(
              (b) => b.purchaseId != null && b.status != 'Confirmed',
            ),
            isEmpty,
          );
          expect(forA.length, paid.length + 1);

          final onlyConfirmed = await repository.listForTutor(
            tutorA,
            status: 'Confirmed',
          );
          expect(onlyConfirmed.every((b) => b.status == 'Confirmed'), isTrue);
          expect(onlyConfirmed.length, paid.length);
          expect(
            await repository.listForTutor(tutorA, status: 'Rejected'),
            isEmpty,
          );

          // Cross-tutor denial: tutor B sees nothing of tutor A's bookings.
          expect(await repository.listForTutor(tutorB), isEmpty);

          // Keep the dashboard assertions below independent of this request.
          await admin.execute(
            'DELETE FROM Booking WHERE Booking_id = :id',
            {'id': legacyId},
          );
        },
      );

      test(
        'tutor dashboard counts the paid booking for the right tutor',
        () async {
          Future<Map<String, dynamic>> asTutor(int tutorId) async {
            final context = _MockRequestContext();
            final request = _MockRequest();
            when(() => context.request).thenReturn(request);
            when(() => request.method).thenReturn(HttpMethod.get);
            when(context.read<TutorSession>).thenReturn(
              TutorSession('uid', tutorId, accountStatus: 'Active'),
            );
            final response = await dashboard.onRequest(context);
            expect(response.statusCode, 200);
            return jsonDecode(await response.body()) as Map<String, dynamic>;
          }

          final a = await asTutor(tutorA);
          expect(a['activeStudents'], 1);
          expect(a['newRequests'], 0);
          expect(a['recentRequests'], isEmpty);
          final b = await asTutor(tutorB);
          expect(b['activeStudents'], 0);
        },
        skip: env['DB_NAME'] == _testDatabase
            ? false
            : 'The dashboard route uses the .env database; run from a '
                  'working copy whose .env targets $_testDatabase.',
      );
    },
    skip: _password == null
        ? 'Set THEO_TEST_DB_PASSWORD to run database-backed tests.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _dayName(String isoDate) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[DateTime.parse('${isoDate}T00:00:00Z').weekday - 1];
}
