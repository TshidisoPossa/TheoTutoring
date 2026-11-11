import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

// "Report a Problem" on the tutor Profile. The report is saved in the Report
// table (migration 010 adds Category) and the admin reads it with
// GET /admin/reports.
//
//   GET  /TutorLandingpage/reports/students  students the tutor may report
//   POST /TutorLandingpage/reports           {"category", "description",
//                                             "studentUserId" (Student issues)}

/// The categories in the tutor's dropdown, as stored in Report.Category.
const tutorReportCategories = ['Payments & Payouts', 'Student issues', 'Other'];

/// The category that is about one of the tutor's students.
const studentIssuesCategory = 'Student issues';

/// Shortest description allowed.
const minReportDescription = 10;

/// Longest description allowed.
const maxReportDescription = 1000;

/// A student who has booked the tutor (User.UserId, for Report.ReportedUserID).
typedef ReportableStudent = ({int userId, String name, String? photo});

/// A report the tutor may not file; [message] is for the tutor.
class TutorReportException implements Exception {
  /// Creates the exception.
  const TutorReportException(this.statusCode, this.message);

  /// HTTP status to answer with.
  final int statusCode;

  /// Shown to the tutor.
  final String message;
}

/// Where tutor reports are saved (MySQL in the app, a fake in tests).
abstract interface class TutorReportRepository {
  /// Students who have booked lessons with the tutor, by name.
  Future<List<ReportableStudent>> studentsOf(int tutorId);

  /// Saves the report and returns its ReportID. Throws a
  /// [TutorReportException] when the student has not booked the tutor or is
  /// already reported and the admin has not resolved it yet.
  Future<int> file({
    required int tutorId,
    required String category,
    required String description,
    int? studentUserId,
  });
}

/// Reports in the Report table.
class MySqlTutorReportRepository implements TutorReportRepository {
  /// Uses the shared connection unless a test passes its own.
  MySqlTutorReportRepository({
    Future<MySQLConnection> Function() connectionFactory = getConnection,
  }) : _connect = connectionFactory;

  final Future<MySQLConnection> Function() _connect;

  @override
  Future<List<ReportableStudent>> studentsOf(int tutorId) async {
    final result = await (await _connect()).execute(
      '''
      SELECT DISTINCT u.UserId, u.Name, u.ProfilePhoto
      FROM Booking b
      INNER JOIN StudentProfile sp ON sp.StudentID = b.StudentID
      INNER JOIN `User` u ON u.UserId = sp.UserID
      WHERE b.TutorID = :tutorId
      ORDER BY u.Name, u.UserId
      ''',
      {'tutorId': tutorId},
    );
    return [
      for (final row in result.rows)
        (
          userId: int.parse(row.reqStr('UserId')),
          name: row.str('Name') ?? 'Student',
          photo: row.str('ProfilePhoto'),
        ),
    ];
  }

  @override
  Future<int> file({
    required int tutorId,
    required String category,
    required String description,
    int? studentUserId,
  }) async {
    final conn = await _connect();
    final tutor = await conn.execute(
      'SELECT UserID FROM TutorProfile WHERE TutorID = :tutorId LIMIT 1',
      {'tutorId': tutorId},
    );
    if (tutor.rows.isEmpty) {
      throw const TutorReportException(
        HttpStatus.notFound,
        'No tutor profile was found for this account.',
      );
    }
    final reporterId = int.parse(tutor.rows.first.reqStr('UserID'));

    if (studentUserId != null) {
      final booked = await conn.execute(
        '''
        SELECT 1
        FROM Booking b
        INNER JOIN StudentProfile sp ON sp.StudentID = b.StudentID
        WHERE b.TutorID = :tutorId AND sp.UserID = :studentUserId
        LIMIT 1
        ''',
        {'tutorId': tutorId, 'studentUserId': studentUserId},
      );
      if (booked.rows.isEmpty) {
        throw const TutorReportException(
          HttpStatus.badRequest,
          'You can only report students who have booked lessons with you.',
        );
      }
      // One unresolved report per student, so a double tap does not file
      // it twice.
      final open = await conn.execute(
        '''
        SELECT 1 FROM Report
        WHERE ReporterID = :reporterId
          AND ReportedUserID = :studentUserId
          AND Status <> 'Resolved'
        LIMIT 1
        ''',
        {'reporterId': reporterId, 'studentUserId': studentUserId},
      );
      if (open.rows.isNotEmpty) {
        throw const TutorReportException(
          HttpStatus.conflict,
          'You have already reported this student. The admin team is '
          'looking into it.',
        );
      }
    }

    final inserted = await conn.execute(
      '''
      INSERT INTO Report (ReporterID, ReportedUserID, Category, Reason)
      VALUES (:reporterId, :studentUserId, :category, :description)
      ''',
      {
        'reporterId': reporterId,
        'studentUserId': studentUserId,
        'category': category,
        'description': description,
      },
    );
    return inserted.lastInsertID.toInt(); // BigInt cannot go into JSON
  }
}

/// GET /TutorLandingpage/reports/students → {"students": [{"userId",
/// "name", "photo"}]}, for the Student issues dropdown.
Future<Response> handleReportableStudents(
  RequestContext context, {
  required int tutorId,
  TutorReportRepository? repository,
}) async {
  if (context.request.method != HttpMethod.get) {
    return jsonError(
      HttpStatus.methodNotAllowed,
      'Only GET requests are supported.',
    );
  }
  try {
    final students = await (repository ?? MySqlTutorReportRepository())
        .studentsOf(tutorId);
    return Response.json(
      body: {
        'students': [
          for (final s in students)
            {'userId': s.userId, 'name': s.name, 'photo': s.photo},
        ],
      },
    );
  } catch (error) {
    stderr.writeln('Loading reportable students failed: $error');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not load your students. Please try again.',
    );
  }
}

/// POST /TutorLandingpage/reports → {"reportId": 7, "message": "..."}.
Future<Response> handleFileTutorReport(
  RequestContext context, {
  required int tutorId,
  TutorReportRepository? repository,
}) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(
      HttpStatus.methodNotAllowed,
      'Only POST requests are supported.',
    );
  }

  final String category;
  final String description;
  int? studentUserId;
  try {
    final body = await readJsonObject(context);
    final rawCategory = optionalString(body, 'category', maxLength: 40);
    if (rawCategory == null || !tutorReportCategories.contains(rawCategory)) {
      return jsonError(HttpStatus.badRequest, 'Choose a category.');
    }
    category = rawCategory;

    final rawDescription = optionalString(
      body,
      'description',
      maxLength: maxReportDescription,
    );
    if (rawDescription == null ||
        rawDescription.length < minReportDescription) {
      return jsonError(
        HttpStatus.badRequest,
        'Describe the problem in at least $minReportDescription characters.',
      );
    }
    description = rawDescription;

    if (category == studentIssuesCategory) {
      final rawStudent = body['studentUserId'];
      if (rawStudent is! int || rawStudent <= 0) {
        return jsonError(
          HttpStatus.badRequest,
          'Choose the student this report is about.',
        );
      }
      studentUserId = rawStudent;
    }
  } on FormatException catch (error) {
    return jsonError(HttpStatus.badRequest, error.message);
  }

  try {
    final reportId = await (repository ?? MySqlTutorReportRepository()).file(
      tutorId: tutorId,
      category: category,
      description: description,
      studentUserId: studentUserId,
    );
    return Response.json(
      body: {
        'reportId': reportId,
        'message': 'Report sent. The admin team will look into it.',
      },
    );
  } on TutorReportException catch (error) {
    return jsonError(error.statusCode, error.message);
  } catch (error) {
    stderr.writeln('Saving a tutor report failed: $error');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not send your report. Please try again.',
    );
  }
}
