import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/session_rate.dart';

class TutorSearchOptions {
  const TutorSearchOptions({
    required this.query,
    required this.subjectId,
    required this.page,
    required this.limit,
  });

  final String query;
  final int? subjectId;
  final int page;
  final int limit;

  int get offset => (page - 1) * limit;
}

class TutorSearchResult {
  const TutorSearchResult({required this.tutors, required this.total});

  final List<Map<String, Object?>> tutors;
  final int total;
}

abstract interface class TutorSearchRepository {
  Future<TutorSearchResult> search(TutorSearchOptions options);
}

class MySqlTutorSearchRepository implements TutorSearchRepository {
  MySqlTutorSearchRepository(this.connection);

  final MySQLConnection connection;

  @override
  Future<TutorSearchResult> search(TutorSearchOptions options) async {
    final filter = buildTutorSearchFilter(options);
    final countResult = await connection.execute(
      buildTutorSearchCountSql(filter),
      filter.parameters,
    );
    final total = int.parse(countResult.rows.first.reqStr('total'));

    final tutorResult = await connection.execute(
      buildTutorSearchPageSql(filter),
      {...filter.parameters, 'limit': options.limit, 'offset': options.offset},
    );
    final tutors = [for (final row in tutorResult.rows) _tutorFromRow(row)];
    await _attachSubjects(tutors);
    return TutorSearchResult(tutors: tutors, total: total);
  }

  /// One approved, active tutor in the same shape as a search result, or
  /// null when there is no such tutor (the student Tutor Profile page).
  Future<Map<String, Object?>?> findById(int tutorId) async {
    final filter = buildTutorSearchFilter(
      const TutorSearchOptions(query: '', subjectId: null, page: 1, limit: 1),
    );
    final result = await connection.execute(
      buildTutorSearchPageSql(
        TutorSearchFilter(
          '${filter.sql} AND tp.TutorID = :tutorId',
          filter.parameters,
        ),
      ),
      {...filter.parameters, 'tutorId': tutorId, 'limit': 1, 'offset': 0},
    );
    if (result.rows.isEmpty) return null;
    final tutors = [_tutorFromRow(result.rows.first)];
    await _attachSubjects(tutors);
    return tutors.single;
  }

  Map<String, Object?> _tutorFromRow(ResultSetRow row) {
    final hourlyRate = row.str('HourlyRate');
    final averageRating = row.str('AverageRating');
    return {
      'tutorId': int.parse(row.reqStr('TutorID')),
      // The tutor's User ID: the ID the chat routes address tutors by.
      'userId': int.parse(row.reqStr('UserID')),
      'name': row.str('Name'),
      'profilePhoto': row.str('ProfilePhoto'),
      'bio': row.str('Bio'),
      'experience': row.str('Experience'),
      'qualification': row.str('Qualification'),
      'hourlyRate': hourlyRate == null ? null : double.parse(hourlyRate),
      'averageRating': averageRating == null
          ? null
          : double.parse(averageRating),
      'reviewCount': int.parse(row.str('ReviewCount') ?? '0'),
      'subjects': <Map<String, Object?>>[],
    };
  }

  Future<void> _attachSubjects(List<Map<String, Object?>> tutors) async {
    if (tutors.isEmpty) return;
    final subjectParameters = <String, dynamic>{};
    final subjectSlots = <String>[];
    for (var i = 0; i < tutors.length; i++) {
      final id = tutors[i]['tutorId']! as int;
      final key = 'tutor$i';
      subjectParameters[key] = id;
      subjectSlots.add(':$key');
    }
    final subjectResult = await connection.execute(
      'SELECT ts.TutorID, s.subjectId, s.subjectName '
      'FROM tutorsubjects ts INNER JOIN subjects s '
      'ON s.subjectId = ts.SubjectID '
      'WHERE ts.TutorID IN (${subjectSlots.join(', ')}) '
      'ORDER BY s.subjectName ASC',
      subjectParameters,
    );
    final tutorsById = {
      for (final tutor in tutors) tutor['tutorId']! as int: tutor,
    };
    for (final row in subjectResult.rows) {
      final tutor = tutorsById[int.parse(row.reqStr('TutorID'))];
      (tutor!['subjects']! as List<Map<String, Object?>>).add({
        'subjectId': int.parse(row.reqStr('subjectId')),
        'subjectName': row.str('subjectName'),
      });
    }
  }
}

class TutorSearchFilter {
  const TutorSearchFilter(this.sql, this.parameters);

  final String sql;
  final Map<String, dynamic> parameters;
}

String buildTutorSearchCountSql(TutorSearchFilter filter) =>
    'SELECT COUNT(*) AS total FROM tutorprofile tp '
    'INNER JOIN `user` u ON u.UserId = tp.UserID ${filter.sql}';

String buildTutorSearchPageSql(TutorSearchFilter filter) =>
    '''
  SELECT tp.TutorID, tp.UserID, u.Name, u.ProfilePhoto, tp.Bio, tp.Experience,
    (SELECT q.Degree FROM qualification q
     WHERE q.TutorID = tp.TutorID
     ORDER BY q.QualificationID DESC LIMIT 1) AS Qualification,
    $currentSessionRateSubquery AS HourlyRate,
    (SELECT AVG(r.Rating) FROM reviews r
     WHERE r.TutorID = tp.TutorID) AS AverageRating,
    (SELECT COUNT(*) FROM reviews r
     WHERE r.TutorID = tp.TutorID) AS ReviewCount
  FROM tutorprofile tp
  INNER JOIN `user` u ON u.UserId = tp.UserID
  ${filter.sql}
  ORDER BY u.Name ASC, tp.TutorID ASC
  LIMIT :limit OFFSET :offset
  ''';

TutorSearchFilter buildTutorSearchFilter(TutorSearchOptions options) {
  final clauses = <String>[
    "u.Role = 'tutor'",
    "u.AccountStatus = 'Active'",
    "tp.VerificationStat = 'Approved'",
    '''
    EXISTS (
      SELECT 1 FROM tutorapplication ta
      WHERE ta.TutorID = tp.TutorID AND ta.Status = 'Approved'
    )
    ''',
  ];
  final parameters = <String, dynamic>{};

  if (options.subjectId != null) {
    clauses.add('''
      EXISTS (
        SELECT 1 FROM tutorsubjects filter_ts
        WHERE filter_ts.TutorID = tp.TutorID
          AND filter_ts.SubjectID = :subjectId
      )
      ''');
    parameters['subjectId'] = options.subjectId;
  }

  if (options.query.isNotEmpty) {
    clauses.add('''
      (
        LOWER(u.Name) LIKE :searchName ESCAPE '!'
        OR LOWER(COALESCE(tp.Bio, '')) LIKE :searchBio ESCAPE '!'
        OR EXISTS (
          SELECT 1 FROM tutorsubjects search_ts
          INNER JOIN subjects search_s ON search_s.subjectId = search_ts.SubjectID
          WHERE search_ts.TutorID = tp.TutorID
            AND LOWER(search_s.subjectName) LIKE :searchSubject ESCAPE '!'
        )
      )
      ''');
    final pattern = '%${_escapeLike(options.query.toLowerCase())}%';
    parameters['searchName'] = pattern;
    parameters['searchBio'] = pattern;
    parameters['searchSubject'] = pattern;
  }

  return TutorSearchFilter('WHERE ${clauses.join(' AND ')}', parameters);
}

String _escapeLike(String value) =>
    value.replaceAll('!', '!!').replaceAll('%', '!%').replaceAll('_', '!_');
