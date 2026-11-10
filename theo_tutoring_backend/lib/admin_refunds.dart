import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

// The audit API is consumed by route handlers and their focused tests.
// ignore_for_file: public_member_api_docs

class AdminIdentity {
  const AdminIdentity({
    required this.id,
    required this.name,
    this.roleKey = 'admin',
  });

  final int id;
  final String name;
  final String roleKey;

  List<String> get permissions =>
      permissionsForAdminRole(roleKey).toList()..sort();
}

const _permissionKeys = <String>{
  'admin.applications.read',
  'admin.applications.review',
  'admin.dashboard.read',
  'admin.finance.read',
  'admin.monitor.read',
  'admin.payouts.manage',
  'admin.refunds.decide',
  'admin.refunds.read',
  'admin.reports.read',
  'admin.reports.resolve',
  'admin.reviews.read',
  'admin.roles.manage',
  'admin.settings.rate.read',
  'admin.settings.rate.write',
  'admin.students.manage',
  'admin.students.read',
  'admin.tutors.manage',
  'admin.tutors.read',
  'admin.users.manage',
};

const Map<String, Set<String>> adminRolePermissions = {
  'super_admin': _permissionKeys,
  // Legacy Admin rows retain access to the existing Admin feature set, but
  // cannot create accounts or grant roles.
  'admin': {
    'admin.applications.read',
    'admin.applications.review',
    'admin.dashboard.read',
    'admin.finance.read',
    'admin.monitor.read',
    'admin.payouts.manage',
    'admin.refunds.decide',
    'admin.refunds.read',
    'admin.reports.read',
    'admin.reports.resolve',
    'admin.reviews.read',
    'admin.settings.rate.read',
    'admin.settings.rate.write',
  },
  'application_reviewer': {
    'admin.dashboard.read',
    'admin.applications.read',
    'admin.applications.review',
  },
  'finance_admin': {
    'admin.dashboard.read',
    'admin.finance.read',
    'admin.payouts.manage',
    'admin.refunds.decide',
    'admin.refunds.read',
    'admin.reports.read',
    'admin.settings.rate.read',
    'admin.settings.rate.write',
  },
  'support_admin': {
    'admin.dashboard.read',
    'admin.refunds.read',
    'admin.reports.read',
    'admin.reports.resolve',
    'admin.reviews.read',
  },
  'monitor_admin': {'admin.dashboard.read', 'admin.monitor.read'},
};

Set<String> permissionsForAdminRole(String roleKey) =>
    adminRolePermissions[roleKey] ?? const <String>{};

bool isKnownAdminRole(String roleKey) =>
    adminRolePermissions.containsKey(roleKey);

class AdminPermissionDenied extends AdminAccessDenied {
  const AdminPermissionDenied(this.permission)
    : super('The administrator lacks the required permission.');
  final String permission;
}

void requireAdminPermission(AdminIdentity admin, String permission) {
  final permissions = permissionsForAdminRole(admin.roleKey);
  if (!permissions.contains(permission)) {
    throw AdminPermissionDenied(permission);
  }
}

class AdminRefundValidation implements Exception {
  const AdminRefundValidation(this.message);
  final String message;
}

class AdminRefundNotFound implements Exception {
  const AdminRefundNotFound();
}

class AdminRefundConflict implements Exception {
  const AdminRefundConflict(this.message);
  final String message;
}

class AdminAccessDenied implements Exception {
  const AdminAccessDenied(this.message);
  final String message;
}

typedef AdminResolver = Future<AdminIdentity> Function(String? authorization);
typedef AdminRefundRepositoryFactory = AdminRefundsRepository Function();

Future<AdminIdentity> resolveAdmin(String? authorization) async {
  final firebaseUser = await verifyFirebaseToken(authorization);
  final result = await (await getConnection()).execute(
    '''
    SELECT a.AdminID, a.RoleKey, u.Name
    FROM `User` u
    INNER JOIN Admin a ON a.UserId = u.UserId
    WHERE u.FirebaseUid = :uid
      AND u.Role = 'admin'
      AND u.AccountStatus = 'Active'
    LIMIT 1
    ''',
    {'uid': firebaseUser.uid},
  );
  if (result.rows.isEmpty) {
    throw const AdminAccessDenied('Administrator access is required.');
  }
  final row = result.rows.first;
  final roleKey = row.colByName('RoleKey') ?? '';
  if (!isKnownAdminRole(roleKey)) {
    throw const AdminAccessDenied('Administrator role is not recognized.');
  }
  return AdminIdentity(
    id: int.parse(row.colByName('AdminID')!),
    name: row.colByName('Name') ?? 'Administrator',
    roleKey: roleKey,
  );
}

abstract interface class AdminRefundsRepository {
  Future<Map<String, Object?>> fetchCases({
    required String type,
    required String status,
    required String adminName,
  });

  Future<void> approve(int refundId, AdminIdentity admin);
  Future<void> deny(int refundId, AdminIdentity admin, String reason);
  Future<void> overrideDecision(
    int refundId,
    AdminIdentity admin,
    double percentage,
    String reason,
  );
  Future<void> resolveReport(
    int reportId,
    AdminIdentity admin,
    String note,
  );
}

class MySqlAdminRefundsRepository implements AdminRefundsRepository {
  MySqlAdminRefundsRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final Future<MySQLConnection> Function() _connectionFactory;

  @override
  Future<Map<String, Object?>> fetchCases({
    required String type,
    required String status,
    required String adminName,
  }) async {
    final connection = await _connectionFactory();
    try {
      final result = await connection.execute('''
        SELECT
          r.RefundID,
          r.RefundStatus,
          r.RefundPercentage,
          r.RefundAmount,
          r.OverriddenByAdmin,
          r.CancellationTime,
          b.Booking_id,
          b.Date,
          b.StartTime,
          s.subjectName,
          student.Name AS StudentName,
          tutor.Name AS TutorName,
          CASE
            WHEN p.PaymentStatus = 'Successful'
              OR pa.PaymentStatus = 'Successful'
            THEN COALESCE(
              b.LessonPriceAtPurchase,
              p.Amount,
              bp.TotalAmount / NULLIF(bp.LessonCount, 0)
            )
            ELSE NULL
          END AS AmountPaid,
          COALESCE(p.PaymentMethod, pa.PaymentMethod) AS PaymentMethod,
          COALESCE(
            CAST(p.PaymentID AS CHAR),
            pa.PaymentReference,
            CAST(pa.PaymentAttemptID AS CHAR)
          ) AS TransactionID,
          (SELECT action.Reason
             FROM RefundAdminAction action
            WHERE action.RefundID = r.RefundID
            ORDER BY action.CreatedAtUtc DESC, action.RefundAdminActionID DESC
            LIMIT 1) AS DecisionReason,
          (SELECT action.CreatedAtUtc
             FROM RefundAdminAction action
            WHERE action.RefundID = r.RefundID
            ORDER BY action.CreatedAtUtc DESC, action.RefundAdminActionID DESC
            LIMIT 1) AS DecisionAtUtc,
          decisionUser.Name AS DecidedBy
        FROM Refund r
        INNER JOIN Booking b ON b.Booking_id = r.BookingID
        INNER JOIN StudentProfile sp ON sp.StudentID = b.StudentID
        INNER JOIN `User` student ON student.UserId = sp.UserID
        INNER JOIN TutorProfile tp ON tp.TutorID = b.TutorID
        INNER JOIN `User` tutor ON tutor.UserId = tp.UserID
        INNER JOIN Subjects s ON s.subjectId = b.SubjectID
        LEFT JOIN Payment p ON p.BookingId = b.Booking_id
        LEFT JOIN BookingPurchase bp ON bp.PurchaseID = b.PurchaseID
        LEFT JOIN PurchasePayment pp ON pp.PurchaseID = b.PurchaseID
        LEFT JOIN PaymentAttempt pa ON pa.PaymentAttemptID = pp.PaymentAttemptID
        LEFT JOIN Admin decisionAdmin ON decisionAdmin.AdminID = r.AdminID
        LEFT JOIN `User` decisionUser ON decisionUser.UserId = decisionAdmin.UserId
        ORDER BY r.CancellationTime DESC, r.RefundID DESC
      ''');

      final allCases = result.rows.map(_caseJson).toList();
      final reportCases = type == 'cancellation'
          ? <Map<String, Object?>>[]
          : await _fetchReportCases(connection);
      final combinedCases = [...allCases, ...reportCases];
      final pending = allCases.where((item) => item['status'] == 'pending');
      final openReports = reportCases.where(
        (item) => item['status'] != 'resolved',
      );
      final resolvedRecently = allCases.where((item) {
        final at = item['_decisionAtUtc'] as DateTime?;
        return item['status'] != 'pending' &&
            at != null &&
            at.isAfter(
              DateTime.now().toUtc().subtract(const Duration(days: 7)),
            );
      }).length;
      final resolvedReportsRecently = reportCases.where((item) {
        final at = item['_decisionAtUtc'] as DateTime?;
        return item['status'] == 'resolved' &&
            at != null &&
            at.isAfter(
              DateTime.now().toUtc().subtract(const Duration(days: 7)),
            );
      }).length;
      final visibleCases = combinedCases
          .where((item) {
            if (type == 'report' && item['type'] != 'report') return false;
            if (type == 'cancellation' && item['type'] != 'cancellation') {
              return false;
            }
            if (status == 'open' &&
                (item['status'] == 'approved' ||
                    item['status'] == 'denied' ||
                    item['status'] == 'resolved')) {
              return false;
            }
            if (status == 'resolved' &&
                (item['status'] == 'pending' ||
                    item['status'] == 'open' ||
                    item['status'] == 'under_review')) {
              return false;
            }
            return true;
          })
          .map((item) {
            final json = Map<String, Object?>.from(item)
              ..remove('_decisionAtUtc');
            return json;
          })
          .toList();

      return {
        'adminName': adminName,
        'summary': {
          'openDisputes': openReports.length,
          'pendingRefunds': pending.length,
          'pendingRefundAmount': pending.fold<double>(
            0,
            (total, item) =>
                total + ((item['refundAmount'] as num?)?.toDouble() ?? 0),
          ),
          'resolvedLast7Days': resolvedRecently + resolvedReportsRecently,
          'needsAction': pending.length + openReports.length,
        },
        'cases': visibleCases,
      };
    } finally {
      if (connection.connected) {
        await connection.close();
      }
    }
  }

  Map<String, Object?> _caseJson(ResultSetRow row) {
    final status = switch (row.colByName('RefundStatus')) {
      'Approved' || 'Processed' => 'approved',
      'Rejected' => 'denied',
      _ => 'pending',
    };
    final amountPaid = _double(row.colByName('AmountPaid'));
    final storedPercentage = _double(row.colByName('RefundPercentage')) ?? 0;
    final overridden =
        row.colByName('OverriddenByAdmin') == '1' ||
        row.colByName('OverriddenByAdmin')?.toLowerCase() == 'true';
    final percentage = status == 'pending' && !overridden
        ? _policyPercentage(
            _wallTime(row.colByName('CancellationTime')),
            _wallTime(
              '${row.colByName('Date')} ${row.colByName('StartTime')}',
            ),
          )
        : storedPercentage;
    final storedAmount = _double(row.colByName('RefundAmount'));
    final refundAmount =
        storedAmount ??
        (amountPaid == null ? null : _money(amountPaid * percentage / 100));

    return {
      'id': row.colByName('RefundID'),
      'type': 'cancellation',
      'status': status,
      'bookingId': row.colByName('Booking_id'),
      'transactionId': row.colByName('TransactionID'),
      'studentName': row.colByName('StudentName'),
      'tutorName': row.colByName('TutorName'),
      'subject': row.colByName('subjectName'),
      'sessionStart': _johannesburgIso(
        '${row.colByName('Date')} ${row.colByName('StartTime')}',
      ),
      'cancelledAt': _johannesburgIso(row.colByName('CancellationTime')),
      'createdAt': _johannesburgIso(row.colByName('CancellationTime')),
      'reportedBy': null,
      'reason': row.colByName('DecisionReason'),
      'amountPaid': amountPaid,
      'paymentMethod': row.colByName('PaymentMethod'),
      'refundPercentage': percentage,
      'refundAmount': refundAmount,
      'overriddenByAdmin': overridden,
      'decidedBy': row.colByName('DecidedBy'),
      'needsAction': status == 'pending',
      '_decisionAtUtc': _utcDateTime(row.colByName('DecisionAtUtc')),
    };
  }

  Future<List<Map<String, Object?>>> _fetchReportCases(
    MySQLConnection connection,
  ) async {
    final result = await connection.execute('''
      SELECT
        report.ReportID,
        report.Status AS ReportStatus,
        report.Category,
        report.Reason,
        -- Created_at is server (South African) time; the page wants UTC
        TIMESTAMPADD(
          SECOND,
          TIMESTAMPDIFF(SECOND, NOW(), UTC_TIMESTAMP()),
          report.Created_at
        ) AS CreatedAtUtc,
        report.ResolvedAtUtc,
        report.ResolutionNote,
        reporter.Role AS ReporterRole,
        CASE WHEN reporter.Role = 'student' THEN reporter.Name ELSE reported.Name END
          AS StudentName,
        CASE WHEN reporter.Role = 'tutor' THEN reporter.Name ELSE reported.Name END
          AS TutorName,
        booking.Booking_id,
        booking.Date,
        booking.StartTime,
        subject.subjectName,
        CASE
          WHEN payment.PaymentStatus = 'Successful'
            OR attempt.PaymentStatus = 'Successful'
          THEN COALESCE(
            booking.LessonPriceAtPurchase,
            payment.Amount,
            purchase.TotalAmount / NULLIF(purchase.LessonCount, 0)
          )
          ELSE NULL
        END AS AmountPaid,
        COALESCE(payment.PaymentMethod, attempt.PaymentMethod) AS PaymentMethod,
        COALESCE(
          CAST(payment.PaymentID AS CHAR),
          attempt.PaymentReference,
          CAST(attempt.PaymentAttemptID AS CHAR)
        ) AS TransactionID,
        adminUser.Name AS DecidedBy
      FROM Report report
      INNER JOIN `User` reporter ON reporter.UserId = report.ReporterID
      -- empty for Payments & Payouts / Other (not about another user)
      LEFT JOIN `User` reported ON reported.UserId = report.ReportedUserID
      LEFT JOIN Booking booking ON booking.Booking_id = report.BookingID
      LEFT JOIN Subjects subject ON subject.subjectId = booking.SubjectID
      LEFT JOIN Payment payment ON payment.BookingId = booking.Booking_id
      LEFT JOIN BookingPurchase purchase ON purchase.PurchaseID = booking.PurchaseID
      LEFT JOIN PurchasePayment purchasePayment
        ON purchasePayment.PurchaseID = booking.PurchaseID
      LEFT JOIN PaymentAttempt attempt
        ON attempt.PaymentAttemptID = purchasePayment.PaymentAttemptID
      LEFT JOIN Admin admin ON admin.AdminID = report.AdminID
      LEFT JOIN `User` adminUser ON adminUser.UserId = admin.UserId
      ORDER BY report.Created_at DESC, report.ReportID DESC
    ''');
    return result.rows.map(_reportJson).toList();
  }

  Map<String, Object?> _reportJson(ResultSetRow row) {
    final rawStatus = row.colByName('ReportStatus')?.toLowerCase();
    final status = switch (rawStatus) {
      'resolved' => 'resolved',
      'under review' || 'underreview' || 'under_review' => 'under_review',
      _ => 'open',
    };
    final sessionDate = row.colByName('Date');
    // Tutors' Report a Problem has a category; students' reports do not
    final category = row.colByName('Category');
    final description = row.colByName('Reason');
    return {
      'id': 'report-${row.colByName('ReportID')}',
      'type': 'report',
      'status': status,
      'bookingId': row.colByName('Booking_id'),
      'transactionId': row.colByName('TransactionID'),
      'studentName': row.colByName('StudentName'),
      'tutorName': row.colByName('TutorName'),
      'subject': row.colByName('subjectName'),
      'sessionStart': sessionDate == null
          ? null
          : _johannesburgIso('$sessionDate ${row.colByName('StartTime')}'),
      'cancelledAt': null,
      'createdAt': _johannesburgIso(row.colByName('CreatedAtUtc')),
      'reportedBy': row.colByName('ReporterRole'),
      'reason': category == null ? description : '$category: $description',
      'amountPaid': _double(row.colByName('AmountPaid')),
      'paymentMethod': row.colByName('PaymentMethod'),
      'refundPercentage': null,
      'refundAmount': null,
      'overriddenByAdmin': false,
      'decidedBy': row.colByName('DecidedBy'),
      'needsAction': status != 'resolved',
      '_decisionAtUtc': _utcDateTime(row.colByName('ResolvedAtUtc')),
    };
  }

  @override
  Future<void> approve(int refundId, AdminIdentity admin) =>
      _decide(refundId, admin, 'Approved');

  @override
  Future<void> deny(int refundId, AdminIdentity admin, String reason) =>
      _decide(refundId, admin, 'Denied', reason: reason);

  @override
  Future<void> overrideDecision(
    int refundId,
    AdminIdentity admin,
    double percentage,
    String reason,
  ) async {
    final connection = await _connectionFactory();
    try {
      await connection.transactional((transaction) async {
        final record = await _selectForUpdate(transaction, refundId);
        final amountPaid = _double(record.colByName('AmountPaid'));
        if (amountPaid == null || amountPaid <= 0) {
          throw const AdminRefundConflict(
            'An override requires a successful payment.',
          );
        }
        if (record.colByName('RefundStatus') != 'Pending') {
          throw const AdminRefundConflict('This refund is already closed.');
        }
        final amount = _money(amountPaid * percentage / 100);
        await transaction.execute(
          '''
          UPDATE Refund
          SET RefundPercentage = :percentage,
              RefundAmount = :amount,
              OverriddenByAdmin = TRUE,
              AdminID = :adminId
          WHERE RefundID = :refundId AND RefundStatus = 'Pending'
          ''',
          {
            'percentage': percentage,
            'amount': amount,
            'adminId': admin.id,
            'refundId': refundId,
          },
        );
        await _insertAction(
          transaction,
          refundId,
          admin.id,
          'Overridden',
          reason: reason,
          percentage: percentage,
          amount: amount,
        );
      });
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  @override
  Future<void> resolveReport(
    int reportId,
    AdminIdentity admin,
    String note,
  ) async {
    final connection = await _connectionFactory();
    try {
      await connection.transactional((transaction) async {
        final current = await transaction.execute(
          'SELECT Status FROM Report WHERE ReportID = :id FOR UPDATE',
          {'id': reportId},
        );
        if (current.rows.isEmpty) throw const AdminRefundNotFound();
        if (current.rows.first.colByName('Status') == 'Resolved') {
          throw const AdminRefundConflict('This report is already resolved.');
        }
        final update = await transaction.execute(
          '''
          UPDATE Report
          SET Status = 'Resolved',
              ResolutionNote = :note,
              AdminID = :adminId,
              ResolvedAtUtc = UTC_TIMESTAMP(6)
          WHERE ReportID = :id AND Status <> 'Resolved'
          ''',
          {'note': note, 'adminId': admin.id, 'id': reportId},
        );
        if (update.affectedRows != BigInt.one) {
          throw const AdminRefundConflict('This report is already resolved.');
        }
      });
    } finally {
      if (connection.connected) {
        await connection.close();
      }
    }
  }

  Future<void> _decide(
    int refundId,
    AdminIdentity admin,
    String decision, {
    String? reason,
  }) async {
    final connection = await _connectionFactory();
    try {
      await connection.transactional((transaction) async {
        final record = await _selectForUpdate(transaction, refundId);
        if (record.colByName('RefundStatus') != 'Pending') {
          throw const AdminRefundConflict('This refund is already closed.');
        }
        var percentage = _double(record.colByName('RefundPercentage')) ?? 0;
        if (record.colByName('OverriddenByAdmin') != '1') {
          percentage = _policyPercentage(
            _wallTime(record.colByName('CancellationTime')),
            _wallTime(record.colByName('SessionStart')),
          );
        }
        final amountPaid = _double(record.colByName('AmountPaid'));
        if (decision == 'Approved' && (amountPaid == null || amountPaid <= 0)) {
          throw const AdminRefundConflict(
            'This booking has no successful payment to refund.',
          );
        }
        final amount = decision == 'Approved' && amountPaid != null
            ? _money(amountPaid * percentage / 100)
            : null;
        await transaction.execute(
          '''
          UPDATE Refund
          SET RefundStatus = :status,
              RefundPercentage = :percentage,
              RefundAmount = :amount,
              AdminID = :adminId
          WHERE RefundID = :refundId AND RefundStatus = 'Pending'
          ''',
          {
            'status': decision,
            'percentage': percentage,
            'amount': amount,
            'adminId': admin.id,
            'refundId': refundId,
          },
        );
        await _insertAction(
          transaction,
          refundId,
          admin.id,
          decision,
          reason: reason,
          percentage: amount == null ? null : percentage,
          amount: amount,
        );
      });
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  Future<ResultSetRow> _selectForUpdate(
    MySQLConnection transaction,
    int refundId,
  ) async {
    final result = await transaction.execute(
      '''
      SELECT
        r.RefundStatus,
        r.RefundPercentage,
        r.OverriddenByAdmin,
        r.CancellationTime,
        CONCAT(b.Date, ' ', b.StartTime) AS SessionStart,
        CASE
          WHEN p.PaymentStatus = 'Successful' OR pa.PaymentStatus = 'Successful'
          THEN COALESCE(
            b.LessonPriceAtPurchase,
            p.Amount,
            bp.TotalAmount / NULLIF(bp.LessonCount, 0)
          )
          ELSE NULL
        END AS AmountPaid
      FROM Refund r
      INNER JOIN Booking b ON b.Booking_id = r.BookingID
      LEFT JOIN Payment p ON p.BookingId = b.Booking_id
      LEFT JOIN BookingPurchase bp ON bp.PurchaseID = b.PurchaseID
      LEFT JOIN PurchasePayment pp ON pp.PurchaseID = b.PurchaseID
      LEFT JOIN PaymentAttempt pa ON pa.PaymentAttemptID = pp.PaymentAttemptID
      WHERE r.RefundID = :refundId
      FOR UPDATE
      ''',
      {'refundId': refundId},
    );
    if (result.rows.isEmpty) throw const AdminRefundNotFound();
    return result.rows.first;
  }

  Future<void> _insertAction(
    MySQLConnection transaction,
    int refundId,
    int adminId,
    String action, {
    String? reason,
    double? percentage,
    double? amount,
  }) async {
    await transaction.execute(
      '''
      INSERT INTO RefundAdminAction
        (RefundID, AdminID, Action, Reason, RefundPercentage, RefundAmount, CreatedAtUtc)
      VALUES
        (:refundId, :adminId, :action, :reason, :percentage, :amount, UTC_TIMESTAMP(6))
      ''',
      {
        'refundId': refundId,
        'adminId': adminId,
        'action': action,
        'reason': reason,
        'percentage': percentage,
        'amount': amount,
      },
    );
  }
}

double? _double(String? value) => value == null ? null : double.tryParse(value);

double _money(double amount) => (amount * 100).roundToDouble() / 100;

DateTime? _wallTime(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value.trim().replaceFirst(' ', 'T');
  return DateTime.tryParse(
    normalized.endsWith('Z') ? normalized : '${normalized}Z',
  );
}

DateTime? _utcDateTime(String? value) => _wallTime(value);

String? _johannesburgIso(String? value) {
  final date = _wallTime(value);
  if (date == null) return null;
  final local = date.add(const Duration(hours: 2));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}T'
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}+02:00';
}

double _policyPercentage(DateTime? cancelledAt, DateTime? sessionStart) {
  if (cancelledAt == null || sessionStart == null) return 0;
  final noticeMinutes = sessionStart.difference(cancelledAt).inMinutes;
  if (noticeMinutes >= 48 * 60) return 100;
  if (noticeMinutes >= 24 * 60) return 50;
  return 0;
}

int parseRefundId(String? raw) {
  final id = int.tryParse(raw ?? '');
  if (id == null || id <= 0) {
    throw const AdminRefundValidation(
      'The refund ID must be a positive integer.',
    );
  }
  return id;
}

int parseReportId(String? raw) {
  if (raw == null || !raw.startsWith('report-')) {
    throw const AdminRefundValidation('The report ID is invalid.');
  }
  final id = int.tryParse(raw.substring('report-'.length));
  if (id == null || id <= 0) {
    throw const AdminRefundValidation(
      'The report ID must be a positive integer.',
    );
  }
  return id;
}

void validateReason(String? reason, {required String fieldName}) {
  if (reason == null ||
      reason.trim().length < 5 ||
      reason.trim().length > 1000) {
    throw AdminRefundValidation(
      '$fieldName must be between 5 and 1000 characters.',
    );
  }
}

double parseRefundPercentage(Object? value) {
  final percentage = value is num ? value.toDouble() : double.nan;
  if (!percentage.isFinite || percentage < 0 || percentage > 100) {
    throw const AdminRefundValidation(
      'Refund percentage must be a number between 0 and 100.',
    );
  }
  return percentage;
}
