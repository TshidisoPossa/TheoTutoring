import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/database.dart';

// The admin Reviews page (documentation: the administrator can "view
// reviews and user reports"). Read-only: oversight happens "without
// changing user data", so reviews are never edited or removed here.

/// Sort orders the Flutter page can ask for -> ORDER BY.
const adminReviewSorts = {
  'newest': 'r.Created_At DESC, r.Reviewid DESC',
  'oldest': 'r.Created_At ASC, r.Reviewid ASC',
  'lowest': 'r.Rating ASC, r.Created_At DESC, r.Reviewid DESC',
  'highest': 'r.Rating DESC, r.Created_At DESC, r.Reviewid DESC',
};

/// Date ranges the page can ask for, in days (null = all time).
const adminReviewRanges = {'all': null, '7d': 7, '30d': 30, '90d': 90};

/// A tutor is "needing attention" when their average is below this...
const needsAttentionBelow = 3.0;

/// ...over at least this many reviews.
const needsAttentionMinReviews = 3;

/// Filters for GET /admin/reviews.
class AdminReviewQuery {
  /// Creates the filters.
  const AdminReviewQuery({
    this.search,
    this.rating,
    this.days,
    this.withComment = false,
    this.sort = 'newest',
    this.page = 1,
    this.pageSize = 10,
  });

  /// Tutor, student or subject name.
  final String? search;

  /// Only reviews with this many stars (1-5), or null for all.
  final int? rating;

  /// Only reviews from the last [days] days, or null for all time.
  final int? days;

  /// Only reviews with a written comment.
  final bool withComment;

  /// A key of [adminReviewSorts].
  final String sort;

  /// 1-based page.
  final int page;

  /// Reviews per page.
  final int pageSize;
}

/// The review asked for does not exist.
class AdminReviewNotFound implements Exception {
  /// Creates the exception.
  const AdminReviewNotFound();
}

/// Reads reviews for the admin portal.
abstract interface class AdminReviewsRepository {
  /// One page of reviews plus the page's summary figures.
  Future<Map<String, Object?>> list(AdminReviewQuery query);

  /// One review with its booking, both people and any reports filed on the
  /// same booking. Throws [AdminReviewNotFound].
  Future<Map<String, Object?>> detail(int reviewId);
}

const _reviewFrom = '''
  FROM reviews r
  INNER JOIN tutorprofile tp ON tp.TutorID = r.TutorID
  INNER JOIN `user` tu ON tu.UserId = tp.UserID
  INNER JOIN studentprofile sp ON sp.StudentID = r.StudentID
  INNER JOIN `user` su ON su.UserId = sp.UserID
  LEFT JOIN booking b ON b.Booking_id = r.BookingID
  LEFT JOIN subjects s ON s.subjectId = b.SubjectID
''';

const _reviewColumns = '''
  SELECT r.Reviewid, r.Rating, r.`comment` AS Comment, r.BookingID,
    DATE_FORMAT(r.Created_At, '%Y-%m-%dT%H:%i:%s') AS CreatedAt,
    tp.TutorID, tu.Name AS TutorName, tu.ProfilePhoto AS TutorPhoto,
    sp.StudentID, su.Name AS StudentName, su.ProfilePhoto AS StudentPhoto,
    s.subjectName,
    (SELECT COUNT(*) FROM report rp WHERE rp.BookingID = r.BookingID)
      AS ReportCount
''';

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int _int(String? value) => int.tryParse(value ?? '') ?? 0;

double _double(String? value) => double.tryParse(value ?? '') ?? 0;

Map<String, Object?> _review(ResultSetRow row) => {
  'reviewId': _int(row.str('Reviewid')),
  'rating': _int(row.str('Rating')),
  'comment': _blankToNull(row.str('Comment')),
  'bookingId': int.tryParse(row.str('BookingID') ?? ''),
  'createdAt': row.str('CreatedAt'),
  'subject': row.str('subjectName'),
  'tutor': {
    'tutorId': _int(row.str('TutorID')),
    'name': row.str('TutorName'),
    'photoUrl': _blankToNull(row.str('TutorPhoto')),
  },
  'student': {
    'studentId': _int(row.str('StudentID')),
    'name': row.str('StudentName'),
    'photoUrl': _blankToNull(row.str('StudentPhoto')),
  },
  'reportCount': _int(row.str('ReportCount')),
};

/// [AdminReviewsRepository] on MySQL.
class MySqlAdminReviewsRepository implements AdminReviewsRepository {
  /// Creates the repository; [connection] defaults to the shared one.
  MySqlAdminReviewsRepository({Future<MySQLConnection> Function()? connection})
    : _connection = connection ?? getConnection;

  final Future<MySQLConnection> Function() _connection;

  @override
  Future<Map<String, Object?>> list(AdminReviewQuery query) async {
    final conn = await _connection();
    final where = <String>['1 = 1'];
    final params = <String, dynamic>{};
    final search = query.search?.trim();
    if (search != null && search.isNotEmpty) {
      where.add(
        '(tu.Name LIKE :q OR su.Name LIKE :q OR s.subjectName LIKE :q)',
      );
      params['q'] = '%${search.replaceAll(RegExp(r'[%_\\]'), '')}%';
    }
    if (query.rating != null) {
      where.add('r.Rating = :rating');
      params['rating'] = query.rating;
    }
    if (query.days != null) {
      where.add('r.Created_At >= NOW() - INTERVAL :days DAY');
      params['days'] = query.days;
    }
    if (query.withComment) {
      where.add("TRIM(COALESCE(r.`comment`, '')) <> ''");
    }
    final clause = where.join(' AND ');
    final orderBy = adminReviewSorts[query.sort] ?? adminReviewSorts['newest'];

    final total = await conn.execute(
      'SELECT COUNT(*) AS n $_reviewFrom WHERE $clause',
      params,
    );
    final rows = await conn.execute(
      '$_reviewColumns $_reviewFrom WHERE $clause '
      'ORDER BY $orderBy LIMIT :limit OFFSET :offset',
      {
        ...params,
        'limit': query.pageSize,
        'offset': (query.page - 1) * query.pageSize,
      },
    );

    // The figures above the table cover every review, not just this page
    final summary = await conn.execute('''
      SELECT COUNT(*) AS Total,
        ROUND(AVG(Rating), 2) AS Average,
        COALESCE(SUM(Rating <= 2 AND Created_At >= NOW() - INTERVAL 30 DAY),
          0) AS LowRecent,
        COALESCE(SUM(Created_At >= DATE_FORMAT(CURDATE(), '%Y-%m-01')), 0)
          AS ThisMonth,
        COALESCE(SUM(Rating = 5), 0) AS Stars5,
        COALESCE(SUM(Rating = 4), 0) AS Stars4,
        COALESCE(SUM(Rating = 3), 0) AS Stars3,
        COALESCE(SUM(Rating = 2), 0) AS Stars2,
        COALESCE(SUM(Rating = 1), 0) AS Stars1
      FROM reviews
    ''');
    final s = summary.rows.first;

    final attention = await conn.execute(
      '''
      SELECT tp.TutorID, u.Name, u.ProfilePhoto, u.AccountStatus,
        ROUND(AVG(r.Rating), 2) AS Average, COUNT(*) AS ReviewCount
      FROM reviews r
      INNER JOIN tutorprofile tp ON tp.TutorID = r.TutorID
      INNER JOIN `user` u ON u.UserId = tp.UserID
      GROUP BY tp.TutorID, u.Name, u.ProfilePhoto, u.AccountStatus
      HAVING COUNT(*) >= :minReviews AND AVG(r.Rating) < :below
      ORDER BY Average ASC, ReviewCount DESC
      LIMIT 5
      ''',
      {'minReviews': needsAttentionMinReviews, 'below': needsAttentionBelow},
    );

    return {
      'total': _int(total.rows.first.str('n')),
      'page': query.page,
      'pageSize': query.pageSize,
      'summary': {
        'totalReviews': _int(s.str('Total')),
        'averageRating': _double(s.str('Average')),
        'lowRatingsLast30Days': _int(s.str('LowRecent')),
        'reviewsThisMonth': _int(s.str('ThisMonth')),
      },
      'distribution': {
        for (var stars = 5; stars >= 1; stars--)
          '$stars': _int(s.str('Stars$stars')),
      },
      'needsAttention': [
        for (final row in attention.rows)
          {
            'tutorId': _int(row.str('TutorID')),
            'name': row.str('Name'),
            'photoUrl': _blankToNull(row.str('ProfilePhoto')),
            'status': row.str('AccountStatus'),
            'averageRating': _double(row.str('Average')),
            'reviewCount': _int(row.str('ReviewCount')),
          },
      ],
      'reviews': [for (final row in rows.rows) _review(row)],
    };
  }

  @override
  Future<Map<String, Object?>> detail(int reviewId) async {
    final conn = await _connection();
    final result = await conn.execute(
      '''
      $_reviewColumns,
        tu.Email AS TutorEmail, tu.AccountStatus AS TutorStatus,
        tp.AveRate AS TutorAverage,
        (SELECT COUNT(*) FROM reviews r2 WHERE r2.TutorID = tp.TutorID)
          AS TutorReviewCount,
        su.Email AS StudentEmail, sp.Institution AS StudentInstitution,
        DATE_FORMAT(b.Date, '%Y-%m-%d') AS SessionDate,
        TIME_FORMAT(b.StartTime, '%H:%i') AS StartTime,
        TIME_FORMAT(b.EndTime, '%H:%i') AS EndTime,
        b.Status AS BookingStatus,
        r.Highlights, r.PrivateNote
      $_reviewFrom
      WHERE r.Reviewid = :id
      ''',
      {'id': reviewId},
    );
    if (result.rows.isEmpty) throw const AdminReviewNotFound();
    final row = result.rows.first;
    final review = _review(row);
    final bookingId = review['bookingId'] as int?;

    final reports = bookingId == null
        ? null
        : await conn.execute(
            '''
            SELECT rp.ReportID, rp.Category, rp.Reason, rp.Status,
              DATE_FORMAT(rp.Created_at, '%Y-%m-%dT%H:%i:%s') AS CreatedAt,
              ru.Name AS ReporterName, ru.Role AS ReporterRole
            FROM report rp
            INNER JOIN `user` ru ON ru.UserId = rp.ReporterID
            WHERE rp.BookingID = :bookingId
            ORDER BY rp.Created_at DESC
            ''',
            {'bookingId': bookingId},
          );

    return {
      ...review,
      // From the Leave a Review page; admin only (migration 011)
      'highlights': [
        for (final part in (row.str('Highlights') ?? '').split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ],
      'privateNote': _blankToNull(row.str('PrivateNote')),
      'tutor': {
        ...review['tutor']! as Map<String, Object?>,
        'email': row.str('TutorEmail'),
        'status': row.str('TutorStatus'),
        'averageRating': _double(row.str('TutorAverage')),
        'reviewCount': _int(row.str('TutorReviewCount')),
      },
      'student': {
        ...review['student']! as Map<String, Object?>,
        'email': row.str('StudentEmail'),
        'institution': _blankToNull(row.str('StudentInstitution')),
      },
      'booking': bookingId == null
          ? null
          : {
              'bookingId': bookingId,
              'date': row.str('SessionDate'),
              'startTime': row.str('StartTime'),
              'endTime': row.str('EndTime'),
              'status': row.str('BookingStatus'),
            },
      'reports': [
        for (final report in reports?.rows ?? const <ResultSetRow>[])
          {
            'reportId': _int(report.str('ReportID')),
            'category': report.str('Category'),
            'reason': report.str('Reason'),
            'status': report.str('Status'),
            'createdAt': report.str('CreatedAt'),
            'reporterName': report.str('ReporterName'),
            'reporterRole': report.str('ReporterRole'),
          },
      ],
    };
  }
}
