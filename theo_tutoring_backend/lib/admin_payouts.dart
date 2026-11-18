import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/payout_finance.dart';
import 'package:theo_tutoring_backend/sa_time.dart';

// The admin Payouts page: tutor earnings recorded in `payout`, one per paid
// lesson that has finished (lib/payout_finance.dart has the money rules).
// An administrator generates payouts for eligible lessons, approves them and
// then marks them as paid. Marking a payout as Paid only records that the
// payment was made outside the platform; it moves no money.
//
// Status flow (schema.sql ENUM): Pending -> Approved -> Paid. No other change
// is allowed and no step can be repeated or undone. Generation, approval and
// payment each write a payoutadminaction row in the same transaction
// (migration 013), so every step is attributable to an administrator.

// ignore_for_file: public_member_api_docs

/// Status filters the page can ask for -> stored Status (null = all).
const adminPayoutStatuses = <String, String?>{
  'all': null,
  'pending': 'Pending',
  'approved': 'Approved',
  'paid': 'Paid',
};

/// MySQL named lock that lets only one payout generation run at a time,
/// across every backend instance using the same database.
const payoutGenerationLock = 'theotutoring.payout_generation';

/// Seconds a generation request waits for another one to finish.
const payoutGenerationLockTimeoutSeconds = 10;

class AdminPayoutQuery {
  const AdminPayoutQuery({this.status, this.page = 1, this.pageSize = 20});

  /// A stored Status value, or null for every payout.
  final String? status;
  final int page;
  final int pageSize;
}

class AdminPayoutNotFound implements Exception {
  const AdminPayoutNotFound();
}

/// The payout is not in the status the action needs, or another
/// administrator changed it at the same time.
class AdminPayoutConflict implements Exception {
  const AdminPayoutConflict(this.message);
  final String message;
}

typedef AdminPayoutsRepositoryFactory = AdminPayoutsRepository Function();

abstract interface class AdminPayoutsRepository {
  /// One page of payouts, totals per status and the financial overview.
  Future<Map<String, Object?>> list(AdminPayoutQuery query);

  /// Creates a Pending payout for every eligible lesson that has none yet
  /// and returns how many were created (0 when there is nothing new).
  /// Throws [AdminPayoutConflict] when another generation is running.
  Future<int> generate(AdminIdentity admin);

  /// Pending -> Approved, recording the approving admin and ApprovedAt.
  /// Throws [AdminPayoutNotFound] or [AdminPayoutConflict].
  Future<void> approve(int payoutId, AdminIdentity admin);

  /// Approved -> Paid, recording the paying admin, PaidAt and the optional
  /// external payment [reference].
  /// Throws [AdminPayoutNotFound] or [AdminPayoutConflict].
  Future<void> markPaid(int payoutId, AdminIdentity admin, {String? reference});
}

/// The payout ID from the URL, or null when it is not a positive integer.
int? parsePayoutId(String? raw) {
  final id = int.tryParse(raw ?? '');
  return id == null || id <= 0 ? null : id;
}

/// The lesson has ended in South African time (lib/sa_time.dart).
const _endedSql =
    '(b.`Date` < $saTodaySql OR '
    '(b.`Date` = $saTodaySql AND b.EndTime <= $saClockSql))';

/// A legacy per-booking payment that a purchase settlement already links
/// (purchasepayment.PaymentID) is part of that purchase's money: it is never
/// counted, or classified, a second time.
const _unlinkedLegacyPayment =
    'NOT EXISTS (SELECT 1 FROM purchasepayment lpp '
    'WHERE lpp.PaymentID = lp.PaymentID)';

/// Every successfully paid lesson with its price, its purchase's captured
/// commission rate, its refund and its payout. One row per booking: each
/// joined table holds at most one row per booking or purchase.
///
/// [where] narrows it (e.g. to candidate bookings) and [lock] adds a locking
/// clause; generation re-reads its candidates with `FOR SHARE OF b, r` so it
/// sees the latest committed booking and refund rows, not its snapshot.
String paidLessonsQuery({String where = '', String lock = ''}) =>
    '''
  SELECT b.Booking_id, b.TutorID, b.Status,
    CASE WHEN b.Status = 'Completed'
           OR (b.Status = 'Confirmed' AND $_endedSql)
         THEN 1 ELSE 0 END AS Ended,
    CASE WHEN $_endedSql THEN 1 ELSE 0 END AS PastEnd,
    CASE WHEN b.PurchaseID IS NULL THEN lp.Amount
         ELSE b.LessonPriceAtPurchase END AS Price,
    CASE WHEN b.PurchaseID IS NULL THEN lp.CommissionPercentage
         ELSE bp.CommissionPercentage END AS CommissionPercentage,
    CASE WHEN b.PurchaseID IS NULL
         THEN IF(lp.CommissionPercentage IS NULL, NULL, 'Payment')
         ELSE bp.CommissionSource END AS CommissionSource,
    r.RefundStatus, r.RefundAmount,
    p.PayoutID, p.CommissionAmount + p.NetAmount AS PayoutTotal
  FROM booking b
  LEFT JOIN bookingpurchase bp ON bp.PurchaseID = b.PurchaseID
  LEFT JOIN purchasepayment pp ON pp.PurchaseID = b.PurchaseID
  LEFT JOIN payment lp ON lp.BookingId = b.Booking_id
    AND b.PurchaseID IS NULL AND lp.PaymentStatus = 'Successful'
    AND $_unlinkedLegacyPayment
  LEFT JOIN refund r ON r.BookingID = b.Booking_id
  LEFT JOIN payout p ON p.BookingID = b.Booking_id
  WHERE ((b.PurchaseID IS NOT NULL AND pp.PurchasePaymentID IS NOT NULL)
     OR (b.PurchaseID IS NULL AND lp.PaymentID IS NOT NULL))
  $where
  ORDER BY b.Booking_id
  $lock
''';

/// Every successful student payment: purchase settlements plus legacy
/// per-booking payments for bookings without a purchase that no settlement
/// already includes.
const _receivedSql =
    '''
  SELECT
    (SELECT COALESCE(SUM(Amount), 0) FROM purchasepayment) AS PurchaseReceived,
    (SELECT COALESCE(SUM(lp.Amount), 0) FROM payment lp
       INNER JOIN booking b ON b.Booking_id = lp.BookingId
       WHERE lp.PaymentStatus = 'Successful' AND b.PurchaseID IS NULL
         AND $_unlinkedLegacyPayment)
      AS LegacyReceived
''';

const _payoutTotalsSql = '''
  SELECT
    COALESCE(SUM(Status = 'Pending'), 0) AS PendingCount,
    COALESCE(SUM(CASE WHEN Status = 'Pending' THEN NetAmount END), 0)
      AS PendingNet,
    COALESCE(SUM(Status = 'Approved'), 0) AS ApprovedCount,
    COALESCE(SUM(CASE WHEN Status = 'Approved' THEN NetAmount END), 0)
      AS ApprovedNet,
    COALESCE(SUM(Status = 'Paid'), 0) AS PaidCount,
    COALESCE(SUM(CASE WHEN Status = 'Paid' THEN NetAmount END), 0)
      AS PaidNet,
    COALESCE(SUM(CommissionAmount), 0) AS CommissionTotal,
    COALESCE(SUM(Amount <> CommissionAmount + NetAmount), 0)
      AS InconsistentCount
  FROM payout
''';

const _payoutFrom = '''
  FROM payout p
  INNER JOIN tutorprofile tp ON tp.TutorID = p.TutorID
  INNER JOIN `user` tu ON tu.UserId = tp.UserID
  LEFT JOIN booking b ON b.Booking_id = p.BookingID
  LEFT JOIN bookingpurchase bp ON bp.PurchaseID = b.PurchaseID
  LEFT JOIN studentprofile sp ON sp.StudentID = b.StudentID
  LEFT JOIN `user` su ON su.UserId = sp.UserID
  LEFT JOIN subjects s ON s.subjectId = b.SubjectID
  LEFT JOIN admin a ON a.AdminID = p.AdminID
  LEFT JOIN `user` au ON au.UserId = a.UserId
  LEFT JOIN admin pa ON pa.AdminID = p.PaidByAdminID
  LEFT JOIN `user` pu ON pu.UserId = pa.UserId
  LEFT JOIN refund r ON r.BookingID = p.BookingID
''';

// Created_at, ApprovedAt and PaidAt are all server wall-clock DATETIMEs
// (Created_at defaults to CURRENT_TIMESTAMP), returned without a zone.
const _payoutColumns = '''
  SELECT p.PayoutID, p.Amount, p.CommissionAmount, p.NetAmount, p.Status,
    p.BookingID, p.PaymentReference,
    DATE_FORMAT(p.Created_at, '%Y-%m-%dT%H:%i:%s') AS CreatedAt,
    DATE_FORMAT(p.ApprovedAt, '%Y-%m-%dT%H:%i:%s') AS ApprovedAt,
    DATE_FORMAT(p.PaidAt, '%Y-%m-%dT%H:%i:%s') AS PaidAt,
    tp.TutorID, tu.Name AS TutorName, tu.Email AS TutorEmail,
    su.Name AS StudentName, s.subjectName,
    DATE_FORMAT(b.Date, '%Y-%m-%d') AS SessionDate,
    TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
    TIME_FORMAT(b.EndTime, '%H:%i') AS EndTime,
    b.Status AS BookingStatus,
    bp.CommissionPercentage, bp.CommissionSource,
    au.Name AS ApprovedBy, pu.Name AS PaidBy,
    r.RefundStatus, r.RefundAmount
''';

const _auditInsertSql = '''
  INSERT INTO payoutadminaction
    (PayoutID, AdminID, Action, NetAmount, PaymentReference, CreatedAtUtc)
  SELECT PayoutID, :adminId, :action, NetAmount, :reference, UTC_TIMESTAMP(6)
  FROM payout WHERE PayoutID = :id
''';

int _int(String? value) => int.tryParse(value ?? '') ?? 0;

double _money(String? value) => double.tryParse(value ?? '') ?? 0;

/// A paid-lesson row of [paidLessonsQuery].
PaidLesson paidLessonFromRow(ResultSetRow row) {
  final payoutId = int.tryParse(row.str('PayoutID') ?? '');
  return PaidLesson(
    bookingId: _int(row.str('Booking_id')),
    tutorId: _int(row.str('TutorID')),
    bookingStatus: row.str('Status') ?? '',
    ended: row.str('Ended') == '1',
    pastEnd: row.str('PastEnd') == '1',
    priceCents: parseCents(row.str('Price')) ?? 0,
    commissionRateHundredths: parseRateHundredths(
      row.str('CommissionPercentage'),
    ),
    commissionSource: row.str('CommissionSource'),
    refundStatus: row.str('RefundStatus'),
    refundCents: parseCents(row.str('RefundAmount')),
    payoutId: payoutId,
    payoutTotalCents: payoutId == null
        ? null
        : parseCents(row.str('PayoutTotal')),
  );
}

Map<String, Object?> _payout(ResultSetRow row) {
  final bookingId = int.tryParse(row.str('BookingID') ?? '');
  final refundStatus = row.str('RefundStatus');
  final refundSettled = settledRefundStatuses.contains(refundStatus);
  return {
    'payoutId': _int(row.str('PayoutID')),
    'status': row.str('Status')?.toLowerCase(),
    'amount': _money(row.str('Amount')),
    'commissionAmount': _money(row.str('CommissionAmount')),
    'netAmount': _money(row.str('NetAmount')),
    'commissionRate': row.str('CommissionPercentage'),
    'commissionRateBackfilled': row.str('CommissionSource') == 'Backfilled',
    'createdAt': row.str('CreatedAt'),
    'approvedAt': row.str('ApprovedAt'),
    'paidAt': row.str('PaidAt'),
    'approvedBy': row.str('ApprovedBy'),
    'paidBy': row.str('PaidBy'),
    'paymentReference': row.str('PaymentReference'),
    // A refund recorded for the lesson after its payout was generated: the
    // payout is left unchanged and flagged for an administrator to review.
    'refund': refundStatus == null || refundStatus == 'Rejected'
        ? null
        : {
            'status': refundStatus.toLowerCase(),
            'amount': _money(row.str('RefundAmount')),
          },
    'flagged': refundSettled || refundStatus == 'Pending',
    'tutor': {
      'tutorId': _int(row.str('TutorID')),
      'name': row.str('TutorName'),
      'email': row.str('TutorEmail'),
    },
    'booking': bookingId == null
        ? null
        : {
            'bookingId': bookingId,
            'studentName': row.str('StudentName'),
            'subject': row.str('subjectName'),
            'date': row.str('SessionDate'),
            'startTime': row.str('StartTime'),
            'endTime': row.str('EndTime'),
            'status': row.str('BookingStatus'),
          },
  };
}

class MySqlAdminPayoutsRepository implements AdminPayoutsRepository {
  MySqlAdminPayoutsRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final Future<MySQLConnection> Function() _connectionFactory;

  static Future<List<PaidLesson>> _paidLessons(
    MySQLConnection c, {
    String where = '',
    String lock = '',
  }) async {
    final rows = await c.execute(paidLessonsQuery(where: where, lock: lock));
    return [for (final row in rows.rows) paidLessonFromRow(row)];
  }

  @override
  Future<Map<String, Object?>> list(AdminPayoutQuery query) async {
    final connection = await _connectionFactory();
    try {
      // One transaction, so every figure comes from the same snapshot and
      // the reconciliation is not thrown off by a concurrent change.
      return await connection.transactional((tx) async {
        final params = <String, dynamic>{};
        var where = '';
        if (query.status != null) {
          where = 'WHERE p.Status = :status';
          params['status'] = query.status;
        }
        final total = await tx.execute(
          'SELECT COUNT(*) AS n FROM payout p $where',
          params,
        );
        final rows = await tx.execute(
          '$_payoutColumns $_payoutFrom $where '
          'ORDER BY p.Created_at DESC, p.PayoutID DESC '
          'LIMIT :limit OFFSET :offset',
          {
            ...params,
            'limit': query.pageSize,
            'offset': (query.page - 1) * query.pageSize,
          },
        );
        // The cards above the list cover every payout, not just this filter.
        final s = (await tx.execute(_payoutTotalsSql)).rows.first;
        final totals = PayoutTotals(
          pendingCount: _int(s.str('PendingCount')),
          pendingNetCents: parseCents(s.str('PendingNet')) ?? 0,
          approvedCount: _int(s.str('ApprovedCount')),
          approvedNetCents: parseCents(s.str('ApprovedNet')) ?? 0,
          paidCount: _int(s.str('PaidCount')),
          paidNetCents: parseCents(s.str('PaidNet')) ?? 0,
          commissionCents: parseCents(s.str('CommissionTotal')) ?? 0,
          inconsistentCount: _int(s.str('InconsistentCount')),
        );
        final received = (await tx.execute(_receivedSql)).rows.first;
        final finance = payoutFinanceSummary(
          receivedCents:
              (parseCents(received.str('PurchaseReceived')) ?? 0) +
              (parseCents(received.str('LegacyReceived')) ?? 0),
          payouts: totals,
          lessons: await _paidLessons(tx),
        );
        return <String, Object?>{
          'total': _int(total.rows.first.str('n')),
          'page': query.page,
          'pageSize': query.pageSize,
          'summary': {
            'pendingCount': totals.pendingCount,
            'pendingNetAmount': totals.pendingNetCents / 100,
            'approvedCount': totals.approvedCount,
            'approvedNetAmount': totals.approvedNetCents / 100,
            'paidCount': totals.paidCount,
            'paidNetAmount': totals.paidNetCents / 100,
          },
          'finance': finance,
          'payouts': [for (final row in rows.rows) _payout(row)],
        };
      });
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  @override
  Future<int> generate(AdminIdentity admin) async {
    final connection = await _connectionFactory();
    var locked = false;
    try {
      // Taken before the transaction starts, so its snapshot includes every
      // payout a previous generation committed.
      final lock = await connection.execute(
        'SELECT GET_LOCK(:name, :timeout) AS Locked',
        {
          'name': payoutGenerationLock,
          'timeout': payoutGenerationLockTimeoutSeconds,
        },
      );
      locked = lock.rows.isNotEmpty && lock.rows.first.str('Locked') == '1';
      if (!locked) {
        throw const AdminPayoutConflict(
          'Payouts are already being generated. Refresh in a moment.',
        );
      }
      return await connection.transactional((tx) async {
        // 1. Candidates from the transaction's snapshot (no locks).
        final candidates = [
          for (final lesson in await _paidLessons(tx))
            if (isEligibleForPayout(lesson)) lesson.bookingId,
        ]..sort();
        if (candidates.isEmpty) return 0;
        final ids = candidates.join(', ');
        // 2. Lock order booking -> refund -> payout, as cancellations and
        //    refund decisions use. Shared locks on the bookings, in ascending
        //    order, wait for any cancellation still holding one (it locks the
        //    booking FOR UPDATE before writing its refund) and keep new ones
        //    out until this transaction ends.
        await tx.execute(
          'SELECT Booking_id FROM booking WHERE Booking_id IN ($ids) '
          'ORDER BY Booking_id FOR SHARE',
        );
        // 3. Re-read with a locking read, which returns the latest committed
        //    booking and refund rows rather than the snapshot of step 1, and
        //    re-check eligibility on them before inserting anything.
        final drafts = [
          for (final lesson in await _paidLessons(
            tx,
            where: 'AND b.Booking_id IN ($ids)',
            lock: 'FOR SHARE OF b, r',
          ))
            if (isEligibleForPayout(lesson)) draftPayout(lesson),
        ];
        for (final draft in drafts) {
          final inserted = await tx.execute(
            '''
            INSERT INTO payout
              (TutorID, Amount, CommissionAmount, NetAmount, Status, BookingID)
            VALUES (:tutorId, :amount, :commission, :net, 'Pending', :bookingId)
            ''',
            {
              'tutorId': draft.tutorId,
              'amount': formatCents(draft.amountCents),
              'commission': formatCents(draft.commissionCents),
              'net': formatCents(draft.netCents),
              'bookingId': draft.bookingId,
            },
          );
          await tx.execute(_auditInsertSql, {
            'adminId': admin.id,
            'action': 'Generated',
            'reference': null,
            'id': inserted.lastInsertID.toInt(),
          });
        }
        return drafts.length;
      });
    } on MySQLServerException catch (error) {
      // 1062: payout.BookingID is unique, so a payout created by anything
      // outside this lock rolls the whole generation back instead of
      // duplicating it.
      if (error.errorCode == 1062) {
        throw const AdminPayoutConflict(
          'Some payouts were created at the same time by another request. '
          'Nothing was added; refresh and try again.',
        );
      }
      rethrow;
    } finally {
      if (locked && connection.connected) {
        try {
          await connection.execute('SELECT RELEASE_LOCK(:name) AS Released', {
            'name': payoutGenerationLock,
          });
        } on Object {
          // Closing the connection below releases the lock anyway.
        }
      }
      if (connection.connected) await connection.close();
    }
  }

  @override
  Future<void> approve(int payoutId, AdminIdentity admin) => _transition(
    payoutId,
    admin,
    from: 'Pending',
    action: 'Approved',
    update: '''
      UPDATE payout
      SET Status = 'Approved', AdminID = :adminId, ApprovedAt = NOW()
      WHERE PayoutID = :id AND Status = 'Pending'
    ''',
    params: {'adminId': admin.id, 'id': payoutId},
    conflictFor: (status) => switch (status) {
      'Approved' => 'This payout is already approved.',
      'Paid' => 'This payout has already been paid.',
      _ => 'Only pending payouts can be approved.',
    },
  );

  @override
  Future<void> markPaid(
    int payoutId,
    AdminIdentity admin, {
    String? reference,
  }) => _transition(
    payoutId,
    admin,
    from: 'Approved',
    action: 'Paid',
    reference: reference,
    update: '''
      UPDATE payout
      SET Status = 'Paid', PaidAt = NOW(), PaidByAdminID = :adminId,
          PaymentReference = :reference
      WHERE PayoutID = :id AND Status = 'Approved'
    ''',
    params: {'adminId': admin.id, 'reference': reference, 'id': payoutId},
    conflictFor: (status) => switch (status) {
      'Pending' => 'Approve this payout before marking it as paid.',
      'Paid' => 'This payout is already marked as paid.',
      _ => 'Only approved payouts can be marked as paid.',
    },
  );

  /// Locks booking -> refund -> payout (the order cancellations, refund
  /// decisions and generation use), checks the payout is in [from] and that
  /// no unresolved refund blocks it ([payoutRefundBlock]), then runs [update]
  /// and writes the audit row in the same transaction, so two admins cannot
  /// both move the same payout and no step goes unrecorded.
  Future<void> _transition(
    int payoutId,
    AdminIdentity admin, {
    required String from,
    required String action,
    required String update,
    required Map<String, dynamic> params,
    required String Function(String? status) conflictFor,
    String? reference,
  }) async {
    final connection = await _connectionFactory();
    try {
      await connection.transactional<void>((transaction) async {
        // The payout's booking never changes, so it is found without a lock.
        final owner = await transaction.execute(
          'SELECT BookingID FROM payout WHERE PayoutID = :id',
          {'id': payoutId},
        );
        if (owner.rows.isEmpty) throw const AdminPayoutNotFound();
        final bookingId = owner.rows.first.str('BookingID');
        await transaction.execute(
          'SELECT Booking_id FROM booking WHERE Booking_id = :booking '
          'FOR SHARE',
          {'booking': bookingId},
        );
        final refund = await transaction.execute(
          'SELECT RefundStatus FROM refund WHERE BookingID = :booking '
          'FOR SHARE',
          {'booking': bookingId},
        );
        final current = await transaction.execute(
          'SELECT Status FROM payout WHERE PayoutID = :id FOR UPDATE',
          {'id': payoutId},
        );
        if (current.rows.isEmpty) throw const AdminPayoutNotFound();
        final status = current.rows.first.str('Status');
        if (status != from) throw AdminPayoutConflict(conflictFor(status));
        final blocked = payoutRefundBlock(
          refund.rows.isEmpty ? null : refund.rows.first.str('RefundStatus'),
        );
        if (blocked != null) throw AdminPayoutConflict(blocked);
        final result = await transaction.execute(update, params);
        if (result.affectedRows != BigInt.one) {
          throw AdminPayoutConflict(conflictFor(null));
        }
        final audit = await transaction.execute(_auditInsertSql, {
          'adminId': admin.id,
          'action': action,
          'reference': reference,
          'id': payoutId,
        });
        if (audit.affectedRows != BigInt.one) {
          throw AdminPayoutConflict(conflictFor(null));
        }
      });
    } on MySQLServerException catch (error) {
      // 1062: uq_payout_action_once, the step was already recorded.
      if (error.errorCode == 1062) {
        throw AdminPayoutConflict(conflictFor(action));
      }
      rethrow;
    } finally {
      if (connection.connected) await connection.close();
    }
  }
}
