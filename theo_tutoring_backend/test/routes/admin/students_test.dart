import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_students.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/students/[studentId]/status.dart' as status_route;
import '../../../routes/admin/students/index.dart' as roster_route;

class _Ctx extends Mock implements RequestContext {}

class _Req extends Mock implements Request {}

class _Repo implements StudentRosterRepository {
  int? statusId;
  String? statusValue;
  String? listedStatus;
  int listCalls = 0;
  bool missing = false;

  @override
  Future<Map<String, Object?>> list({
    String? status,
    String? search,
    required int page,
    required int pageSize,
  }) async {
    listCalls++;
    listedStatus = status;
    return {
      'total': 0,
      'page': page,
      'pageSize': pageSize,
      'summary': {},
      'students': [],
    };
  }

  @override
  Future<Map<String, Object?>> setStatus(int studentId, String status) async {
    if (missing) throw const StudentNotFound();
    statusId = studentId;
    statusValue = status;
    return {'studentId': studentId, 'status': status};
  }
}

AdminResolver _as(String role) =>
    (_) async => AdminIdentity(id: 1, name: 'Ada', roleKey: role);

AdminResolver _badToken() =>
    (_) async => throw const AuthTokenException('bad token');

RequestContext _ctx(
  HttpMethod method, {
  String url = 'http://x/a',
  Object? body,
}) {
  final c = _Ctx();
  final r = _Req();
  when(() => c.request).thenReturn(r);
  when(() => r.method).thenReturn(method);
  when(() => r.uri).thenReturn(Uri.parse(url));
  when(() => r.headers).thenReturn({'Authorization': '******'});
  when(r.json).thenAnswer((_) async {
    if (body == null) throw const FormatException('no body');
    return body;
  });
  return c;
}

void main() {
  group('PATCH /admin/students/{id}/status', () {
    for (final role in [
      'admin',
      'application_reviewer',
      'finance_admin',
      'support_admin',
      'monitor_admin',
    ]) {
      test('$role is forbidden and nothing changes', () async {
        final repo = _Repo();
        final res = await status_route.handleStudentStatus(
          _ctx(HttpMethod.patch, body: {'status': 'Suspended'}),
          '5',
          adminResolver: _as(role),
          repository: repo,
        );
        expect(res.statusCode, HttpStatus.forbidden);
        expect(repo.statusValue, isNull);
      });
    }

    test('invalid token is 401', () async {
      final repo = _Repo();
      final res = await status_route.handleStudentStatus(
        _ctx(HttpMethod.patch, body: {'status': 'Suspended'}),
        '5',
        adminResolver: _badToken(),
        repository: repo,
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      expect(repo.statusValue, isNull);
    });

    test('super_admin can suspend, deactivate and reactivate', () async {
      for (final s in ['Suspended', 'Deactivated', 'Active']) {
        final repo = _Repo();
        final res = await status_route.handleStudentStatus(
          _ctx(HttpMethod.patch, body: {'status': s}),
          '5',
          adminResolver: _as('super_admin'),
          repository: repo,
        );
        expect(res.statusCode, HttpStatus.ok);
        expect(repo.statusId, 5);
        expect(repo.statusValue, s);
      }
    });

    test('rejects bad statuses, ids and bodies', () async {
      for (final c in [
        (id: '5', body: <String, Object?>{'status': 'Rejected'}),
        (id: '5', body: <String, Object?>{'status': 'active'}),
        (id: '5', body: <String, Object?>{}),
        (id: 'x', body: <String, Object?>{'status': 'Active'}),
        (id: '0', body: <String, Object?>{'status': 'Active'}),
      ]) {
        final repo = _Repo();
        final res = await status_route.handleStudentStatus(
          _ctx(HttpMethod.patch, body: c.body),
          c.id,
          adminResolver: _as('super_admin'),
          repository: repo,
        );
        expect(res.statusCode, HttpStatus.badRequest, reason: '$c');
        expect(repo.statusValue, isNull);
      }
    });

    test('missing student is 404; wrong method is 405', () async {
      final repo = _Repo()..missing = true;
      var res = await status_route.handleStudentStatus(
        _ctx(HttpMethod.patch, body: {'status': 'Suspended'}),
        '9',
        adminResolver: _as('super_admin'),
        repository: repo,
      );
      expect(res.statusCode, HttpStatus.notFound);
      res = await status_route.handleStudentStatus(
        _ctx(HttpMethod.post),
        '9',
        adminResolver: _as('super_admin'),
        repository: repo,
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('GET /admin/students', () {
    test('only super_admin may read; filter maps to account status', () async {
      final repo = _Repo();
      final denied = await roster_route.handleStudentRoster(
        _ctx(HttpMethod.get),
        adminResolver: _as('admin'),
        repository: repo,
      );
      expect(denied.statusCode, HttpStatus.forbidden);
      expect(repo.listCalls, 0);

      final ok = await roster_route.handleStudentRoster(
        _ctx(HttpMethod.get, url: 'http://x/a?status=suspended&pageSize=5'),
        adminResolver: _as('super_admin'),
        repository: repo,
      );
      expect(ok.statusCode, HttpStatus.ok);
      expect(repo.listedStatus, 'Suspended');
      final body = jsonDecode(await ok.body()) as Map<String, dynamic>;
      expect(body['adminName'], 'Ada');
      expect(body['pageSize'], 5);
    });

    test('validates status, page and pageSize', () async {
      for (final q in [
        'status=Rejected',
        'page=0',
        'pageSize=0',
        'pageSize=101',
      ]) {
        final res = await roster_route.handleStudentRoster(
          _ctx(HttpMethod.get, url: 'http://x/a?$q'),
          adminResolver: _as('super_admin'),
          repository: _Repo(),
        );
        expect(res.statusCode, HttpStatus.badRequest, reason: q);
      }
    });
  });
}
