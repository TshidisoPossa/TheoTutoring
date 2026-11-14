import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';

// The admin Payouts page: tutor earnings recorded in `payout`, which an
// administrator approves and then marks as paid. Marking a payout as Paid only
// records that the payment was made outside the platform; it moves no money.
//
// Status flow (schema.sql ENUM): Pending -> Approved -> Paid. No other change
// is allowed and no step can be repeated or undone.

// ignore_for_file: public_member_api_docs

/// Status filters the page can ask for -> stored Status (null = all).
const adminPayoutStatuses = <String, String?>{
  'all': null,
  'pending': 'Pending',
  'approved': 'Approved',
  'paid': 'Paid',
};

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

/// The payout is not in the status the action needs.
class AdminPayoutConflict implements Exception {
  const AdminPayoutConflict(this.message);
  final String message;
}

typedef AdminPayoutsRepositoryFactory = AdminPayoutsRepository Function();

abstract interface class AdminPayoutsRepository {
  /// One page of payouts plus totals per status across every payout.
  Future<Map<String, Object?>> list(AdminPayoutQuery query);

  /// Pending -> Approved, recording the approving admin and ApprovedAt.
  /// Throws [AdminPayoutNotFound] or [AdminPayoutConflict].
  Future<void> approve(int payoutId, AdminIdentity admin);

  /// Approved -> Paid, recording PaidAt.
  /// Throws [AdminPayoutNotFound] or [AdminPayoutConflict].
  Future<void> markPaid(int payoutId, AdminIdentity admin);
}

/// The payout ID from the URL, or null when it is not a positive integer.
int? parsePayoutId(String? raw) {
  final id = int.tryParse(raw ?? '');
  return id == null || id <= 0 ? null : id;
}

const _payoutFrom = '''
  FROM payout p
  INNER JOIN tutorprofile tp ON tp.TutorID = p.TutorID
  INNER JOIN `user` tu ON tu.UserId = tp.UserID
  LEFT JOIN booking b ON b.Booking_id = p.BookingID
  LEFT JOIN studentprofile sp ON sp.StudentID = b.StudentID
  LEFT JOIN `user` su ON su.UserId = sp.UserID
  LEFT JOIN subjects s ON s.subjectId = b.SubjectID
  LEFT JOIN admin a ON a.AdminID = p.AdminID
  LEFT JOIN `user` au ON au.UserId = a.UserId
''';

// Created_at, ApprovedAt and PaidAt are all server wall-clock DATETIMEs
// (Created_at defaults to CURRENT_TIMESTAMP), returned without a zone.
const _payoutColumns = '''
  SELECT p.PayoutID, p.Amount, p.CommissionAmount, p.NetAmount, p.Status,
    p.BookingID,
    DATE_FORMAT(p.Created_at, '%Y-%m-%dT%H:%i:%s') AS CreatedAt,
    DATE_FORMAT(p.ApprovedAt, '%Y-%m-%dT%H:%i:%s') AS ApprovedAt,
    DATE_FORMAT(p.PaidAt, '%Y-%m-%dT%H:%i:%s') AS PaidAt,
    tp.TutorID, tu.Name AS TutorName, tu.Email AS TutorEmail,
    su.Name AS StudentName, s.subjectName,
    DATE_FORMAT(b.Date, '%Y-%m-%d') AS SessionDate,
    TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
    TIME_FORMAT(b.EndTime, '%H:%i') AS EndTime,
    b.Status AS BookingStatus,
    au.Name AS ApprovedBy
''';

int _int(String? value) => int.tryParse(value ?? '') ?? 0;

double _money(String? value) => double.tryParse(value ?? '') ?? 0;

Map<String, Object?> _payout(ResultSetRow row) {
  final bookingId = int.tryParse(row.str('BookingID') ?? '');
  return {
    'payoutId': _int(row.str('PayoutID')),
    'status': row.str('Status')?.toLowerCase(),
    'amount': _money(row.str('Amount')),
    'commissionAmount': _money(row.str('CommissionAmount')),
    'netAmount': _money(row.str('NetAmount')),
    'createdAt': row.str('CreatedAt'),
    'approvedAt': row.str('ApprovedAt'),
    'paidAt': row.str('PaidAt'),
    'approvedBy': row.str('ApprovedBy'),
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

  @override
  Future<Map<String, Object?>> list(AdminPayoutQuery query) async {
    final connection = await _connectionFactory();
    try {
      final params = <String, dynamic>{};
      var where = '';
      if (query.status != null) {
        where = 'WHERE p.Status = :status';
        params['status'] = query.status;
      }
      final total = await connection.execute(
        'SELECT COUNT(*) AS n FROM payout p $where',
        params,
      );
      final rows = await connection.execute(
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
      final summary = await connection.execute('''
        SELECT
          COALESCE(SUM(Status = 'Pending'), 0) AS PendingCount,
          COALESCE(SUM(CASE WHEN Status = 'Pending' THEN NetAmount END), 0)
            AS PendingNet,
          COALESCE(SUM(Status = 'Approved'), 0) AS ApprovedCount,
          COALESCE(SUM(CASE WHEN Status = 'Approved' THEN NetAmount END), 0)
            AS ApprovedNet,
          COALESCE(SUM(Status = 'Paid'), 0) AS PaidCount,
          COALESCE(SUM(CASE WHEN Status = 'Paid' THEN NetAmount END), 0)
            AS PaidNet
        FROM payout
      ''');
      final s = summary.rows.first;
      return {
        'total': _int(total.rows.first.str('n')),
        'page': query.page,
        'pageSize': query.pageSize,
        'summary': {
          'pendingCount': _int(s.str('PendingCount')),
          'pendingNetAmount': _money(s.str('PendingNet')),
          'approvedCount': _int(s.str('ApprovedCount')),
          'approvedNetAmount': _money(s.str('ApprovedNet')),
          'paidCount': _int(s.str('PaidCount')),
          'paidNetAmount': _money(s.str('PaidNet')),
        },
        'payouts': [for (final row in rows.rows) _payout(row)],
      };
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  @override
  Future<void> approve(int payoutId, AdminIdentity admin) => _transition(
    payoutId,
    from: 'Pending',
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
  Future<void> markPaid(int payoutId, AdminIdentity admin) => _transition(
    payoutId,
    from: 'Approved',
    update: '''
      UPDATE payout
      SET Status = 'Paid', PaidAt = NOW()
      WHERE PayoutID = :id AND Status = 'Approved'
    ''',
    params: {'id': payoutId},
    conflictFor: (status) => switch (status) {
      'Pending' => 'Approve this payout before marking it as paid.',
      'Paid' => 'This payout is already marked as paid.',
      _ => 'Only approved payouts can be marked as paid.',
    },
  );

  /// Locks the payout row, checks it is in [from], then runs [update] in the
  /// same transaction so two admins cannot both move the same payout.
  Future<void> _transition(
    int payoutId, {
    required String from,
    required String update,
    required Map<String, dynamic> params,
    required String Function(String? status) conflictFor,
  }) async {
    final connection = await _connectionFactory();
    try {
      await connection.transactional<void>((transaction) async {
        final current = await transaction.execute(
          'SELECT Status FROM payout WHERE PayoutID = :id FOR UPDATE',
          {'id': payoutId},
        );
        if (current.rows.isEmpty) throw const AdminPayoutNotFound();
        final status = current.rows.first.str('Status');
        if (status != from) throw AdminPayoutConflict(conflictFor(status));
        final result = await transaction.execute(update, params);
        if (result.affectedRows != BigInt.one) {
          throw AdminPayoutConflict(conflictFor(null));
        }
      });
    } finally {
      if (connection.connected) await connection.close();
    }
  }
}
