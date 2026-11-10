import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/database.dart';

/// The ?status= values GET /admin/reports accepts, and the Report.Status
/// each one means (null = every report).
const reportStatusFilters = <String, String?>{
  'all': null,
  'open': 'Open',
  'under-review': 'Under review',
  'resolved': 'Resolved',
};

/// Reads the Report table for the admin Reports page.
// ignore: one_member_abstracts
abstract interface class AdminReportRepository {
  /// Newest first: {"total", "page", "pageSize", "reports": [...]}.
  Future<Map<String, Object?>> list({
    required int page,
    required int pageSize,
    String? status,
    String? category,
  });
}

/// Reports in MySQL, with who sent them and who they are about.
class MySqlAdminReportRepository implements AdminReportRepository {
  /// Uses the shared connection unless a test passes its own.
  MySqlAdminReportRepository({
    Future<MySQLConnection> Function() connectionFactory = getConnection,
  }) : _connect = connectionFactory;

  final Future<MySQLConnection> Function() _connect;

  @override
  Future<Map<String, Object?>> list({
    required int page,
    required int pageSize,
    String? status,
    String? category,
  }) async {
    final conn = await _connect();
    const where = '''
      WHERE (:status IS NULL OR r.Status = :status)
        AND (:category IS NULL OR r.Category = :category)
    ''';
    final params = <String, Object?>{'status': status, 'category': category};

    final count = await conn.execute(
      'SELECT COUNT(*) AS Total FROM Report r $where',
      params,
    );
    final rows = await conn.execute(
      '''
      SELECT r.ReportID, r.Category, r.Reason, r.Status, r.BookingID,
             DATE_FORMAT(r.Created_at, '%Y-%m-%d %H:%i:%s') AS CreatedAt,
             reporter.UserId AS ReporterUserId, reporter.Name AS ReporterName,
             reporter.Email AS ReporterEmail, reporter.Role AS ReporterRole,
             reported.UserId AS ReportedUserId, reported.Name AS ReportedName,
             reported.Email AS ReportedEmail, reported.Role AS ReportedRole
      FROM Report r
      INNER JOIN `User` reporter ON reporter.UserId = r.ReporterID
      LEFT JOIN `User` reported ON reported.UserId = r.ReportedUserID
      $where
      ORDER BY r.Created_at DESC, r.ReportID DESC
      LIMIT $pageSize OFFSET ${(page - 1) * pageSize}
      ''',
      params,
    );

    Map<String, Object?>? person(ResultSetRow row, String prefix) {
      final id = row.colByName('${prefix}UserId');
      if (id == null) return null;
      return {
        'userId': int.parse(id),
        'name': row.colByName('${prefix}Name'),
        'email': row.colByName('${prefix}Email'),
        'role': row.colByName('${prefix}Role'),
      };
    }

    return {
      'total': int.parse(count.rows.first.colByName('Total') ?? '0'),
      'page': page,
      'pageSize': pageSize,
      'reports': [
        for (final row in rows.rows)
          {
            'reportId': int.parse(row.colByName('ReportID')!),
            // null for the students' lesson/tutor reports made before
            // categories (migration 010)
            'category': row.colByName('Category'),
            'description': row.colByName('Reason'),
            'status': row.colByName('Status'),
            'bookingId': int.tryParse(row.colByName('BookingID') ?? ''),
            'createdAt': row.colByName('CreatedAt'),
            'reporter': person(row, 'Reporter'),
            // null when the report is not about another user
            'reportedUser': person(row, 'Reported'),
          },
      ],
    };
  }
}
