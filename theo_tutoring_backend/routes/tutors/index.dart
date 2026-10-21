import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/tutor_search.dart';

Future<Response> onRequest(RequestContext context) =>
    handleTutorSearch(context);

Future<Response> handleTutorSearch(
  RequestContext context, {
  Future<TutorSearchRepository> Function()? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }

  final options = _parseOptions(context.request.uri);
  if (options == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Invalid tutor search parameters.'},
    );
  }

  try {
    final repository = await (repositoryFactory ?? _defaultRepository)();
    final result = await repository.search(options);
    return Response.json(
      body: {
        'tutors': result.tutors,
        'page': options.page,
        'limit': options.limit,
        'total': result.total,
      },
    );
  } catch (error, stackTrace) {
    stderr.writeln('Tutor search failed: $error\n$stackTrace');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Tutors are temporarily unavailable.'},
    );
  }
}

Future<TutorSearchRepository> _defaultRepository() async =>
    MySqlTutorSearchRepository(await getConnection());

TutorSearchOptions? _parseOptions(Uri uri) {
  final parameters = uri.queryParametersAll;
  const allowed = {'query', 'subjectId', 'page', 'limit'};
  if (parameters.keys.any((key) => !allowed.contains(key)) ||
      parameters.values.any((values) => values.length != 1)) {
    return null;
  }

  String? value(String key) => parameters[key]?.single;
  final query = value('query')?.trim() ?? '';
  if (query.length > 200) return null;

  int? positiveInteger(String key, {int? defaultValue, int? maximum}) {
    final raw = value(key);
    if (raw == null) return defaultValue;
    if (!RegExp(r'^[0-9]+$').hasMatch(raw)) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1 || (maximum != null && parsed > maximum)) {
      return null;
    }
    return parsed;
  }

  final subjectId = positiveInteger('subjectId', maximum: 2147483647);
  final page = positiveInteger('page', defaultValue: 1, maximum: 2147483647);
  final limit = positiveInteger('limit', defaultValue: 20, maximum: 50);
  if ((value('subjectId') != null && subjectId == null) ||
      page == null ||
      limit == null) {
    return null;
  }

  return TutorSearchOptions(
    query: query,
    subjectId: subjectId,
    page: page,
    limit: limit,
  );
}
