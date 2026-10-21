import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/tutor_search.dart';

import '../../../routes/tutors/index.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _FakeRepository implements TutorSearchRepository {
  _FakeRepository(this.result);

  final TutorSearchResult result;
  TutorSearchOptions? receivedOptions;

  @override
  Future<TutorSearchResult> search(TutorSearchOptions options) async {
    receivedOptions = options;
    return result;
  }
}

class _ErrorRepository implements TutorSearchRepository {
  @override
  Future<TutorSearchResult> search(TutorSearchOptions options) =>
      Future.error(Exception('database detail'));
}

void main() {
  late RequestContext context;
  late Request request;

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.get);
    when(() => request.uri).thenReturn(Uri.parse('/tutors'));
  });

  group('GET /tutors', () {
    test('uses defaults and serializes repository results', () async {
      final repository = _FakeRepository(
        const TutorSearchResult(tutors: <Map<String, Object?>>[], total: 0),
      );
      final response = await route.handleTutorSearch(
        context,
        repositoryFactory: () async => repository,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(repository.receivedOptions?.page, 1);
      expect(repository.receivedOptions?.limit, 20);
      expect(jsonDecode(await response.body()), {
        'tutors': <Object?>[],
        'page': 1,
        'limit': 20,
        'total': 0,
      });
    });

    test('passes validated query, subject and pagination values', () async {
      when(() => request.uri).thenReturn(
        Uri.parse('/tutors?query=math&subjectId=4&page=2&limit=30'),
      );
      final repository = _FakeRepository(
        const TutorSearchResult(tutors: <Map<String, Object?>>[], total: 37),
      );

      await route.handleTutorSearch(
        context,
        repositoryFactory: () async => repository,
      );

      expect(repository.receivedOptions?.query, 'math');
      expect(repository.receivedOptions?.subjectId, 4);
      expect(repository.receivedOptions?.page, 2);
      expect(repository.receivedOptions?.limit, 30);
    });

    for (final query in [
      'page=0',
      'page=-1',
      'limit=51',
      'limit=0',
      'subjectId=abc',
      'subjectId=0',
      'page=1&page=2',
      'other=1',
    ]) {
      test('rejects $query', () async {
        when(() => request.uri).thenReturn(Uri.parse('/tutors?$query'));

        final response = await route.handleTutorSearch(
          context,
          repositoryFactory: () async => _ErrorRepository(),
        );

        expect(response.statusCode, HttpStatus.badRequest);
      });
    }

    test('returns 405 for non-GET requests', () async {
      when(() => request.method).thenReturn(HttpMethod.post);
      final response = await route.handleTutorSearch(context);
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });

    test('returns generic 500 when repository fails', () async {
      final response = await route.handleTutorSearch(
        context,
        repositoryFactory: () async => _ErrorRepository(),
      );
      expect(response.statusCode, HttpStatus.internalServerError);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], contains('unavailable'));
      expect((await response.body()).contains('database detail'), isFalse);
    });

    test('preserves nullable profile, rate, and rating values', () async {
      final repository = _FakeRepository(
        const TutorSearchResult(
          tutors: [
            {
              'tutorId': 7,
              'name': 'Tutor Example',
              'profilePhoto': null,
              'bio': null,
              'experience': null,
              'hourlyRate': null,
              'averageRating': null,
              'reviewCount': 0,
              'subjects': [
                {'subjectId': 3, 'subjectName': 'Mathematics'},
              ],
            },
          ],
          total: 1,
        ),
      );
      final response = await route.handleTutorSearch(
        context,
        repositoryFactory: () async => repository,
      );
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      final tutor = (body['tutors'] as List).single as Map<String, dynamic>;
      expect(tutor['profilePhoto'], isNull);
      expect(tutor['bio'], isNull);
      expect(tutor['experience'], isNull);
      expect(tutor['hourlyRate'], isNull);
      expect(tutor['averageRating'], isNull);
      expect(tutor['reviewCount'], 0);
    });
  });

  group('tutor search SQL filters', () {
    test('requires all three eligibility conditions via approved EXISTS', () {
      final filter = buildTutorSearchFilter(
        const TutorSearchOptions(
          query: '',
          subjectId: null,
          page: 1,
          limit: 20,
        ),
      );
      expect(filter.sql, contains("u.Role = 'tutor'"));
      expect(filter.sql, contains("u.AccountStatus = 'Active'"));
      expect(filter.sql, contains("tp.VerificationStat = 'Approved'"));
      expect(filter.sql, contains('EXISTS'));
      expect(filter.sql, contains("ta.Status = 'Approved'"));
      expect(filter.sql, contains('ta.TutorID = tp.TutorID'));
      expect(filter.sql, isNot(contains('JOIN TutorApplication')));
    });

    test('uses parameterized subject and escaped literal text filters', () {
      final filter = buildTutorSearchFilter(
        const TutorSearchOptions(
          query: r'Math_%!',
          subjectId: 9,
          page: 1,
          limit: 20,
        ),
      );
      expect(filter.sql, contains('filter_ts.SubjectID = :subjectId'));
      expect(filter.sql, contains('LOWER(u.Name) LIKE :searchName'));
      expect(filter.sql, contains('LOWER(COALESCE(tp.Bio'));
      expect(filter.sql, contains('search_s.subjectName'));
      expect(filter.parameters, {
        'subjectId': 9,
        'searchName': r'%math!_!%!!%',
        'searchBio': r'%math!_!%!!%',
        'searchSubject': r'%math!_!%!!%',
      });
    });

    test('count and page share the same filters and page order is stable', () {
      final filter = buildTutorSearchFilter(
        const TutorSearchOptions(
          query: 'science',
          subjectId: 8,
          page: 3,
          limit: 15,
        ),
      );
      final countSql = buildTutorSearchCountSql(filter);
      final pageSql = buildTutorSearchPageSql(filter);
      expect(countSql, contains(filter.sql));
      expect(pageSql, contains(filter.sql));
      expect(pageSql, contains('ORDER BY u.Name ASC, tp.TutorID ASC'));
      expect(pageSql, contains('LIMIT :limit OFFSET :offset'));
      expect(pageSql, contains('AS HourlyRate'));
      expect(pageSql, contains('AS AverageRating'));
      expect(pageSql, contains('AS ReviewCount'));
      expect(pageSql, contains('WHERE ps.SettingsID = 1'));
      expect(pageSql, contains('SELECT AVG(r.Rating)'));
      expect(pageSql, contains('SELECT COUNT(*) FROM Reviews'));
    });
  });
}
