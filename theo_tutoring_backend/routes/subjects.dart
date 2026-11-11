import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';

/// Public reference data only; no user or private records are returned.
/// The catalogue must be readable before a tutor has a Firebase account.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Only GET requests are supported.'},
    );
  }

  try {
    final connection = await getConnection();
    final result = await connection.execute(
      'SELECT subjectId, subjectName FROM subjects ORDER BY subjectName',
    );
    return Response.json(
      body: {
        'subjects': [
          for (final row in result.rows)
            {
              'subjectId': int.parse(row.reqStr('subjectId')),
              'subjectName': row.str('subjectName'),
            },
        ],
      },
    );
  } catch (error, stackTrace) {
    stderr
      ..writeln('Subject catalogue lookup failed: $error')
      ..writeln(stackTrace);
    return Response.json(
      statusCode: 500,
      body: {'error': 'Subjects are temporarily unavailable.'},
    );
  }
}
