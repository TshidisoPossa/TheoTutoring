import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/account/suspension/appeal.dart' as appeal_route;
import '../../../routes/account/suspension/index.dart' as suspension_route;
import '../../fakes/fake_account_suspensions.dart';

class _Ctx extends Mock implements RequestContext {}

class _Req extends Mock implements Request {}

RequestContext _ctx(HttpMethod method, {Object? body}) {
  final c = _Ctx();
  final r = _Req();
  when(() => c.request).thenReturn(r);
  when(() => r.method).thenReturn(method);
  when(() => r.uri).thenReturn(Uri.parse('http://x/account/suspension'));
  when(() => r.headers).thenReturn({'Authorization': 'Bearer t'});
  when(r.json).thenAnswer((_) async {
    if (body == null) throw const FormatException('no body');
    return body;
  });
  return c;
}

/// The Firebase token says who the caller is; nothing else does.
Future<FirebaseUser> Function(String?) _signedInAs(String uid) =>
    (_) async => FirebaseUser(
      uid: uid,
      email: '$uid@example.test',
      emailVerified: true,
    );

Future<FirebaseUser> _badToken(String? _) async =>
    throw const AuthTokenException('Invalid sign-in token.');

const _admin = AdminIdentity(id: 3, name: 'Ada', roleKey: 'super_admin');
const _explanation =
    'I was in hospital that week and could not attend my lessons.';

Future<Map<String, dynamic>> _json(Response res) async =>
    jsonDecode(await res.body()) as Map<String, dynamic>;

void main() {
  late FakeSuspensionStore store;
  late RecordingSender sender;

  setUp(() async {
    store = FakeSuspensionStore()
      ..add(role: 'student', profileId: 5)
      ..add(role: 'student', profileId: 6)
      ..add(role: 'tutor', profileId: 8);
    sender = RecordingSender();
    await store.changeStatus(
      admin: _admin,
      role: 'student',
      profileId: 5,
      status: 'Suspended',
      reason: 'Repeated no-shows for booked lessons.',
    );
  });

  Future<Response> view(String uid) => suspension_route.handleAccountSuspension(
    _ctx(HttpMethod.get),
    tokenVerifier: _signedInAs(uid),
    repository: store,
    noticeSender: sender.call,
  );

  Future<Response> appeal(String uid, Object? body) =>
      appeal_route.handleSubmitAppeal(
        _ctx(HttpMethod.post, body: body),
        tokenVerifier: _signedInAs(uid),
        repository: store,
      );

  group('GET /account/suspension', () {
    test('shows the suspended user their reason and that they can appeal',
        () async {
      final res = await view('uid-student-5');
      expect(res.statusCode, HttpStatus.ok);
      final body = await _json(res);
      expect(body['accountStatus'], 'Suspended');
      expect(
        (body['suspension'] as Map)['reason'],
        'Repeated no-shows for booked lessons.',
      );
      expect(body['appeal'], isNull);
      expect(body['canAppeal'], isTrue);
    });

    test("only ever returns the caller's own suspension", () async {
      final other = await _json(await view('uid-student-6'));
      expect(other['accountStatus'], 'Active');
      expect(other['suspension'], isNull);
      expect(other['canAppeal'], isFalse);
    });

    test('retries a notice Firestore missed earlier', () async {
      expect(store.notifications.single.firestoreId, isNull);
      await view('uid-student-5');
      expect(sender.sent.single.firestoreId, 'suspension-1');
      expect(store.notifications.single.firestoreId, 'suspension-1');
      // Delivered once only
      await view('uid-student-5');
      expect(sender.sent, hasLength(1));
    });

    test('a delivery failure does not stop the screen loading', () async {
      sender.fail = true;
      final res = await view('uid-student-5');
      expect(res.statusCode, HttpStatus.ok);
      expect(store.notifications.single.firestoreId, isNull);
    });

    test('401 without a valid token; 404 for admins and unknown users',
        () async {
      var res = await suspension_route.handleAccountSuspension(
        _ctx(HttpMethod.get),
        tokenVerifier: _badToken,
        repository: store,
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      res = await view('uid-admin-1');
      expect(res.statusCode, HttpStatus.notFound);
      res = await suspension_route.handleAccountSuspension(
        _ctx(HttpMethod.post),
        tokenVerifier: _signedInAs('uid-student-5'),
        repository: store,
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('POST /account/suspension/appeal', () {
    test('the suspended user sends an appeal; the account stays suspended',
        () async {
      final res = await appeal('uid-student-5', {'explanation': _explanation});
      expect(res.statusCode, HttpStatus.created);
      final body = await _json(res);
      expect(body['status'], 'Pending');
      expect(store.appeals.single.explanation, _explanation);
      expect(store.appeals.single.userId, store.account('student', 5).userId);
      // An appeal never restores the account
      expect(store.account('student', 5).status, 'Suspended');
      expect(store.suspensions.single.status, 'Active');

      final status = await _json(await view('uid-student-5'));
      expect((status['appeal'] as Map)['status'], 'Pending');
      expect(status['canAppeal'], isFalse);
    });

    test('a second appeal for the same suspension is refused', () async {
      await appeal('uid-student-5', {'explanation': _explanation});
      final res = await appeal('uid-student-5', {
        'explanation': '$_explanation Please reconsider.',
      });
      expect(res.statusCode, HttpStatus.conflict);
      expect((await _json(res))['code'], 'appeal_exists');
      expect(store.appeals, hasLength(1));
    });

    test('another user cannot appeal (they are not suspended)', () async {
      final res = await appeal('uid-student-6', {'explanation': _explanation});
      expect(res.statusCode, HttpStatus.conflict);
      expect((await _json(res))['code'], 'not_suspended');
      expect(store.appeals, isEmpty);
    });

    test('no ids, roles or statuses are accepted from the app', () async {
      for (final body in [
        {'explanation': _explanation, 'userId': 101},
        {'explanation': _explanation, 'suspensionId': 1},
        {'explanation': _explanation, 'status': 'Active'},
      ]) {
        final res = await appeal('uid-student-5', body);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$body');
      }
      expect(store.appeals, isEmpty);
    });

    test('the explanation must be meaningful', () async {
      for (final body in <Object?>[
        null,
        <String, Object?>{},
        {'explanation': ''},
        {'explanation': 'Please.'},
        {'explanation': 'x' * 2001},
        {'explanation': 7},
      ]) {
        final res = await appeal('uid-student-5', body);
        expect(res.statusCode, HttpStatus.badRequest, reason: '$body');
      }
      expect(store.appeals, isEmpty);
    });

    test('401 without a valid token', () async {
      final res = await appeal_route.handleSubmitAppeal(
        _ctx(HttpMethod.post, body: {'explanation': _explanation}),
        tokenVerifier: _badToken,
        repository: store,
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      expect(store.appeals, isEmpty);
    });

    test('an account suspended before records began cannot appeal here',
        () async {
      store.account('tutor', 8).status = 'Suspended'; // no suspension row
      final res = await appeal('uid-tutor-8', {'explanation': _explanation});
      expect(res.statusCode, HttpStatus.conflict);
      expect((await _json(res))['code'], 'no_suspension_record');
    });
  });
}
