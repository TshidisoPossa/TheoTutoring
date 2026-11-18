import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/appeals/[appealId]/decision.dart'
    as decision_route;
import '../../../routes/admin/appeals/index.dart' as list_route;
import '../../fakes/fake_account_suspensions.dart';

class _Ctx extends Mock implements RequestContext {}

class _Req extends Mock implements Request {}

RequestContext _ctx(
  HttpMethod method, {
  String url = 'http://x/admin/appeals',
  Object? body,
}) {
  final c = _Ctx();
  final r = _Req();
  when(() => c.request).thenReturn(r);
  when(() => r.method).thenReturn(method);
  when(() => r.uri).thenReturn(Uri.parse(url));
  when(() => r.headers).thenReturn({'Authorization': 'Bearer t'});
  when(r.json).thenAnswer((_) async {
    if (body == null) throw const FormatException('no body');
    return body;
  });
  return c;
}

AdminResolver _as(String role, {int id = 1}) =>
    (_) async => AdminIdentity(id: id, name: 'Ada', roleKey: role);

const _note = 'Thank you for explaining; your account is restored.';
const _rejectNote = 'The missed lessons were confirmed by three tutors.';

Future<Map<String, dynamic>> _json(Response res) async =>
    jsonDecode(await res.body()) as Map<String, dynamic>;

void main() {
  late FakeSuspensionStore store;
  late RecordingSender sender;

  /// Suspends the account and sends its appeal; returns the appeal id.
  Future<int> suspendAndAppeal(String role, int profileId) async {
    await store.changeStatus(
      admin: const AdminIdentity(id: 9, name: 'Bo', roleKey: 'super_admin'),
      role: role,
      profileId: profileId,
      status: 'Suspended',
      reason: 'Reported for abusive messages.',
    );
    final appeal = await store.submitAppeal(
      'uid-$role-$profileId',
      'Those messages were sent by someone else using my phone.',
    );
    return appeal['appealId']! as int;
  }

  setUp(() {
    store = FakeSuspensionStore()
      ..add(role: 'student', profileId: 5)
      ..add(role: 'tutor', profileId: 8, status: 'Pending');
    sender = RecordingSender();
  });

  Future<Response> decide(
    int appealId,
    Object? body, {
    AdminResolver? resolver,
  }) => decision_route.handleAppealDecision(
    _ctx(HttpMethod.post, body: body),
    '$appealId',
    adminResolver: resolver ?? _as('super_admin'),
    repository: store,
    noticeSender: sender.call,
  );

  group('GET /admin/appeals', () {
    test('lists appeals with the account, reason and explanation', () async {
      await suspendAndAppeal('student', 5);
      final res = await list_route.handleAppealList(
        _ctx(HttpMethod.get),
        adminResolver: _as('super_admin'),
        repository: store,
      );
      expect(res.statusCode, HttpStatus.ok);
      final body = await _json(res);
      expect(body['adminName'], 'Ada');
      expect((body['summary'] as Map)['pending'], 1);
      final appeal = (body['appeals'] as List).single as Map;
      expect(appeal['status'], 'Pending');
      expect(appeal['explanation'], contains('someone else'));
      expect((appeal['suspension'] as Map)['reason'], contains('abusive'));
      expect((appeal['user'] as Map)['role'], 'student');
      // Defaults to the pending appeals, for both kinds of account
      expect(store.lastListed?.status, 'pending');
      expect(store.lastListed?.roles, {'student', 'tutor'});
    });

    test('accepts each status filter and rejects others', () async {
      for (final s in ['pending', 'approved', 'rejected', 'closed', 'all']) {
        final res = await list_route.handleAppealList(
          _ctx(HttpMethod.get, url: 'http://x/admin/appeals?status=$s'),
          adminResolver: _as('super_admin'),
          repository: store,
        );
        expect(res.statusCode, HttpStatus.ok, reason: s);
      }
      final res = await list_route.handleAppealList(
        _ctx(HttpMethod.get, url: 'http://x/admin/appeals?status=Pending'),
        adminResolver: _as('super_admin'),
        repository: store,
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('admins who cannot manage students or tutors are forbidden',
        () async {
      for (final role in [
        'admin',
        'application_reviewer',
        'finance_admin',
        'support_admin',
        'monitor_admin',
      ]) {
        final res = await list_route.handleAppealList(
          _ctx(HttpMethod.get),
          adminResolver: _as(role),
          repository: store,
        );
        expect(res.statusCode, HttpStatus.forbidden, reason: role);
      }
      expect(store.lastListed, isNull);
    });

    test('401 for a bad token; 405 for other methods', () async {
      var res = await list_route.handleAppealList(
        _ctx(HttpMethod.get),
        adminResolver: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
        repository: store,
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      res = await list_route.handleAppealList(
        _ctx(HttpMethod.post),
        adminResolver: _as('super_admin'),
        repository: store,
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });

    test('appeal roles follow the manage permissions', () {
      expect(
        appealRolesFor(
          const AdminIdentity(id: 1, name: 'A', roleKey: 'super_admin'),
        ),
        {'student', 'tutor'},
      );
      expect(
        appealRolesFor(const AdminIdentity(id: 1, name: 'A')),
        isEmpty,
      );
    });
  });

  group('POST /admin/appeals/{id}/decision', () {
    test('approving lifts the suspension and tells the user', () async {
      final id = await suspendAndAppeal('student', 5);
      final res = await decide(id, {'decision': 'approve', 'note': _note});
      expect(res.statusCode, HttpStatus.ok);
      final body = await _json(res);
      expect((body['appeal'] as Map)['status'], 'Approved');
      expect(body['notificationDelivered'], isTrue);

      expect(store.account('student', 5).status, 'Active');
      final s = store.suspensions.single;
      expect(s.status, 'Lifted');
      expect(s.liftReason, 'AppealApproved');
      expect(store.appeals.single.reviewedBy, 1);
      expect(store.appeals.single.note, _note);
      final notice = sender.sent.single;
      expect(notice.type, 'AppealApproved');
      expect(notice.firebaseUid, 'uid-student-5');
      expect(notice.body, contains(_note));
    });

    test('approval restores the previous status, not always Active', () async {
      final id = await suspendAndAppeal('tutor', 8); // was Pending
      await decide(id, {'decision': 'approve'}); // note optional
      expect(store.account('tutor', 8).status, 'Pending');
    });

    test('rejecting keeps the suspension and tells the user why', () async {
      final id = await suspendAndAppeal('student', 5);
      final res = await decide(id, {'decision': 'reject', 'note': _rejectNote});
      expect(res.statusCode, HttpStatus.ok);
      expect(store.account('student', 5).status, 'Suspended');
      expect(store.suspensions.single.status, 'Active');
      expect(store.appeals.single.status, 'Rejected');
      expect(sender.sent.single.type, 'AppealRejected');
      expect(sender.sent.single.body, contains(_rejectNote));
      // Final for this suspension: no second appeal
      expect(
        () => store.submitAppeal('uid-student-5', 'One more try, please.'),
        throwsA(isA<SuspensionConflict>()),
      );
    });

    test('a rejection needs a reason; an approval note is optional', () async {
      final id = await suspendAndAppeal('student', 5);
      for (final body in [
        {'decision': 'reject'},
        {'decision': 'reject', 'note': '   '},
        {'decision': 'reject', 'note': 'No.'},
        {'decision': 'approve', 'note': 'Ok.'}, // given, so it must be real
        {'decision': 'approve', 'note': 'x' * 1001},
      ]) {
        final res = await decide(id, body);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$body');
      }
      expect(store.appeals.single.status, 'Pending');
      expect(store.account('student', 5).status, 'Suspended');
    });

    test('invalid decisions, ids and bodies are rejected', () async {
      final id = await suspendAndAppeal('student', 5);
      for (final c in [
        (id: '$id', body: <String, Object?>{'decision': 'maybe'}),
        (id: '$id', body: <String, Object?>{'decision': 'APPROVE'}),
        (id: '$id', body: <String, Object?>{}),
        (id: '0', body: <String, Object?>{'decision': 'approve'}),
        (id: 'abc', body: <String, Object?>{'decision': 'approve'}),
      ]) {
        final res = await decision_route.handleAppealDecision(
          _ctx(HttpMethod.post, body: c.body),
          c.id,
          adminResolver: _as('super_admin'),
          repository: store,
          noticeSender: sender.call,
        );
        expect(res.statusCode, HttpStatus.badRequest, reason: '$c');
      }
      final missing = await decide(999, {'decision': 'approve'});
      expect(missing.statusCode, HttpStatus.notFound);
      expect(sender.sent, isEmpty);
    });

    test('a decided appeal cannot be decided again', () async {
      final id = await suspendAndAppeal('student', 5);
      await decide(id, {'decision': 'reject', 'note': _rejectNote});
      for (final body in [
        {'decision': 'reject', 'note': _rejectNote},
        {'decision': 'approve', 'note': _note},
      ]) {
        final res = await decide(id, body);
        expect(res.statusCode, HttpStatus.conflict);
        expect((await _json(res))['code'], 'appeal_already_decided');
      }
      // The rejection stands
      expect(store.account('student', 5).status, 'Suspended');
      expect(store.appeals.single.status, 'Rejected');
      expect(sender.sent, hasLength(1));
    });

    test('an appeal closed by a reinstatement cannot be approved', () async {
      final id = await suspendAndAppeal('student', 5);
      await store.changeStatus(
        admin: const AdminIdentity(id: 9, name: 'Bo', roleKey: 'super_admin'),
        role: 'student',
        profileId: 5,
        status: 'Active',
      );
      final res = await decide(id, {'decision': 'approve'});
      expect(res.statusCode, HttpStatus.conflict);
      expect(store.appeals.single.status, 'Closed');
    });

    test('admins without the manage permission cannot decide', () async {
      final id = await suspendAndAppeal('student', 5);
      for (final role in ['admin', 'support_admin', 'monitor_admin']) {
        final res = await decide(
          id,
          {'decision': 'approve', 'note': _note},
          resolver: _as(role),
        );
        expect(res.statusCode, HttpStatus.forbidden, reason: role);
      }
      expect(store.appeals.single.status, 'Pending');
      expect(store.account('student', 5).status, 'Suspended');
      expect(sender.sent, isEmpty);
    });

    test('a failed notification keeps the decision and warns the admin',
        () async {
      final id = await suspendAndAppeal('student', 5);
      sender.fail = true;
      final res = await decide(id, {'decision': 'approve', 'note': _note});
      expect(res.statusCode, HttpStatus.ok);
      final body = await _json(res);
      expect(body['notificationDelivered'], isFalse);
      expect(body['warning'], contains('decision was saved'));
      expect(store.account('student', 5).status, 'Active');
      expect(store.appeals.single.status, 'Approved');
      final decisionNotice = store.notifications.last;
      expect(decisionNotice.type, 'AppealApproved');
      expect(decisionNotice.firestoreId, isNull); // retried later
    });

    test('a database failure is a 500 and nothing is notified', () async {
      final id = await suspendAndAppeal('student', 5);
      store.failWith = Exception('lost connection');
      final res = await decide(id, {'decision': 'approve', 'note': _note});
      expect(res.statusCode, HttpStatus.internalServerError);
      expect(sender.sent, isEmpty);
    });

    test('401 for a bad token; 405 for other methods', () async {
      var res = await decide(
        1,
        {'decision': 'approve'},
        resolver: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      res = await decision_route.handleAppealDecision(
        _ctx(HttpMethod.get),
        '1',
        adminResolver: _as('super_admin'),
        repository: store,
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('notice text', () {
    test('suspension and decision notices carry the reasons', () {
      expect(
        suspensionNoticeBody('Spam messages.'),
        allOf(contains('suspended'), contains('Spam messages.'),
            contains('appeal')),
      );
      expect(
        appealDecisionNoticeBody(approved: false, note: 'Confirmed.'),
        allOf(contains('remains suspended'), contains('Confirmed.')),
      );
      expect(
        appealDecisionNoticeBody(approved: true),
        'Your appeal was approved and your account has been reinstated.',
      );
    });
  });
}
