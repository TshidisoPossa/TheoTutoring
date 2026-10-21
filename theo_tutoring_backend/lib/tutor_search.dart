import 'package:mysql_client/mysql_client.dart';

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
    final total = int.parse(countResult.rows.first.colByName('total')!);

    final tutorResult = await connection.execute(
      buildTutorSearchPageSql(filter),
      {...filter.parameters, 'limit': options.limit, 'offset': options.offset},
    );

    final tutors = <Map<String, Object?>>[];
    for (final row in tutorResult.rows) {
      final tutorId = int.parse(row.colByName('TutorID')!);
      final hourlyRate = row.colByName('HourlyRate');
      final averageRating = row.colByName('AverageRating');
      tutors.add({
        'tutorId': tutorId,
        'name': row.colByName('Name'),
        'profilePhoto': row.colByName('ProfilePhoto'),
        'bio': row.colByName('Bio'),
        'experience': row.colByName('Experience'),
        'hourlyRate': hourlyRate == null ? null : double.parse(hourlyRate),
        'averageRating': averageRating == null
            ? null
            : double.parse(averageRating),
        'reviewCount': int.parse(row.colByName('ReviewCount') ?? '0'),
        'subjects': <Map<String, Object?>>[],
      });
    }

    if (tutors.isNotEmpty) {
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
        'FROM TutorSubjects ts INNER JOIN Subjects s '
        'ON s.subjectId = ts.SubjectID '
        'WHERE ts.TutorID IN (${subjectSlots.join(', ')}) '
        'ORDER BY s.subjectName ASC',
        subjectParameters,
      );
      final tutorsById = {
        for (final tutor in tutors) tutor['tutorId']! as int: tutor,
      };
      for (final row in subjectResult.rows) {
        final tutor = tutorsById[int.parse(row.colByName('TutorID')!)];
        (tutor!['subjects']! as List<Map<String, Object?>>).add({
          'subjectId': int.parse(row.colByName('subjectId')!),
          'subjectName': row.colByName('subjectName'),
        });
      }
    }

    return TutorSearchResult(tutors: tutors, total: total);
  }
}

class TutorSearchFilter {
  const TutorSearchFilter(this.sql, this.parameters);

  final String sql;
  final Map<String, dynamic> parameters;
}

String buildTutorSearchCountSql(TutorSearchFilter filter) =>
    'SELECT COUNT(*) AS total FROM TutorProfile tp '
    'INNER JOIN `User` u ON u.UserId = tp.UserID ${filter.sql}';

String buildTutorSearchPageSql(TutorSearchFilter filter) =>
    '''
  SELECT tp.TutorID, u.Name, u.ProfilePhoto, tp.Bio, tp.Experience,
    (SELECT ps.TutoringRate FROM PlatformSettings ps
     WHERE ps.SettingsID = 1) AS HourlyRate,
    (SELECT AVG(r.Rating) FROM Reviews r
     WHERE r.TutorID = tp.TutorID) AS AverageRating,
    (SELECT COUNT(*) FROM Reviews r
     WHERE r.TutorID = tp.TutorID) AS ReviewCount
  FROM TutorProfile tp
  INNER JOIN `User` u ON u.UserId = tp.UserID
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
      SELECT 1 FROM TutorApplication ta
      WHERE ta.TutorID = tp.TutorID AND ta.Status = 'Approved'
    )
    ''',
  ];
  final parameters = <String, dynamic>{};

  if (options.subjectId != null) {
    clauses.add('''
      EXISTS (
        SELECT 1 FROM TutorSubjects filter_ts
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
          SELECT 1 FROM TutorSubjects search_ts
          INNER JOIN Subjects search_s ON search_s.subjectId = search_ts.SubjectID
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
