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
import '../../fakes/fake_account_suspensions.dart';

class _Ctx extends Mock implements RequestContext {}

class _Req extends Mock implements Request {}

/// Reads students from the shared fake store, like the MySQL roster does.
class _Repo implements StudentRosterRepository {
  _Repo([FakeSuspensionStore? store]) : store = store ?? FakeSuspensionStore();
  final FakeSuspensionStore store;
  String? listedStatus;
  int listCalls = 0;

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
  Future<Map<String, Object?>> find(int studentId) async {
    final a = store.accounts
        .where((a) => a.role == 'student' && a.profileId == studentId)
        .firstOrNull;
    if (a == null) throw const StudentNotFound();
    return {'studentId': studentId, 'status': a.status};
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

const _reason = 'Repeatedly missed booked lessons without notice.';

void main() {
  group('PATCH /admin/students/{id}/status', () {
    late FakeSuspensionStore store;
    late RecordingSender sender;

    setUp(() {
      store = FakeSuspensionStore()..add(role: 'student', profileId: 5);
      sender = RecordingSender();
    });

    Future<Response> patch(
      Map<String, Object?>? body, {
      String id = '5',
      AdminResolver? resolver,
    }) => status_route.handleStudentStatus(
      _ctx(HttpMethod.patch, body: body),
      id,
      adminResolver: resolver ?? _as('super_admin'),
      repository: _Repo(store),
      suspensions: store,
      noticeSender: sender.call,
    );

    for (final role in [
      'admin',
      'application_reviewer',
      'finance_admin',
      'support_admin',
      'monitor_admin',
    ]) {
      test('$role is forbidden and nothing changes', () async {
        final res = await patch(
          {'status': 'Suspended', 'reason': _reason},
          resolver: _as(role),
        );
        expect(res.statusCode, HttpStatus.forbidden);
        expect(store.account('student', 5).status, 'Active');
        expect(store.suspensions, isEmpty);
        expect(sender.sent, isEmpty);
      });
    }

    test('invalid token is 401', () async {
      final res = await patch(
        {'status': 'Suspended', 'reason': _reason},
        resolver: _badToken(),
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      expect(store.suspensions, isEmpty);
    });

    test('suspending records the reason and notifies the student', () async {
      final res = await patch({'status': 'Suspended', 'reason': '  $_reason '});
      expect(res.statusCode, HttpStatus.ok);
      final body = jsonDecode(await res.body()) as Map<String, dynamic>;
      expect(body['status'], 'Suspended');
      expect(body['notificationDelivered'], isTrue);
      expect(body.containsKey('warning'), isFalse);

      final s = store.suspensions.single;
      expect(s.reason, _reason); // trimmed
      expect(s.adminId, 1);
      expect(s.previous, 'Active');
      expect(store.account('student', 5).status, 'Suspended');
      // SQL record of the notice, marked delivered
      final n = store.notifications.single;
      expect(n.type, 'AccountSuspended');
      expect(n.message, contains(_reason));
      expect(n.firestoreId, 'suspension-${s.id}');
      expect(sender.sent.single.firebaseUid, 'uid-student-5');
      expect(sender.sent.single.title, 'Account suspended');
    });

    test('a failed notification keeps the suspension and warns the admin', () async {
      sender.fail = true;
      final res = await patch({'status': 'Suspended', 'reason': _reason});
      expect(res.statusCode, HttpStatus.ok);
      final body = jsonDecode(await res.body()) as Map<String, dynamic>;
      expect(body['notificationDelivered'], isFalse);
      expect(body['warning'], contains('could not be delivered'));
      expect(store.account('student', 5).status, 'Suspended');
      expect(store.suspensions.single.status, 'Active');
      // Not marked delivered, so it is retried later
      expect(store.notifications.single.firestoreId, isNull);
    });

    test('suspending needs a meaningful reason', () async {
      for (final body in [
        <String, Object?>{'status': 'Suspended'},
        <String, Object?>{'status': 'Suspended', 'reason': ''},
        <String, Object?>{'status': 'Suspended', 'reason': '   short  '},
        <String, Object?>{'status': 'Suspended', 'reason': 42},
        <String, Object?>{'status': 'Suspended', 'reason': 'x' * 1001},
      ]) {
        final res = await patch(body);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$body');
      }
      expect(store.suspensions, isEmpty);
      expect(store.account('student', 5).status, 'Active');
    });

    test('suspending twice is a conflict, not a second record', () async {
      await patch({'status': 'Suspended', 'reason': _reason});
      final res = await patch({'status': 'Suspended', 'reason': _reason});
      expect(res.statusCode, HttpStatus.conflict);
      final body = jsonDecode(await res.body()) as Map<String, dynamic>;
      expect(body['code'], 'already_suspended');
      expect(store.suspensions, hasLength(1));
    });

    test('reinstating ends the suspension and closes a pending appeal', () async {
      await patch({'status': 'Suspended', 'reason': _reason});
      await store.submitAppeal(
        'uid-student-5',
        'I was ill and could not attend those lessons.',
      );
      final res = await patch({'status': 'Active'});
      expect(res.statusCode, HttpStatus.ok);
      expect(store.account('student', 5).status, 'Active');
      expect(store.suspensions.single.status, 'Lifted');
      expect(store.suspensions.single.liftReason, 'Reinstated');
      expect(store.appeals.single.status, 'Closed');
      // History is kept
      expect(store.suspensions, hasLength(1));
    });

    test('deactivating and reactivating need no reason', () async {
      for (final s in ['Deactivated', 'Active']) {
        final res = await patch({'status': s});
        expect(res.statusCode, HttpStatus.ok);
        expect(store.account('student', 5).status, s);
      }
      expect(store.suspensions, isEmpty);
      expect(sender.sent, isEmpty);
    });

    test('rejects bad statuses, ids and bodies', () async {
      for (final c in [
        (id: '5', body: <String, Object?>{'status': 'Rejected'}),
        (id: '5', body: <String, Object?>{'status': 'active'}),
        (id: '5', body: <String, Object?>{}),
        (id: 'x', body: <String, Object?>{'status': 'Active'}),
        (id: '0', body: <String, Object?>{'status': 'Active'}),
      ]) {
        final res = await patch(c.body, id: c.id);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$c');
      }
      expect(store.account('student', 5).status, 'Active');
    });

    test('missing student is 404; wrong method is 405', () async {
      var res = await patch(
        {'status': 'Suspended', 'reason': _reason},
        id: '9',
      );
      expect(res.statusCode, HttpStatus.notFound);
      res = await status_route.handleStudentStatus(
        _ctx(HttpMethod.post),
        '9',
        adminResolver: _as('super_admin'),
        repository: _Repo(store),
        suspensions: store,
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });

    test('a database failure is a 500 and nothing is notified', () async {
      store.failWith = Exception('lost connection');
      final res = await patch({'status': 'Suspended', 'reason': _reason});
      expect(res.statusCode, HttpStatus.internalServerError);
      expect(sender.sent, isEmpty);
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
