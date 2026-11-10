import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
// Same imports as the route, so the exception types match.
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/student_dashboard.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';
import 'package:theo_tutoring_backend/student_reviews.dart';

import '../../../routes/students/lessons/[id]/review.dart' as review_route;

// POST /students/lessons/<id>/review with a fake identity and repository.

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeRepository implements StudentReviewsRepository {
  _FakeRepository({this.error});

  final Exception? error;
  String? uid;
  int? bookingId;
  ReviewInput? input;

  @override
  Future<SavedReview> submit(
    String firebaseUid,
    int bookingId,
    ReviewInput input,
  ) async {
    if (error != null) throw error!;
    uid = firebaseUid;
    this.bookingId = bookingId;
    this.input = input;
    return SavedReview(
      reviewId: 9,
      bookingId: bookingId,
      rating: input.rating,
      comment: input.comment,
      tutorAverage: 4.33,
      tutorReviewCount: 3,
    );
  }
}

RequestContext _request(String method, {Object? body}) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/students/lessons/41/review'),
      headers: {'Authorization': 'Bearer test'},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  return context;
}

Future<FirebaseUser> _student(String? _) async => const FirebaseUser(
  uid: 'student-uid',
  email: 'lerato@example.com',
  emailVerified: true,
);

void main() {
  Future<Response> post(
    Object? body, {
    String id = '41',
    _FakeRepository? repository,
    Future<FirebaseUser> Function(String?) tokenVerifier = _student,
  }) => review_route.handleLessonReview(
    _request('POST', body: body),
    id,
    tokenVerifier: tokenVerifier,
    repositoryFactory: () async => repository ?? _FakeRepository(),
  );

  group('POST /students/lessons/<id>/review', () {
    test('saves the review and returns the new tutor average', () async {
      final repository = _FakeRepository();
      final response = await post({
        'rating': 5,
        'comment': '  Explained derivatives clearly.  ',
      }, repository: repository);

      expect(response.statusCode, 201);
      expect(repository.uid, 'student-uid');
      expect(repository.bookingId, 41);
      expect(repository.input?.rating, 5);
      expect(repository.input?.comment, 'Explained derivatives clearly.');
      expect(await response.json(), {
        'reviewId': 9,
        'bookingId': 41,
        'rating': 5,
        'comment': 'Explained derivatives clearly.',
        'tutorAverage': 4.33,
        'tutorReviewCount': 3,
      });
    });

    test('the written review is optional', () async {
      final repository = _FakeRepository();
      final response = await post({'rating': 3}, repository: repository);
      expect(response.statusCode, 201);
      expect(repository.input?.comment, isNull);
      expect(repository.input?.highlights, isEmpty);
      expect(repository.input?.privateNote, isNull);
    });

    test('saves the badges in a fixed order and the private note', () async {
      final repository = _FakeRepository();
      final response = await post({
        'rating': 5,
        'highlights': [
          'Patient with questions',
          'Clear explanations',
          'Patient with questions',
        ],
        'privateNote': '  Please check the Meet link worked. ',
      }, repository: repository);
      expect(response.statusCode, 201);
      expect(repository.input?.highlights, [
        'Clear explanations',
        'Patient with questions',
      ]);
      expect(
        repository.input?.privateNote,
        'Please check the Meet link worked.',
      );
    });

    test('an unknown badge or a bad badge list is a 400', () async {
      final unknown = await post({
        'rating': 4,
        'highlights': ['Free snacks'],
      });
      expect(unknown.statusCode, 400);
      expect(await unknown.json(), {
        'error': '"Free snacks" is not one of the badges.',
      });
      final notAList = await post({
        'rating': 4,
        'highlights': 'Clear explanations',
      });
      expect(notAList.statusCode, 400);
    });

    test('a private note over 500 characters is a 400', () async {
      final response = await post({'rating': 4, 'privateNote': 'a' * 501});
      expect(response.statusCode, 400);
    });

    test('a rating outside 1-5 or not a whole number is a 400', () async {
      for (final rating in [0, 6, 4.5, '4', null]) {
        final response = await post({'rating': rating});
        expect(response.statusCode, 400, reason: 'rating $rating');
        expect(await response.json(), {
          'error': 'Please choose a rating from 1 to 5 stars.',
        });
      }
    });

    test('a public review over 500 characters is a 400', () async {
      final response = await post({'rating': 4, 'comment': 'a' * 501});
      expect(response.statusCode, 400);
      final ok = await post({'rating': 4, 'comment': 'a' * 500});
      expect(ok.statusCode, 201);
    });

    test('a body that is not JSON is a 400', () async {
      final response = await post('not an object');
      expect(response.statusCode, 400);
    });

    test('a bad booking id is a 400', () async {
      final response = await post({'rating': 4}, id: 'abc');
      expect(response.statusCode, 400);
    });

    test('a lesson that is not theirs is a 404', () async {
      final response = await post(
        {'rating': 4},
        repository: _FakeRepository(
          error: const LessonActionException(404, 'Lesson not found.'),
        ),
      );
      expect(response.statusCode, 404);
    });

    test('an unfinished or already reviewed lesson is a 409', () async {
      final response = await post(
        {'rating': 4},
        repository: _FakeRepository(
          error: const LessonActionException(
            409,
            'You have already reviewed this lesson.',
          ),
        ),
      );
      expect(response.statusCode, 409);
      expect(await response.json(), {
        'error': 'You have already reviewed this lesson.',
      });
    });

    test('a tutor or suspended student is a 403', () async {
      final response = await post(
        {'rating': 4},
        repository: _FakeRepository(error: const StudentDashboardDenied()),
      );
      expect(response.statusCode, 403);
    });

    test('an invalid sign-in token is a 401', () async {
      final response = await post(
        {'rating': 4},
        tokenVerifier: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
      );
      expect(response.statusCode, 401);
    });

    test('a database failure is a 500 without the details', () async {
      final response = await post(
        {'rating': 4},
        repository: _FakeRepository(error: Exception('db down')),
      );
      expect(response.statusCode, 500);
      expect(await response.json(), {
        'error': 'Could not save your review. Please try again.',
      });
    });

    test('only POST is allowed', () async {
      final response = await review_route.handleLessonReview(
        _request('GET'),
        '41',
        tokenVerifier: _student,
        repositoryFactory: () async => _FakeRepository(),
      );
      expect(response.statusCode, 405);
    });
  });
}
