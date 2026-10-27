import 'package:theo_tutoring_backend/database.dart';

/// Roster filters sent by the Flutter app (lower case) -> User.AccountStatus.
const tutorRosterStatusFilters = {
  'all': null,
  'active': 'Active',
  'suspended': 'Suspended',
  'pending': 'Pending',
};

// Only these may be set by an admin; history and payments are never touched.
const tutorRosterSettableStatuses = {'Active', 'Suspended', 'Deactivated'};

class TutorNotFound implements Exception {
  const TutorNotFound();
}

/// The tutor has not been approved yet (Incomplete, Pending or Rejected):
/// their status is decided on the Applications page, not here.
class TutorStatusLocked implements Exception {
  const TutorStatusLocked(this.status);
  final String status;
}

abstract interface class TutorRosterRepository {
  /// [status] is a User.AccountStatus value, or null for all tutors.
  Future<Map<String, Object?>> list({
    String? status,
    String? search,
    required int page,
    required int pageSize,
  });

  /// Updates only `User.AccountStatus` of an approved tutor and returns that
  /// tutor. Throws [TutorStatusLocked] for a tutor still in review.
  Future<Map<String, Object?>> setStatus(int tutorId, String status);
}

const _tutorSelect =
    'SELECT tp.TutorID, u.Name, u.Email, u.PhoneNum, u.ProfilePhoto, '
    'u.Created_at, u.AccountStatus, tp.VerificationStat, tp.Experience, '
    'tp.AveRate, '
    '(SELECT COUNT(*) FROM Reviews r WHERE r.TutorId = tp.TutorID) '
    'AS ReviewCount, '
    '(SELECT GROUP_CONCAT(s.subjectName ORDER BY s.subjectName '
    "SEPARATOR ', ') FROM TutorSubjects ts "
    'JOIN Subjects s ON s.subjectId = ts.SubjectID '
    'WHERE ts.TutorID = tp.TutorID) AS SubjectNames, '
    '(SELECT COUNT(*) FROM Booking b WHERE b.TutorID = tp.TutorID '
    "AND b.Status = 'Completed') AS TotalLessons "
    'FROM `User` u JOIN TutorProfile tp ON tp.UserID = u.UserId ';

Map<String, Object?> _tutor(dynamic r) => {
  'tutorId': int.parse(r.colByName('TutorID')! as String),
  'name': r.colByName('Name'),
  'email': r.colByName('Email'),
  'phone': r.colByName('PhoneNum'),
  'photoUrl': r.colByName('ProfilePhoto'),
  'subjects': r.colByName('SubjectNames'),
  'experience': r.colByName('Experience'),
  'verification': r.colByName('VerificationStat'),
  'averageRating': double.tryParse(r.colByName('AveRate') as String? ?? '') ??
      0.0,
  'reviewCount': int.parse(r.colByName('ReviewCount')! as String),
  'totalLessons': int.parse(r.colByName('TotalLessons')! as String),
  'joinedAt': r.colByName('Created_at'),
  'status': r.colByName('AccountStatus'),
};

class MySqlTutorRosterRepository implements TutorRosterRepository {
  @override
  Future<Map<String, Object?>> list({
    String? status,
    String? search,
    required int page,
    required int pageSize,
  }) async {
    final conn = await getConnection();
    final where = <String>["u.Role = 'tutor'"];
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
      'JOIN TutorProfile tp ON tp.UserID = u.UserId WHERE $clause',
      params,
    );
    final rows = await conn.execute(
      '$_tutorSelect WHERE $clause '
      'ORDER BY u.Created_at DESC, tp.TutorID DESC '
      'LIMIT :limit OFFSET :offset',
      {...params, 'limit': pageSize, 'offset': (page - 1) * pageSize},
    );
    final summary = await conn.execute(
      'SELECT COUNT(*) AS total, '
      "COALESCE(SUM(u.AccountStatus = 'Suspended'), 0) AS suspended, "
      '(SELECT COUNT(DISTINCT b.TutorID) FROM Booking b '
      'WHERE b.`Date` >= DATE_FORMAT(CURDATE(), \'%Y-%m-01\')) AS activeMonth, '
      "(SELECT COUNT(*) FROM Booking b WHERE b.Status = 'Completed') AS lessons "
      'FROM `User` u JOIN TutorProfile tp ON tp.UserID = u.UserId '
      "WHERE u.Role = 'tutor'",
    );
    final s = summary.rows.first;
    final totalTutors = int.parse(s.colByName('total')!);
    final lessons = int.parse(s.colByName('lessons')!);
    return {
      'total': int.parse(total.rows.first.colByName('n')!),
      'page': page,
      'pageSize': pageSize,
      'summary': {
        'totalTutors': totalTutors,
        'activeThisMonth': int.parse(s.colByName('activeMonth')!),
        'avgLessonsPerTutor': totalTutors == 0
            ? 0.0
            : double.parse((lessons / totalTutors).toStringAsFixed(1)),
        'suspendedAccounts': int.parse(s.colByName('suspended')!),
      },
      'tutors': [for (final r in rows.rows) _tutor(r)],
    };
  }

  @override
  Future<Map<String, Object?>> setStatus(int tutorId, String status) async {
    final conn = await getConnection();
    final found = await conn.execute(
      'SELECT u.UserId, u.AccountStatus FROM `User` u JOIN TutorProfile tp '
      "ON tp.UserID = u.UserId WHERE tp.TutorID = :id AND u.Role = 'tutor'",
      {'id': tutorId},
    );
    if (found.rows.isEmpty) throw const TutorNotFound();
    final current = found.rows.first.colByName('AccountStatus') ?? '';
    // Activating a tutor in review would skip the application approval.
    if (!tutorRosterSettableStatuses.contains(current)) {
      throw TutorStatusLocked(current);
    }
    await conn.execute(
      'UPDATE `User` SET AccountStatus = :status WHERE UserId = :uid',
      {'status': status, 'uid': found.rows.first.colByName('UserId')},
    );
    final row = await conn.execute(
      '$_tutorSelect WHERE tp.TutorID = :id',
      {'id': tutorId},
    );
    return _tutor(row.rows.first);
  }
}
