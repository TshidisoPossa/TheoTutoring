import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_reports.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/reports/index.dart' as route;

// The admin Reports page: GET /admin/reports.

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeRepository implements AdminReportRepository {
  int calls = 0;
  String? status;
  String? category;
  int? page;
  int? pageSize;
  Error? failure;

  @override
  Future<Map<String, Object?>> list({
    required int page,
    required int pageSize,
    String? status,
    String? category,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    this.status = status;
    this.category = category;
    this.page = page;
    this.pageSize = pageSize;
    return {
      'total': 1,
      'page': page,
      'pageSize': pageSize,
      'reports': [
        {'reportId': 3, 'category': null},
      ],
    };
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

Future<Response> _get(
  String path,
  _FakeRepository repository, {
  AdminResolver? resolver,
  String method = 'GET',
}) => route.handleAdminReports(
  _request(path, method: method),
  adminResolver: resolver ?? _as('support_admin'),
  repository: repository,
);

void main() {
  group('GET /admin/reports', () {
    test('passes the filters on and returns the page', () async {
      final repository = _FakeRepository();
      final response = await _get(
        '/admin/reports?status=under-review&category=Student%20issues'
        '&page=2&pageSize=50',
        repository,
      );

      expect(response.statusCode, 200);
      expect(repository.status, 'Under review');
      expect(repository.category, 'Student issues');
      expect(repository.page, 2);
      expect(repository.pageSize, 50);
      final body = await response.json() as Map<String, dynamic>;
      expect(body['adminName'], 'Ada');
      expect(body['total'], 1);
      expect((body['reports'] as List).single, {
        'reportId': 3,
        'category': null,
      });
    });

    test('defaults to every report, page 1, 20 per page', () async {
      final repository = _FakeRepository();
      final response = await _get('/admin/reports', repository);

      expect(response.statusCode, 200);
      expect(repository.status, isNull);
      expect(repository.category, isNull);
      expect(repository.page, 1);
      expect(repository.pageSize, 20);
    });

    test('rejects bad query parameters with a 400', () async {
      for (final query in [
        'status=closed',
        'category=Nonsense',
        'page=0',
        'page=abc',
        'pageSize=0',
        'pageSize=101',
        'pageSize=abc',
      ]) {
        final repository = _FakeRepository();
        final response = await _get('/admin/reports?$query', repository);
        expect(response.statusCode, 400, reason: query);
        expect(repository.calls, 0, reason: query);
      }
    });

    test('allows roles that have admin.reports.read', () async {
      for (final role in [
        'super_admin',
        'admin',
        'finance_admin',
        'support_admin',
      ]) {
        final response = await _get(
          '/admin/reports',
          _FakeRepository(),
          resolver: _as(role),
        );
        expect(response.statusCode, 200, reason: role);
      }
    });

    test('refuses roles without it and never reads reports', () async {
      for (final role in [
        'application_reviewer',
        'monitor_admin',
        'unknown_role',
      ]) {
        final repository = _FakeRepository();
        final response = await _get(
          '/admin/reports',
          repository,
          resolver: _as(role),
        );
        expect(response.statusCode, 403, reason: role);
        expect(repository.calls, 0, reason: role);
      }
    });

    test('answers 401 when the token is rejected', () async {
      final repository = _FakeRepository();
      final response = await _get(
        '/admin/reports',
        repository,
        resolver: (_) async => throw const AuthTokenException('Bad token'),
      );

      expect(response.statusCode, 401);
      expect(repository.calls, 0);
    });

    test('answers 405 to anything but GET', () async {
      for (final method in ['POST', 'PUT', 'DELETE']) {
        final repository = _FakeRepository();
        final response = await _get(
          '/admin/reports',
          repository,
          method: method,
        );
        expect(response.statusCode, 405, reason: method);
        expect(repository.calls, 0, reason: method);
      }
    });

    test('answers 500 when the repository fails', () async {
      final repository = _FakeRepository()..failure = StateError('db down');
      final response = await _get('/admin/reports', repository);

      expect(response.statusCode, 500);
      final body = await response.json() as Map<String, dynamic>;
      expect(body['error'], 'The reports could not be loaded.');
    });
  });
}
