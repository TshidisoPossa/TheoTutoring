import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_tutors.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/tutors/[tutorId]/status.dart' as status_route;
import '../../../routes/admin/tutors/index.dart' as roster_route;
import '../../fakes/fake_account_suspensions.dart';

class _Ctx extends Mock implements RequestContext {}

class _Req extends Mock implements Request {}

/// Reads tutors from the shared fake store, like the MySQL roster does.
class _Repo implements TutorRosterRepository {
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
      'tutors': [],
    };
  }

  @override
  Future<Map<String, Object?>> find(int tutorId) async {
    final a = store.accounts
        .where((a) => a.role == 'tutor' && a.profileId == tutorId)
        .firstOrNull;
    if (a == null) throw const TutorNotFound();
    return {'tutorId': tutorId, 'status': a.status};
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

const _reason = 'Asked students to pay outside the platform.';

void main() {
  group('PATCH /admin/tutors/{id}/status', () {
    late FakeSuspensionStore store;
    late RecordingSender sender;

    setUp(() {
      store = FakeSuspensionStore()..add(role: 'tutor', profileId: 5);
      sender = RecordingSender();
    });

    Future<Response> patch(
      Map<String, Object?>? body, {
      String id = '5',
      AdminResolver? resolver,
    }) => status_route.handleTutorStatus(
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
        expect(store.account('tutor', 5).status, 'Active');
        expect(store.suspensions, isEmpty);
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

    test('suspending records the reason and notifies the tutor', () async {
      final res = await patch({'status': 'Suspended', 'reason': _reason});
      expect(res.statusCode, HttpStatus.ok);
      final body = jsonDecode(await res.body()) as Map<String, dynamic>;
      expect(body['status'], 'Suspended');
      expect(body['notificationDelivered'], isTrue);
      expect(store.suspensions.single.reason, _reason);
      expect(store.notifications.single.type, 'AccountSuspended');
      expect(sender.sent.single.firebaseUid, 'uid-tutor-5');
      expect(sender.sent.single.body, contains(_reason));
    });

    test('a failed notification keeps the suspension and warns the admin', () async {
      sender.fail = true;
      final res = await patch({'status': 'Suspended', 'reason': _reason});
      final body = jsonDecode(await res.body()) as Map<String, dynamic>;
      expect(res.statusCode, HttpStatus.ok);
      expect(body['notificationDelivered'], isFalse);
      expect(body['warning'], contains('could not be delivered'));
      expect(store.account('tutor', 5).status, 'Suspended');
    });

    test('suspending needs a meaningful reason', () async {
      for (final body in [
        <String, Object?>{'status': 'Suspended'},
        <String, Object?>{'status': 'Suspended', 'reason': 'too short'},
      ]) {
        final res = await patch(body);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$body');
      }
      expect(store.suspensions, isEmpty);
    });

    test('deactivating and reactivating need no reason', () async {
      for (final s in ['Deactivated', 'Active']) {
        final res = await patch({'status': s});
        expect(res.statusCode, HttpStatus.ok);
        expect(store.account('tutor', 5).status, s);
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
        final res = await patch(c.body, id: c.id);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$c');
      }
    });

    test('a tutor still in review cannot be changed here (409)', () async {
      store.add(role: 'tutor', profileId: 7, status: 'Pending');
      for (final body in [
        <String, Object?>{'status': 'Active'},
        <String, Object?>{'status': 'Suspended', 'reason': _reason},
      ]) {
        final res = await patch(body, id: '7');
        expect(res.statusCode, HttpStatus.conflict);
        final json = jsonDecode(await res.body()) as Map<String, dynamic>;
        expect(json['error'], contains('Applications page'));
      }
      expect(store.account('tutor', 7).status, 'Pending');
      expect(store.suspensions, isEmpty);
    });

    test('missing tutor is 404; wrong method is 405', () async {
      var res = await patch(
        {'status': 'Suspended', 'reason': _reason},
        id: '9',
      );
      expect(res.statusCode, HttpStatus.notFound);
      res = await status_route.handleTutorStatus(
        _ctx(HttpMethod.post),
        '9',
        adminResolver: _as('super_admin'),
        repository: _Repo(store),
        suspensions: store,
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('GET /admin/tutors', () {
    test('only super_admin may read; filter maps to account status', () async {
      final repo = _Repo();
      final denied = await roster_route.handleTutorRoster(
        _ctx(HttpMethod.get),
        adminResolver: _as('admin'),
        repository: repo,
      );
      expect(denied.statusCode, HttpStatus.forbidden);
      expect(repo.listCalls, 0);

      final ok = await roster_route.handleTutorRoster(
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
        final res = await roster_route.handleTutorRoster(
          _ctx(HttpMethod.get, url: 'http://x/a?$q'),
          adminResolver: _as('super_admin'),
          repository: _Repo(),
        );
        expect(res.statusCode, HttpStatus.badRequest, reason: q);
      }
    });
  });
}
