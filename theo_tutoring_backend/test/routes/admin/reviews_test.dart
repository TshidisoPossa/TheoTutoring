import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_reviews.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/reviews/[reviewId].dart' as detail_route;
import '../../../routes/admin/reviews/index.dart' as list_route;

// The admin Reviews page: GET /admin/reviews and GET /admin/reviews/<id>.

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeRepository implements AdminReviewsRepository {
  AdminReviewQuery? query;
  int? detailId;
  bool missing = false;

  @override
  Future<Map<String, Object?>> list(AdminReviewQuery query) async {
    this.query = query;
    return {
      'total': 1,
      'page': query.page,
      'pageSize': query.pageSize,
      'summary': {'totalReviews': 1},
      'distribution': {'5': 1, '4': 0, '3': 0, '2': 0, '1': 0},
      'needsAttention': <Object?>[],
      'reviews': [
        {'reviewId': 7, 'rating': 5},
      ],
    };
  }

  @override
  Future<Map<String, Object?>> detail(int reviewId) async {
    if (missing) throw const AdminReviewNotFound();
    detailId = reviewId;
    return {'reviewId': reviewId, 'reports': <Object?>[]};
  }
}

RequestContext _request(String path, {String method = 'GET'}) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {'Authorization': 'Bearer test'},
    ),
  );
  return context;
}

AdminResolver _as(String role) =>
    (_) async => AdminIdentity(id: 1, name: 'Ada', roleKey: role);

void main() {
  group('GET /admin/reviews', () {
    test('passes the filters on and returns the page', () async {
      final repository = _FakeRepository();
      final response = await list_route.handleAdminReviews(
        _request(
          '/admin/reviews?search=Thabo&rating=2&range=30d'
          '&withComment=true&sort=lowest&page=2&pageSize=20',
        ),
        adminResolver: _as('admin'),
        repository: repository,
      );

      expect(response.statusCode, 200);
      final query = repository.query!;
      expect(query.search, 'Thabo');
      expect(query.rating, 2);
      expect(query.days, 30);
      expect(query.withComment, isTrue);
      expect(query.sort, 'lowest');
      expect(query.page, 2);
      expect(query.pageSize, 20);
      final body = await response.json() as Map<String, dynamic>;
      expect(body['adminName'], 'Ada');
      expect((body['reviews'] as List).single, {'reviewId': 7, 'rating': 5});
    });

    test('defaults to every review, newest first', () async {
      final repository = _FakeRepository();
      await list_route.handleAdminReviews(
        _request('/admin/reviews'),
        adminResolver: _as('super_admin'),
        repository: repository,
      );
      final query = repository.query!;
      expect(query.rating, isNull);
      expect(query.days, isNull);
      expect(query.withComment, isFalse);
      expect(query.sort, 'newest');
      expect(query.page, 1);
      expect(query.pageSize, 10);
    });

    test('rejects bad filters with a 400', () async {
      for (final query in [
        'rating=6',
        'rating=abc',
        'range=1y',
        'sort=random',
        'page=0',
        'pageSize=500',
      ]) {
        final response = await list_route.handleAdminReviews(
          _request('/admin/reviews?$query'),
          adminResolver: _as('admin'),
          repository: _FakeRepository(),
        );
        expect(response.statusCode, 400, reason: query);
      }
    });

    test('Support admins can see reviews', () async {
      final response = await list_route.handleAdminReviews(
        _request('/admin/reviews'),
        adminResolver: _as('support_admin'),
        repository: _FakeRepository(),
      );
      expect(response.statusCode, 200);
    });

    test('roles without admin.reviews.read get a 403', () async {
      for (final role in ['application_reviewer', 'monitor_admin']) {
        final repository = _FakeRepository();
        final response = await list_route.handleAdminReviews(
          _request('/admin/reviews'),
          adminResolver: _as(role),
          repository: repository,
        );
        expect(response.statusCode, 403, reason: role);
        expect(repository.query, isNull);
      }
    });

    test('a bad sign-in token is a 401', () async {
      final response = await list_route.handleAdminReviews(
        _request('/admin/reviews'),
        adminResolver: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
        repository: _FakeRepository(),
      );
      expect(response.statusCode, 401);
    });

    test('only GET is allowed (the page is read-only)', () async {
      final response = await list_route.handleAdminReviews(
        _request('/admin/reviews', method: 'DELETE'),
        adminResolver: _as('super_admin'),
        repository: _FakeRepository(),
      );
      expect(response.statusCode, 405);
    });
  });

  group('GET /admin/reviews/<id>', () {
    test('returns the review details', () async {
      final repository = _FakeRepository();
      final response = await detail_route.handleAdminReviewDetail(
        _request('/admin/reviews/7'),
        '7',
        adminResolver: _as('admin'),
        repository: repository,
      );
      expect(response.statusCode, 200);
      expect(repository.detailId, 7);
      expect(await response.json(), {'reviewId': 7, 'reports': <Object?>[]});
    });

    test('an unknown review is a 404', () async {
      final response = await detail_route.handleAdminReviewDetail(
        _request('/admin/reviews/99'),
        '99',
        adminResolver: _as('admin'),
        repository: _FakeRepository()..missing = true,
      );
      expect(response.statusCode, 404);
    });

    test('a bad id is a 400', () async {
      final response = await detail_route.handleAdminReviewDetail(
        _request('/admin/reviews/x'),
        'x',
        adminResolver: _as('admin'),
        repository: _FakeRepository(),
      );
      expect(response.statusCode, 400);
    });

    test('roles without admin.reviews.read get a 403', () async {
      final response = await detail_route.handleAdminReviewDetail(
        _request('/admin/reviews/7'),
        '7',
        adminResolver: _as('monitor_admin'),
        repository: _FakeRepository(),
      );
      expect(response.statusCode, 403);
    });
  });
}
