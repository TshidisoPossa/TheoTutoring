import 'dart:io';

import 'package:mysql_client/mysql_client.dart';
import 'package:mysql_client/exception.dart';

import 'booking_domain.dart';
import 'booking_purchase.dart';
import 'database.dart';

typedef BookingPurchaseConnectionFactory = Future<MySQLConnection> Function();

class MySqlBookingPurchaseRepository implements BookingPurchaseRepository {
  MySqlBookingPurchaseRepository({
    BookingPurchaseConnectionFactory? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final BookingPurchaseConnectionFactory _connectionFactory;

  @override
  Future<BookingPurchaseReceipt> create(
    int studentId,
    CreateBookingPurchaseCommand command,
  ) async {
    MySQLConnection? connection;
    try {
      connection = await _connectionFactory();
      await connection.execute(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ',
      );
      return await connection.transactional(
        (transaction) => _createInTransaction(
          transaction,
          studentId,
          command,
        ),
      );
    } on BookingPurchaseConflict {
      rethrow;
    } on BookingPurchaseNotFound {
      rethrow;
    } on BookingPurchaseUnavailable {
      rethrow;
    } on BookingPurchaseServiceUnavailable {
      rethrow;
    } on MySQLServerException {
      throw const BookingPurchaseServiceUnavailable();
    } on MySQLClientException {
      throw const BookingPurchaseServiceUnavailable();
    } on FormatException {
      throw const BookingPurchaseServiceUnavailable();
    } catch (error) {
      stderr.writeln(
        'Booking purchase transaction failed (${error.runtimeType}).',
      );
      throw const BookingPurchaseServiceUnavailable();
    } finally {
      if (connection?.connected ?? false) {
        await connection!.close();
      }
    }
  }

  @override
  Future<PaymentAttemptReceipt> createPaymentAttempt(
    int studentId,
    int purchaseId,
    CreatePaymentAttemptCommand command,
  ) async {
    MySQLConnection? connection;
    try {
      connection = await _connectionFactory();
      await connection.execute(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ',
      );
      final outcome = await connection.transactional(
        (transaction) => _createPaymentAttemptInTransaction(
          transaction,
          studentId,
          purchaseId,
          command,
        ),
      );
      if (outcome.conflict != null) throw outcome.conflict!;
      return outcome.receipt!;
    } on BookingPurchaseConflict {
      rethrow;
    } on BookingPurchaseNotFound {
      rethrow;
    } on BookingPurchaseServiceUnavailable {
      rethrow;
    } on MySQLServerException {
      throw const BookingPurchaseServiceUnavailable();
    } on MySQLClientException {
      throw const BookingPurchaseServiceUnavailable();
    } on FormatException {
      throw const BookingPurchaseServiceUnavailable();
    } catch (error) {
      stderr.writeln(
        'Payment attempt transaction failed (${error.runtimeType}).',
      );
      throw const BookingPurchaseServiceUnavailable();
    } finally {
      if (connection?.connected ?? false) {
        await connection!.close();
      }
    }
  }

  Future<_PaymentTransactionOutcome> _createPaymentAttemptInTransaction(
    MySQLConnection connection,
    int studentId,
    int purchaseId,
    CreatePaymentAttemptCommand command,
  ) async {
    final discovery = await connection.execute(
      '''
      SELECT TutorID
      FROM BookingPurchase
      WHERE PurchaseID = :purchaseId AND StudentID = :studentId
      ''',
      {'purchaseId': purchaseId, 'studentId': studentId},
    );
    if (discovery.rows.isEmpty) throw const BookingPurchaseNotFound();
    final tutorId = _int(discovery.rows.first.colByName('TutorID'));

    final student = await connection.execute(
      '''
      SELECT sp.StudentID
      FROM StudentProfile sp
      INNER JOIN \`User\` u ON u.UserId = sp.UserID
      WHERE sp.StudentID = :studentId
        AND u.Role = 'student'
        AND u.AccountStatus = 'Active'
      FOR UPDATE
      ''',
      {'studentId': studentId},
    );
    if (student.rows.isEmpty) throw const BookingPurchaseNotFound();

    final tutor = await connection.execute(
      'SELECT TutorID FROM TutorProfile WHERE TutorID = :tutorId FOR UPDATE',
      {'tutorId': tutorId},
    );
    if (tutor.rows.isEmpty) throw const BookingPurchaseNotFound();

    final purchaseResult = await connection.execute(
      '''
      SELECT PurchaseStatus, LessonCount, TotalAmount, StudentID, TutorID
      FROM BookingPurchase
      WHERE PurchaseID = :purchaseId
      FOR UPDATE
      ''',
      {'purchaseId': purchaseId},
    );
    if (purchaseResult.rows.isEmpty) throw const BookingPurchaseNotFound();
    final purchase = purchaseResult.rows.first;
    if (_int(purchase.colByName('StudentID')) != studentId ||
        _int(purchase.colByName('TutorID')) != tutorId) {
      throw const BookingPurchaseNotFound();
    }
    final purchaseStatus = _string(purchase.colByName('PurchaseStatus'));
    final lessonCount = _int(purchase.colByName('LessonCount'));
    final amount = _string(purchase.colByName('TotalAmount'));

    final bookings = await connection.execute(
      '''
      SELECT Booking_id, LessonNumber, Status
      FROM Booking
      WHERE PurchaseID = :purchaseId
      ORDER BY Booking_id
      FOR UPDATE
      ''',
      {'purchaseId': purchaseId},
    );
    final holds = await connection.execute(
      '''
      SELECT HoldID, LessonNumber, BookingID, HoldStatus, ExpiresAtUtc
      FROM BookingSlotHold
      WHERE PurchaseID = :purchaseId
      ORDER BY HoldID
      FOR UPDATE
      ''',
      {'purchaseId': purchaseId},
    );
    final attempts = await connection.execute(
      '''
      SELECT PaymentAttemptID, AttemptNumber, IdempotencyKey, PaymentMethod,
             DemoOutcome, PaymentStatus
      FROM PaymentAttempt
      WHERE PurchaseID = :purchaseId
      ORDER BY PaymentAttemptID
      FOR UPDATE
      ''',
      {'purchaseId': purchaseId},
    );
    final settlements = await connection.execute(
      '''
      SELECT PurchasePaymentID, PaymentAttemptID
      FROM PurchasePayment
      WHERE PurchaseID = :purchaseId
      ORDER BY PurchasePaymentID
      FOR UPDATE
      ''',
      {'purchaseId': purchaseId},
    );

    final expectedOutcome = command.simulatedOutcome == 'success'
        ? 'SimulatedSuccess'
        : 'SimulatedFailure';
    for (final attempt in attempts.rows) {
      if (_string(attempt.colByName('IdempotencyKey')) ==
          command.idempotencyKey) {
        if (_string(attempt.colByName('PaymentMethod')) !=
                command.paymentMethod ||
            _string(attempt.colByName('DemoOutcome')) != expectedOutcome) {
          throw const BookingPurchaseConflict(
            'idempotency_key_reused',
            'The idempotency key was already used for a different request.',
          );
        }
        final attemptId = _int(attempt.colByName('PaymentAttemptID'));
        final settled = settlements.rows.any(
          (row) => _int(row.colByName('PaymentAttemptID')) == attemptId,
        );
        if (purchaseStatus == 'Held' &&
            _string(attempt.colByName('PaymentStatus')) == 'Failed') {
          final nowResult = await connection.execute(
            'SELECT UTC_TIMESTAMP(6) AS NowUtc',
          );
          final replayNowUtc = _utcDateTime(
            nowResult.rows.first.colByName('NowUtc'),
          );
          var allHoldsValid =
              bookings.rows.length == lessonCount &&
              holds.rows.length == lessonCount;
          var holdExpired = false;
          final replayBookings = <int, Map<String, Object?>>{};
          for (final booking in bookings.rows) {
            final number = _int(booking.colByName('LessonNumber'));
            if (replayBookings.containsKey(number)) {
              allHoldsValid = false;
              continue;
            }
            replayBookings[number] = {
              'id': _int(booking.colByName('Booking_id')),
              'status': _string(booking.colByName('Status')),
            };
            if (_string(booking.colByName('Status')) != 'Pending') {
              allHoldsValid = false;
            }
          }
          for (final hold in holds.rows) {
            final number = _int(hold.colByName('LessonNumber'));
            final booking = replayBookings[number];
            final bookingId = hold.colByName('BookingID');
            if (booking == null ||
                bookingId == null ||
                _int(bookingId) != booking['id']) {
              allHoldsValid = false;
            }
            final holdIsActive =
                _string(hold.colByName('HoldStatus')) == 'Active';
            final holdIsUnexpired = _utcDateTime(
              hold.colByName('ExpiresAtUtc'),
            ).isAfter(replayNowUtc);
            if (!holdIsActive || !holdIsUnexpired) {
              allHoldsValid = false;
              if (!holdIsUnexpired) holdExpired = true;
            }
          }
          for (var number = 1; number <= lessonCount; number++) {
            if (!replayBookings.containsKey(number)) allHoldsValid = false;
          }
          if (!allHoldsValid) {
            await _expirePaymentPurchase(
              connection,
              purchaseId: purchaseId,
              nowUtc: replayNowUtc,
            );
            return _PaymentTransactionOutcome.conflict(
              BookingPurchaseConflict(
                holdExpired ? 'hold_expired' : 'incomplete_hold_set',
                holdExpired
                    ? 'One or more lesson holds have expired.'
                    : 'The purchase does not have all required lesson holds.',
              ),
            );
          }
        }
        return _PaymentTransactionOutcome.receipt(
          PaymentAttemptReceipt(
            paymentAttemptId: attemptId,
            attemptNumber: _int(attempt.colByName('AttemptNumber')),
            paymentStatus: _string(attempt.colByName('PaymentStatus')),
            purchaseStatus: purchaseStatus,
            replayed: true,
            settled: settled,
          ),
        );
      }
    }

    if (purchaseStatus != 'Held') {
      throw const BookingPurchaseConflict(
        'purchase_not_payable',
        'This purchase is no longer available for payment.',
      );
    }
    if (settlements.rows.isNotEmpty) {
      throw const BookingPurchaseConflict(
        'purchase_already_settled',
        'This purchase already has a settlement.',
      );
    }
    if (attempts.rows.any(
      (row) => _string(row.colByName('PaymentStatus')) != 'Failed',
    )) {
      throw const BookingPurchaseConflict(
        'payment_attempt_unresolved',
        'The previous payment attempt must be resolved before retrying.',
      );
    }

    final nowResult = await connection.execute(
      'SELECT UTC_TIMESTAMP(6) AS NowUtc',
    );
    final nowUtc = _utcDateTime(nowResult.rows.first.colByName('NowUtc'));
    var completeHoldSet =
        bookings.rows.length == lessonCount && holds.rows.length == lessonCount;
    var holdExpired = false;
    final bookingByLesson = <int, Map<String, dynamic>>{};
    for (final booking in bookings.rows) {
      final number = _int(booking.colByName('LessonNumber'));
      if (bookingByLesson.containsKey(number)) {
        completeHoldSet = false;
        continue;
      }
      bookingByLesson[number] = {
        'id': _int(booking.colByName('Booking_id')),
        'status': _string(booking.colByName('Status')),
      };
      if (_string(booking.colByName('Status')) != 'Pending') {
        completeHoldSet = false;
      }
    }

    final holdsByLesson = <int, Map<String, Object?>>{};
    for (final hold in holds.rows) {
      final number = _int(hold.colByName('LessonNumber'));
      if (holdsByLesson.containsKey(number)) {
        completeHoldSet = false;
        continue;
      }
      final booking = bookingByLesson[number];
      final expiresAtUtc = _utcDateTime(hold.colByName('ExpiresAtUtc'));
      final status = _string(hold.colByName('HoldStatus'));
      if (booking == null ||
          hold.colByName('BookingID') == null ||
          _int(hold.colByName('BookingID')) != booking['id']) {
        completeHoldSet = false;
      }
      final holdIsUnexpired = expiresAtUtc.isAfter(nowUtc);
      if (status != 'Active' || !holdIsUnexpired) {
        completeHoldSet = false;
        if (!holdIsUnexpired) holdExpired = true;
      }
      holdsByLesson[number] = {
        'status': status,
        'expiresAtUtc': expiresAtUtc,
      };
    }
    for (var lessonNumber = 1; lessonNumber <= lessonCount; lessonNumber++) {
      if (!bookingByLesson.containsKey(lessonNumber) ||
          !holdsByLesson.containsKey(lessonNumber)) {
        completeHoldSet = false;
      }
    }
    if (!completeHoldSet) {
      await _expirePaymentPurchase(
        connection,
        purchaseId: purchaseId,
        nowUtc: nowUtc,
      );
      return _PaymentTransactionOutcome.conflict(
        BookingPurchaseConflict(
          holdExpired ? 'hold_expired' : 'incomplete_hold_set',
          holdExpired
              ? 'One or more lesson holds have expired.'
              : 'The purchase does not have all required lesson holds.',
        ),
      );
    }

    final attemptNumber = attempts.rows.isEmpty
        ? 1
        : _int(attempts.rows.last.colByName('AttemptNumber')) + 1;
    if (attemptNumber > 65535) {
      throw const BookingPurchaseServiceUnavailable();
    }
    final succeeded = command.simulatedOutcome == 'success';
    final status = succeeded ? 'Successful' : 'Failed';
    final timestamp = _formatUtcDateTime(nowUtc);
    final attemptInsert = await connection.execute(
      '''
      INSERT INTO PaymentAttempt (
        PurchaseID, AttemptNumber, IdempotencyKey, PaymentMethod,
        PaymentMode, DemoOutcome, PaymentStatus, Amount, FailureCode,
        CreatedAtUtc, UpdatedAtUtc, ResolvedAtUtc
      ) VALUES (
        :purchaseId, :attemptNumber, :idempotencyKey, :paymentMethod,
        'Demo', :demoOutcome, :paymentStatus, :amount, :failureCode,
        :nowUtc, :nowUtc, :nowUtc
      )
      ''',
      {
        'purchaseId': purchaseId,
        'attemptNumber': attemptNumber,
        'idempotencyKey': command.idempotencyKey,
        'paymentMethod': command.paymentMethod,
        'demoOutcome': expectedOutcome,
        'paymentStatus': status,
        'amount': amount,
        'failureCode': succeeded ? null : 'simulated_failure',
        'nowUtc': timestamp,
      },
    );
    final attemptId = attemptInsert.lastInsertID.toInt();

    if (succeeded) {
      await connection.execute(
        '''
        INSERT INTO PurchasePayment (
          PurchaseID, PaymentAttemptID, Amount, CreatedAtUtc
        ) VALUES (:purchaseId, :attemptId, :amount, :nowUtc)
        ''',
        {
          'purchaseId': purchaseId,
          'attemptId': attemptId,
          'amount': amount,
          'nowUtc': timestamp,
        },
      );
      final purchaseUpdate = await connection.execute(
        '''
        UPDATE BookingPurchase
        SET PurchaseStatus = 'Paid'
        WHERE PurchaseID = :purchaseId AND PurchaseStatus = 'Held'
        ''',
        {'purchaseId': purchaseId},
      );
      final bookingUpdate = await connection.execute(
        '''
        UPDATE Booking
        SET Status = 'Confirmed'
        WHERE PurchaseID = :purchaseId AND Status = 'Pending'
        ''',
        {'purchaseId': purchaseId},
      );
      final holdUpdate = await connection.execute(
        '''
        UPDATE BookingSlotHold
        SET HoldStatus = 'Consumed', ConsumedAtUtc = :nowUtc
        WHERE PurchaseID = :purchaseId
          AND HoldStatus = 'Active' AND ExpiresAtUtc > :nowUtc
        ''',
        {'purchaseId': purchaseId, 'nowUtc': timestamp},
      );
      if (purchaseUpdate.affectedRows != BigInt.one ||
          bookingUpdate.affectedRows != BigInt.from(lessonCount) ||
          holdUpdate.affectedRows != BigInt.from(lessonCount)) {
        throw const BookingPurchaseServiceUnavailable();
      }
    }

    return _PaymentTransactionOutcome.receipt(
      PaymentAttemptReceipt(
        paymentAttemptId: attemptId,
        attemptNumber: attemptNumber,
        paymentStatus: status,
        purchaseStatus: succeeded ? 'Paid' : 'Held',
        replayed: false,
        settled: succeeded,
      ),
    );
  }

  Future<BookingPurchaseReceipt> _createInTransaction(
    MySQLConnection connection,
    int studentId,
    CreateBookingPurchaseCommand command,
  ) async {
    final student = await connection.execute(
      '''
      SELECT sp.StudentID
      FROM StudentProfile sp
      INNER JOIN `User` u ON u.UserId = sp.UserID
      WHERE sp.StudentID = :studentId
        AND u.Role = 'student'
        AND u.AccountStatus = 'Active'
      FOR UPDATE
      ''',
      {'studentId': studentId},
    );
    if (student.rows.isEmpty) {
      throw const BookingPurchaseNotFound();
    }

    final tutorLock = await connection.execute(
      'SELECT TutorID FROM TutorProfile WHERE TutorID = :tutorId FOR UPDATE',
      {'tutorId': command.tutorId},
    );
    if (tutorLock.rows.isEmpty) throw const BookingPurchaseNotFound();

    final existing = await connection.execute(
      '''
      SELECT PurchaseID, RequestFingerprint
      FROM BookingPurchase
      WHERE StudentID = :studentId AND IdempotencyKey = :idempotencyKey
      FOR UPDATE
      ''',
      {
        'studentId': studentId,
        'idempotencyKey': command.idempotencyKey,
      },
    );
    if (existing.rows.isNotEmpty) {
      final row = existing.rows.first;
      if (_string(row.colByName('RequestFingerprint')) != command.fingerprint) {
        throw const BookingPurchaseConflict(
          'idempotency_key_reused',
          'The idempotency key was already used for a different request.',
        );
      }
      final purchaseId = _int(row.colByName('PurchaseID'));
      await _expirePurchaseIfNeeded(connection, purchaseId);
      return _loadReceipt(connection, studentId, purchaseId, replayed: true);
    }

    final eligibility = await connection.execute(
      '''
      SELECT tp.TutorID
      FROM TutorProfile tp
      INNER JOIN `User` u ON u.UserId = tp.UserID
      WHERE tp.TutorID = :tutorId
        AND u.Role = 'tutor'
        AND u.AccountStatus = 'Active'
        AND tp.VerificationStat = 'Approved'
        AND EXISTS (
          SELECT 1 FROM TutorApplication ta
          WHERE ta.TutorID = tp.TutorID AND ta.Status = 'Approved'
        )
        AND EXISTS (
          SELECT 1 FROM TutorSubjects ts
          INNER JOIN Subjects s ON s.subjectId = ts.SubjectID
          WHERE ts.TutorID = tp.TutorID
            AND s.subjectId = :subjectId
        )
      LIMIT 1
      ''',
      {'tutorId': command.tutorId, 'subjectId': command.subjectId},
    );
    if (eligibility.rows.isEmpty) throw const BookingPurchaseNotFound();

    final rateResult = await connection.execute(
      'SELECT TutoringRate FROM PlatformSettings WHERE SettingsID = 1 LIMIT 1',
    );
    if (rateResult.rows.isEmpty) {
      throw const BookingPurchaseServiceUnavailable();
    }
    final rate = _string(rateResult.rows.first.colByName('TutoringRate'));
    final price = calculateBookingPrice(
      platformRate: rate,
      purchaseType: command.purchaseType,
      lessonCount: command.lessons.length,
    );

    final availabilityResult = await connection.execute(
      '''
      SELECT Day, StartTime, end_Time
      FROM TutAvailability
      WHERE TutorID = :tutorId
      ORDER BY Day, StartTime
      ''',
      {'tutorId': command.tutorId},
    );
    final availability = [
      for (final row in availabilityResult.rows)
        WeeklyAvailability(
          weekday: _weekday(_string(row.colByName('Day'))),
          startMinutes: parseClockTime(_string(row.colByName('StartTime'))),
          endMinutes: parseClockTime(_string(row.colByName('end_Time'))),
        ),
    ];

    final databaseNowResult = await connection.execute(
      'SELECT UTC_TIMESTAMP(6) AS NowUtc',
    );
    final databaseNow = _utcDateTime(
      databaseNowResult.rows.first.colByName('NowUtc'),
    );
    for (final lesson in command.lessons) {
      validateLessonSlot(
        slot: lesson.interval,
        nowUtc: databaseNow,
        availability: availability,
      );
    }
    await _ensureNoConflicts(
      connection,
      studentId: studentId,
      tutorId: command.tutorId,
      lessons: command.lessons,
    );

    final purchaseInsert = await connection.execute(
      '''
      INSERT INTO BookingPurchase (
        StudentID, TutorID, SubjectID, PurchaseType, LessonCount,
        RatePerLesson, SubtotalAmount, DiscountPercent, DiscountAmount,
        TotalAmount, IdempotencyKey, RequestFingerprint, PurchaseStatus,
        CreatedAtUtc
      ) VALUES (
        :studentId, :tutorId, :subjectId, :purchaseType, :lessonCount,
        :rate, :subtotal, :discountPercent, :discount, :total,
        :idempotencyKey, :fingerprint, 'Held', UTC_TIMESTAMP(6)
      )
      ''',
      {
        'studentId': studentId,
        'tutorId': command.tutorId,
        'subjectId': command.subjectId,
        'purchaseType': command.purchaseType,
        'lessonCount': command.lessons.length,
        'rate': price.rate,
        'subtotal': price.subtotal,
        'discountPercent': price.discountPercent,
        'discount': price.discount,
        'total': price.total,
        'idempotencyKey': command.idempotencyKey,
        'fingerprint': command.fingerprint,
      },
    );
    final purchaseId = purchaseInsert.lastInsertID.toInt();
    final allocations = price.allocateLessonCents();
    final bookingIds = <int>[];

    for (var index = 0; index < command.lessons.length; index++) {
      final lesson = command.lessons[index];
      final bookingInsert = await connection.execute(
        '''
        INSERT INTO Booking (
          StudentID, TutorID, SubjectID, PurchaseID, LessonNumber,
          LessonPriceAtPurchase, `Date`, StartTime, EndTime, Status
        ) VALUES (
          :studentId, :tutorId, :subjectId, :purchaseId, :lessonNumber,
          :lessonPrice, :lessonDate, :startTime, :endTime, 'Pending'
        )
        ''',
        {
          'studentId': studentId,
          'tutorId': command.tutorId,
          'subjectId': command.subjectId,
          'purchaseId': purchaseId,
          'lessonNumber': index + 1,
          'lessonPrice': formatMoney(allocations[index]),
          'lessonDate': lesson.date.iso,
          'startTime': lesson.startTime,
          'endTime': lesson.endTime,
        },
      );
      bookingIds.add(bookingInsert.lastInsertID.toInt());
    }

    final holdTimes = await connection.execute(
      '''
      SELECT UTC_TIMESTAMP(6) AS CreatedAtUtc,
             DATE_ADD(UTC_TIMESTAMP(6), INTERVAL 10 MINUTE) AS ExpiresAtUtc
      ''',
    );
    final holdCreatedAt = _formatUtcDateTime(
      _utcDateTime(holdTimes.rows.first.colByName('CreatedAtUtc')),
    );
    final holdExpiresAt = _formatUtcDateTime(
      _utcDateTime(holdTimes.rows.first.colByName('ExpiresAtUtc')),
    );
    for (var index = 0; index < command.lessons.length; index++) {
      final lesson = command.lessons[index];
      await connection.execute(
        '''
        INSERT INTO BookingSlotHold (
          PurchaseID, LessonNumber, TutorID, BookingID, LessonDate,
          StartTime, EndTime, HoldStatus, CreatedAtUtc, ExpiresAtUtc
        ) VALUES (
          :purchaseId, :lessonNumber, :tutorId, :bookingId, :lessonDate,
          :startTime, :endTime, 'Active', :createdAtUtc, :expiresAtUtc
        )
        ''',
        {
          'purchaseId': purchaseId,
          'lessonNumber': index + 1,
          'tutorId': command.tutorId,
          'bookingId': bookingIds[index],
          'lessonDate': lesson.date.iso,
          'startTime': lesson.startTime,
          'endTime': lesson.endTime,
          'createdAtUtc': holdCreatedAt,
          'expiresAtUtc': holdExpiresAt,
        },
      );
    }
    return _loadReceipt(connection, studentId, purchaseId, replayed: false);
  }

  Future<void> _ensureNoConflicts(
    MySQLConnection connection, {
    required int studentId,
    required int tutorId,
    required List<PurchaseLesson> lessons,
  }) async {
    for (final lesson in lessons) {
      final bookings = await connection.execute(
        '''
        SELECT Booking_id
        FROM Booking
        WHERE `Date` = :lessonDate
          AND Status = 'Confirmed'
          AND (TutorID = :tutorId OR StudentID = :studentId)
          AND StartTime < :endTime
          AND EndTime > :startTime
        ORDER BY Booking_id
        FOR UPDATE
        ''',
        {
          'studentId': studentId,
          'tutorId': tutorId,
          'lessonDate': lesson.date.iso,
          'startTime': lesson.startTime,
          'endTime': lesson.endTime,
        },
      );
      if (bookings.rows.isNotEmpty) {
        throw const BookingPurchaseUnavailable();
      }
    }
    for (final lesson in lessons) {
      final holds = await connection.execute(
        '''
        SELECT h.HoldID
        FROM BookingSlotHold h
        INNER JOIN BookingPurchase p ON p.PurchaseID = h.PurchaseID
        WHERE h.LessonDate = :lessonDate
          AND h.HoldStatus = 'Active'
          AND h.ExpiresAtUtc > UTC_TIMESTAMP(6)
          AND (h.TutorID = :tutorId OR p.StudentID = :studentId)
          AND h.StartTime < :endTime
          AND h.EndTime > :startTime
        ORDER BY h.HoldID
        FOR UPDATE
        ''',
        {
          'studentId': studentId,
          'tutorId': tutorId,
          'lessonDate': lesson.date.iso,
          'startTime': lesson.startTime,
          'endTime': lesson.endTime,
        },
      );
      if (holds.rows.isNotEmpty) {
        throw const BookingPurchaseUnavailable();
      }
    }
  }

  Future<void> _expirePurchaseIfNeeded(
    MySQLConnection connection,
    int purchaseId,
  ) async {
    final purchaseResult = await connection.execute(
      '''
      SELECT LessonCount, PurchaseStatus
      FROM BookingPurchase
      WHERE PurchaseID = :purchaseId
      FOR UPDATE
      ''',
      {'purchaseId': purchaseId},
    );
    if (purchaseResult.rows.isEmpty) throw const BookingPurchaseNotFound();
    final purchase = purchaseResult.rows.first;
    if (purchase.colByName('PurchaseStatus') != 'Held') return;

    await connection.execute(
      '''
      SELECT Booking_id
      FROM Booking
      WHERE PurchaseID = :purchaseId
      ORDER BY Booking_id
      FOR UPDATE
      ''',
      {'purchaseId': purchaseId},
    );
    final holds = await connection.execute(
      '''
      SELECT HoldID, LessonNumber, HoldStatus, ExpiresAtUtc
      FROM BookingSlotHold
      WHERE PurchaseID = :purchaseId
      ORDER BY HoldID
      FOR UPDATE
      ''',
      {'purchaseId': purchaseId},
    );
    final nowResult = await connection.execute(
      'SELECT UTC_TIMESTAMP(6) AS NowUtc',
    );
    final nowUtc = _utcDateTime(nowResult.rows.first.colByName('NowUtc'));
    final requiredCount = _int(purchase.colByName('LessonCount'));
    final validLessons = {
      for (final row in holds.rows)
        if (row.colByName('HoldStatus') == 'Active' &&
            _utcDateTime(row.colByName('ExpiresAtUtc')).isAfter(nowUtc))
          _int(row.colByName('LessonNumber')),
    };
    final allLessonsHeld =
        validLessons.length == requiredCount &&
        List<bool>.generate(
          requiredCount,
          (index) => validLessons.contains(index + 1),
        ).every((isHeld) => isHeld);
    if (!allLessonsHeld) {
      await connection.execute(
        '''
        UPDATE Booking
        SET Status = 'Cancelled'
        WHERE PurchaseID = :purchaseId AND Status = 'Pending'
        ''',
        {'purchaseId': purchaseId},
      );
      await connection.execute(
        '''
        UPDATE BookingSlotHold
        SET HoldStatus = CASE
              WHEN ExpiresAtUtc <= :nowUtc THEN 'Expired'
              ELSE 'Released'
            END,
            ReleasedAtUtc = CASE
              WHEN ExpiresAtUtc <= :nowUtc THEN ReleasedAtUtc
              ELSE :nowUtc
            END
        WHERE PurchaseID = :purchaseId
          AND HoldStatus = 'Active'
        ''',
        {'purchaseId': purchaseId, 'nowUtc': _formatUtcDateTime(nowUtc)},
      );
      await connection.execute(
        '''
        UPDATE BookingPurchase
        SET PurchaseStatus = 'Expired'
        WHERE PurchaseID = :purchaseId AND PurchaseStatus = 'Held'
        ''',
        {'purchaseId': purchaseId},
      );
    }
  }

  Future<BookingPurchaseReceipt> _loadReceipt(
    MySQLConnection connection,
    int studentId,
    int purchaseId, {
    required bool replayed,
  }) async {
    final purchaseResult = await connection.execute(
      '''
      SELECT PurchaseID, TutorID, SubjectID, PurchaseStatus, RatePerLesson,
             LessonCount, SubtotalAmount, DiscountPercent, DiscountAmount,
             TotalAmount
      FROM BookingPurchase
      WHERE PurchaseID = :purchaseId AND StudentID = :studentId
      ''',
      {'purchaseId': purchaseId, 'studentId': studentId},
    );
    if (purchaseResult.rows.isEmpty) throw const BookingPurchaseNotFound();
    final purchase = purchaseResult.rows.first;
    final lessonResult = await connection.execute(
      '''
      SELECT b.Booking_id, b.LessonNumber, b.`Date`, b.StartTime, b.EndTime,
             CASE
               WHEN h.HoldStatus = 'Active'
                 AND h.ExpiresAtUtc <= UTC_TIMESTAMP(6)
               THEN 'Expired'
               ELSE h.HoldStatus
             END AS HoldStatus
      FROM Booking b
      INNER JOIN BookingSlotHold h
        ON h.PurchaseID = b.PurchaseID
       AND h.LessonNumber = b.LessonNumber
      WHERE b.PurchaseID = :purchaseId
      ORDER BY b.LessonNumber
      ''',
      {'purchaseId': purchaseId},
    );
    final lessons = [
      for (final row in lessonResult.rows)
        PurchaseLessonReceipt(
          bookingId: _int(row.colByName('Booking_id')),
          lessonNumber: _int(row.colByName('LessonNumber')),
          lesson: PurchaseLesson(
            date: BookingDate.parse(_string(row.colByName('Date'))),
            startMinutes: parseClockTime(_string(row.colByName('StartTime'))),
            endMinutes: parseClockTime(_string(row.colByName('EndTime'))),
          ),
          holdStatus: _receiptHoldStatus(
            _string(row.colByName('HoldStatus')),
          ),
        ),
    ];
    if (lessons.length != _int(purchase.colByName('LessonCount'))) {
      throw const BookingPurchaseServiceUnavailable();
    }
    final expiryResult = await connection.execute(
      '''
      SELECT MAX(ExpiresAtUtc) AS HoldExpiresAt
      FROM BookingSlotHold WHERE PurchaseID = :purchaseId
      ''',
      {'purchaseId': purchaseId},
    );
    return BookingPurchaseReceipt(
      purchaseId: _int(purchase.colByName('PurchaseID')),
      purchaseStatus: _string(purchase.colByName('PurchaseStatus')),
      holdExpiresAtUtc: _utcDateTime(
        expiryResult.rows.first.colByName('HoldExpiresAt'),
      ),
      tutorId: _int(purchase.colByName('TutorID')),
      subjectId: _int(purchase.colByName('SubjectID')),
      rate: _string(purchase.colByName('RatePerLesson')),
      lessonCount: _int(purchase.colByName('LessonCount')),
      subtotal: _string(purchase.colByName('SubtotalAmount')),
      discountPercent: _discountPercent(
        purchase.colByName('DiscountPercent'),
      ),
      discount: _string(purchase.colByName('DiscountAmount')),
      total: _string(purchase.colByName('TotalAmount')),
      lessons: lessons,
      replayed: replayed,
    );
  }
}

Future<void> _expirePaymentPurchase(
  MySQLConnection connection, {
  required int purchaseId,
  required DateTime nowUtc,
}) async {
  final formattedNow = _formatUtcDateTime(nowUtc);
  await connection.execute(
    '''
    UPDATE Booking
    SET Status = 'Cancelled'
    WHERE PurchaseID = :purchaseId AND Status = 'Pending'
    ''',
    {'purchaseId': purchaseId},
  );
  await connection.execute(
    '''
    UPDATE BookingSlotHold
    SET HoldStatus = CASE
          WHEN ExpiresAtUtc <= :nowUtc THEN 'Expired'
          ELSE 'Released'
        END,
        ReleasedAtUtc = CASE
          WHEN ExpiresAtUtc <= :nowUtc THEN ReleasedAtUtc
          ELSE :nowUtc
        END
    WHERE PurchaseID = :purchaseId AND HoldStatus = 'Active'
    ''',
    {'purchaseId': purchaseId, 'nowUtc': formattedNow},
  );
  await connection.execute(
    '''
    UPDATE BookingPurchase
    SET PurchaseStatus = 'Expired'
    WHERE PurchaseID = :purchaseId AND PurchaseStatus = 'Held'
    ''',
    {'purchaseId': purchaseId},
  );
}

class _PaymentTransactionOutcome {
  const _PaymentTransactionOutcome._({this.receipt, this.conflict});

  const _PaymentTransactionOutcome.receipt(PaymentAttemptReceipt value)
    : this._(receipt: value);

  const _PaymentTransactionOutcome.conflict(BookingPurchaseConflict value)
    : this._(conflict: value);

  final PaymentAttemptReceipt? receipt;
  final BookingPurchaseConflict? conflict;
}

String _receiptHoldStatus(String status) => status;

int _int(Object? value) {
  if (value is int) return value;
  if (value is BigInt) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const BookingPurchaseServiceUnavailable();
}

int _discountPercent(Object? value) {
  if (value == 0 || value == 0.0 || value == '0' || value == '0.00') {
    return 0;
  }
  if (value == 10 || value == 10.0 || value == '10' || value == '10.00') {
    return 10;
  }
  throw const BookingPurchaseServiceUnavailable();
}

String _string(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  if (value is int || value is BigInt || value is double) return '$value';
  throw const BookingPurchaseServiceUnavailable();
}

String _formatUtcDateTime(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}:'
      '${utc.second.toString().padLeft(2, '0')}.'
      '${utc.microsecond.toString().padLeft(6, '0')}';
}

DateTime _utcDateTime(Object? value) {
  final text = _string(value);
  final iso = text.contains('T') ? text : text.replaceFirst(' ', 'T');
  return DateTime.parse(iso.endsWith('Z') ? iso : '${iso}Z').toUtc();
}

int _weekday(String value) {
  const values = {
    'Monday': DateTime.monday,
    'Tuesday': DateTime.tuesday,
    'Wednesday': DateTime.wednesday,
    'Thursday': DateTime.thursday,
    'Friday': DateTime.friday,
    'Saturday': DateTime.saturday,
    'Sunday': DateTime.sunday,
  };
  final weekday = values[value];
  if (weekday == null) throw const BookingPurchaseServiceUnavailable();
  return weekday;
}
