import 'package:theo_tutoring_backend/database.dart';

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

  /// Updates only `User.AccountStatus` of a student and returns that student.
  Future<Map<String, Object?>> setStatus(int studentId, String status);
}

const _studentSelect =
    'SELECT sp.StudentID, u.Name, u.Email, u.PhoneNum, u.ProfilePhoto, '
    'u.Created_at, u.AccountStatus, sp.Course, sp.InstitutionYear, '
    'sp.Subject_of_interest, '
    '(SELECT COUNT(*) FROM Booking b WHERE b.StudentID = sp.StudentID '
    "AND b.Status = 'Completed') AS TotalLessons "
    'FROM `User` u JOIN StudentProfile sp ON sp.UserID = u.UserId ';

Map<String, Object?> _student(dynamic r) => {
  'studentId': int.parse(r.colByName('StudentID')! as String),
  'name': r.colByName('Name'),
  'email': r.colByName('Email'),
  'phone': r.colByName('PhoneNum'),
  'photoUrl': r.colByName('ProfilePhoto'),
  'course': r.colByName('Course'),
  'institutionYear': r.colByName('InstitutionYear'),
  'subjectOfInterest': r.colByName('Subject_of_interest'),
  'totalLessons': int.parse(r.colByName('TotalLessons')! as String),
  'joinedAt': r.colByName('Created_at'),
  'status': r.colByName('AccountStatus'),
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
      'SELECT COUNT(*) AS n FROM `User` u '
      'JOIN StudentProfile sp ON sp.UserID = u.UserId WHERE $clause',
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
      '(SELECT COUNT(DISTINCT b.StudentID) FROM Booking b '
      'WHERE b.`Date` >= DATE_FORMAT(CURDATE(), \'%Y-%m-01\')) AS activeMonth, '
      "(SELECT COUNT(*) FROM Booking b WHERE b.Status = 'Completed') AS lessons "
      'FROM `User` u JOIN StudentProfile sp ON sp.UserID = u.UserId '
      "WHERE u.Role = 'student'",
    );
    final s = summary.rows.first;
    final totalStudents = int.parse(s.colByName('total')!);
    final lessons = int.parse(s.colByName('lessons')!);
    return {
      'total': int.parse(total.rows.first.colByName('n')!),
      'page': page,
      'pageSize': pageSize,
      'summary': {
        'totalStudents': totalStudents,
        'activeThisMonth': int.parse(s.colByName('activeMonth')!),
        'avgLessonsPerStudent': totalStudents == 0
            ? 0.0
            : double.parse((lessons / totalStudents).toStringAsFixed(1)),
        'suspendedAccounts': int.parse(s.colByName('suspended')!),
      },
      'students': [for (final r in rows.rows) _student(r)],
    };
  }

  @override
  Future<Map<String, Object?>> setStatus(int studentId, String status) async {
    final conn = await getConnection();
    final found = await conn.execute(
      'SELECT u.UserId FROM `User` u JOIN StudentProfile sp '
      "ON sp.UserID = u.UserId WHERE sp.StudentID = :id AND u.Role = 'student'",
      {'id': studentId},
    );
    if (found.rows.isEmpty) throw const StudentNotFound();
    await conn.execute(
      'UPDATE `User` SET AccountStatus = :status WHERE UserId = :uid',
      {'status': status, 'uid': found.rows.first.colByName('UserId')},
    );
    final row = await conn.execute(
      '$_studentSelect WHERE sp.StudentID = :id',
      {'id': studentId},
    );
    return _student(row.rows.first);
  }
}
