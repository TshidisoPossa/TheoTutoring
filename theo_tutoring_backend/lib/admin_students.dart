import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/sa_time.dart';

/// Roster filters sent by the Flutter app (lower case) -> User.AccountStatus.
const rosterStatusFilters = {
  'all': null,
  'active': 'Active',
  'suspended': 'Suspended',
  'pending': 'Pending',
};

// Only these may be set by an admin; history and payments are never touched.
const rosterSettableStatuses = {'Active', 'Suspended', 'Deactivated'};

class StudentNotFound implements Exception {
  const StudentNotFound();
}

abstract interface class StudentRosterRepository {
  /// [status] is a User.AccountStatus value, or null for all students.
  Future<Map<String, Object?>> list({
    String? status,
    String? search,
    required int page,
    required int pageSize,
  });

  /// One student as the roster shows them. Throws [StudentNotFound].
  /// (Status changes go through the AccountSuspensionRepository, which also
  /// records suspensions.)
  Future<Map<String, Object?>> find(int studentId);
}

const _studentSelect =
    'SELECT sp.StudentID, u.Name, u.Email, u.PhoneNum, u.ProfilePhoto, '
    'u.Created_at, u.AccountStatus, sp.Course, sp.InstitutionYear, '
    'sp.Subject_of_interest, sp.Institution, sp.ProofOfReg, '
    '(SELECT COUNT(*) FROM booking b WHERE b.StudentID = sp.StudentID '
    "AND b.Status = 'Completed') AS TotalLessons "
    'FROM `user` u JOIN studentprofile sp ON sp.UserID = u.UserId ';

Map<String, Object?> _student(ResultSetRow r) => {
  'studentId': int.parse(r.reqStr('StudentID')),
  'name': r.str('Name'),
  'email': r.str('Email'),
  'phone': r.str('PhoneNum'),
  'photoUrl': r.str('ProfilePhoto'),
  'course': r.str('Course'),
  'institutionYear': r.str('InstitutionYear'),
  'subjectOfInterest': r.str('Subject_of_interest'),
  'totalLessons': int.parse(r.reqStr('TotalLessons')),
  'joinedAt': r.str('Created_at'),
  'status': r.str('AccountStatus'),
  // What the admin checks the proof of registration against
  'institution': r.str('Institution'),
  // Proof of registration uploaded at sign-up (Cloudinary link)
  'proofOfRegistrationUrl': r.str('ProofOfReg'),
};

class MySqlStudentRosterRepository implements StudentRosterRepository {
  @override
  Future<Map<String, Object?>> list({
    String? status,
    String? search,
    required int page,
    required int pageSize,
  }) async {
    final conn = await getConnection();
    final where = <String>["u.Role = 'student'"];
    final params = <String, dynamic>{};
    if (status != null) {
      where.add('u.AccountStatus = :status');
      params['status'] = status;
    }
    if (search != null && search.isNotEmpty) {
      where.add('(u.Name LIKE :q OR u.Email LIKE :q)');
      params['q'] = '%${search.replaceAll(RegExp(r'[%_\\]'), '')}%';
    }
    final clause = where.join(' AND ');
    final total = await conn.execute(
      'SELECT COUNT(*) AS n FROM `user` u '
      'JOIN studentprofile sp ON sp.UserID = u.UserId WHERE $clause',
      params,
    );
    final rows = await conn.execute(
      '$_studentSelect WHERE $clause '
      'ORDER BY u.Created_at DESC, sp.StudentID DESC '
      'LIMIT :limit OFFSET :offset',
      {...params, 'limit': pageSize, 'offset': (page - 1) * pageSize},
    );
    final summary = await conn.execute(
      'SELECT COUNT(*) AS total, '
      "COALESCE(SUM(u.AccountStatus = 'Suspended'), 0) AS suspended, "
      '(SELECT COUNT(DISTINCT b.StudentID) FROM booking b '
      'WHERE b.`Date` >= DATE_FORMAT($saTodaySql, \'%Y-%m-01\')) AS activeMonth, '
      "(SELECT COUNT(*) FROM booking b WHERE b.Status = 'Completed') AS lessons "
      'FROM `user` u JOIN studentprofile sp ON sp.UserID = u.UserId '
      "WHERE u.Role = 'student'",
    );
    final s = summary.rows.first;
    final totalStudents = int.parse(s.reqStr('total'));
    final lessons = int.parse(s.reqStr('lessons'));
    return {
      'total': int.parse(total.rows.first.reqStr('n')),
      'page': page,
      'pageSize': pageSize,
      'summary': {
        'totalStudents': totalStudents,
        'activeThisMonth': int.parse(s.reqStr('activeMonth')),
        'avgLessonsPerStudent': totalStudents == 0
            ? 0.0
            : double.parse((lessons / totalStudents).toStringAsFixed(1)),
        'suspendedAccounts': int.parse(s.reqStr('suspended')),
      },
      'students': [for (final r in rows.rows) _student(r)],
    };
  }

  @override
  Future<Map<String, Object?>> find(int studentId) async {
    final conn = await getConnection();
    final row = await conn.execute(
      "$_studentSelect WHERE sp.StudentID = :id AND u.Role = 'student'",
      {'id': studentId},
    );
    if (row.rows.isEmpty) throw const StudentNotFound();
    return _student(row.rows.first);
  }
}
