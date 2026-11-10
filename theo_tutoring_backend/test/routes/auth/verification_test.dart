import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/email_verification.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

// POST /auth/verification/send and /verify with a fake identity, code
// table, email sender and Firebase.

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeStore implements VerificationCodeStore {
  CodeOwner? owner = (userId: 12, name: 'Thandi Mokoena');
  CodeSendStats stats = (
    secondsSinceLast: null,
    sentLastHour: 0,
    secondsUntilHourFrees: 0,
  );
  final codes = <int, ({String hash, int attempts, bool used})>{};
  bool expired = false;

  @override
  Future<CodeOwner?> findUser(String firebaseUid) async {
    expect(firebaseUid, 'firebase-uid');
    return owner;
  }

  @override
  Future<CodeSendStats> sendStats(int userId) async => stats;

  @override
  Future<int> saveCode(int userId, String codeHash) async {
    final id = codes.length + 1;
    codes[id] = (hash: codeHash, attempts: 0, used: false);
    return id;
  }

  @override
  Future<void> deleteCode(int codeId) async => codes.remove(codeId);

  @override
  Future<StoredCode?> latestCode(int userId) async {
    if (codes.isEmpty) return null;
    final id = codes.keys.last;
    final code = codes[id]!;
    return (
      codeId: id,
      codeHash: code.hash,
      attempts: code.attempts,
      used: code.used,
      expired: expired,
    );
  }

  @override
  Future<bool> claimAttempt(int codeId) async {
    final code = codes[codeId]!;
    if (code.used || code.attempts >= maxCodeAttempts) return false;
    codes[codeId] = (hash: code.hash, attempts: code.attempts + 1, used: false);
    return true;
  }

  @override
  Future<void> markUsed(int codeId) async {
    final code = codes[codeId]!;
    codes[codeId] = (hash: code.hash, attempts: code.attempts, used: true);
  }

  /// Stores [code] as the live code, as if it had been emailed.
  void give(String code, {int attempts = 0}) => codes[codes.length + 1] = (
    hash: hashVerificationCode(12, code),
    attempts: attempts,
    used: false,
  );
}

class _FakeSender implements VerificationEmailSender {
  final sent = <({String to, String name, String code})>[];
  bool fail = false;

  @override
  Future<void> sendCode({
    required String to,
    required String name,
    required String code,
  }) async {
    if (fail) throw const EmailSendException('Brevo is down');
    sent.add((to: to, name: name, code: code));
  }
}

class _FakeFirebase implements FirebaseEmailVerifier {
  final verified = <String>[];
  bool fail = false;

  @override
  Future<void> markEmailVerified(String uid) async {
    if (fail) throw const FirebaseAdminException('Firebase is down');
    verified.add(uid);
  }
}

RequestContext _request(String path, {String method = 'POST', Object? body}) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/auth/verification/$path'),
      headers: {'Authorization': 'Bearer test'},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  return context;
}

Future<FirebaseUser> Function(String?) _user({bool verified = false}) =>
    (_) async => FirebaseUser(
      uid: 'firebase-uid',
      email: 'thandi@example.com',
      emailVerified: verified,
    );

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

void main() {
  group('POST /auth/verification/send', () {
    late _FakeStore store;
    late _FakeSender sender;

    setUp(() {
      store = _FakeStore();
      sender = _FakeSender();
    });

    Future<Response> send({
      bool verified = false,
      String method = 'POST',
      VerificationEmailSender Function()? emailSender,
    }) => handleSendVerificationCode(
      _request('send', method: method),
      tokenVerifier: _user(verified: verified),
      store: store,
      emailSender: emailSender ?? () => sender,
    );

    test('emails a 6-digit code and stores only its hash', () async {
      final response = await send();

      expect(response.statusCode, 200);
      expect(await _json(response), {
        'sent': true,
        'expiresIn': 600,
        'resendIn': 60,
      });
      expect(sender.sent, hasLength(1));
      final email = sender.sent.single;
      expect(email.to, 'thandi@example.com');
      expect(email.name, 'Thandi Mokoena');
      expect(email.code, matches(RegExp(r'^\d{6}$')));
      expect(store.codes.values.single.hash, isNot(email.code));
      expect(
        store.codes.values.single.hash,
        hashVerificationCode(12, email.code),
      );
    });

    test('only POST is allowed', () async {
      expect((await send(method: 'GET')).statusCode, 405);
    });

    test('a missing or invalid token is a 401', () async {
      final response = await handleSendVerificationCode(
        _request('send'),
        tokenVerifier: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
        store: store,
        emailSender: () => sender,
      );
      expect(response.statusCode, 401);
    });

    test('an already verified email gets no code', () async {
      final response = await send(verified: true);
      expect(await _json(response), {'alreadyVerified': true});
      expect(sender.sent, isEmpty);
    });

    test('no MySQL user is a 404', () async {
      store.owner = null;
      expect((await send()).statusCode, 404);
    });

    test('a second code within a minute is refused', () async {
      store.stats = (
        secondsSinceLast: 20,
        sentLastHour: 1,
        secondsUntilHourFrees: 3580,
      );
      final response = await send();
      expect(response.statusCode, 429);
      expect((await _json(response))['retryAfter'], 40);
      expect(sender.sent, isEmpty);
    });

    test('more than 5 codes an hour are refused', () async {
      store.stats = (
        secondsSinceLast: 300,
        sentLastHour: 5,
        secondsUntilHourFrees: 600,
      );
      final response = await send();
      expect(response.statusCode, 429);
      expect((await _json(response))['retryAfter'], 600);
    });

    test('no email set up on the server is a 503', () async {
      final response = await send(
        emailSender: () => throw const EmailNotConfiguredException(),
      );
      expect(response.statusCode, 503);
      expect(store.codes, isEmpty);
    });

    test('a failed email removes the code so they can retry', () async {
      sender.fail = true;
      final response = await send();
      expect(response.statusCode, 503);
      expect(store.codes, isEmpty);
    });
  });

  group('POST /auth/verification/verify', () {
    late _FakeStore store;
    late _FakeFirebase firebase;

    setUp(() {
      store = _FakeStore();
      firebase = _FakeFirebase();
    });

    Future<Response> verify(Object? code, {bool verified = false}) =>
        handleVerifyCode(
          _request('verify', body: {'code': code}),
          tokenVerifier: _user(verified: verified),
          store: store,
          firebase: firebase,
        );

    test('the right code marks the email verified in Firebase', () async {
      store.give('048213');
      final response = await verify('048213');

      expect(response.statusCode, 200);
      expect(await _json(response), {'verified': true});
      expect(firebase.verified, ['firebase-uid']);
      expect(store.codes.values.single.used, isTrue);
    });

    test('a wrong code says how many tries are left', () async {
      store.give('048213');
      final response = await verify('111111');

      expect(response.statusCode, 400);
      final body = await _json(response);
      expect(body['attemptsLeft'], 4);
      expect(body['error'], contains('4 tries left'));
      expect(firebase.verified, isEmpty);
    });

    test('the last wrong try asks for a new code', () async {
      store.give('048213', attempts: maxCodeAttempts - 1);
      final body = await _json(await verify('111111'));
      expect(body['needsNewCode'], isTrue);

      // Even the right code no longer works.
      final again = await _json(await verify('048213'));
      expect(again['needsNewCode'], isTrue);
      expect(firebase.verified, isEmpty);
    });

    test('an expired code asks for a new one', () async {
      store
        ..give('048213')
        ..expired = true;
      final body = await _json(await verify('048213'));
      expect(body['needsNewCode'], isTrue);
      expect(body['error'], contains('expired'));
    });

    test('a used code cannot be used twice', () async {
      store.give('048213');
      await verify('048213');
      final body = await _json(await verify('048213'));
      expect(body['needsNewCode'], isTrue);
    });

    test('no code sent yet asks for one', () async {
      final body = await _json(await verify('048213'));
      expect(body['needsNewCode'], isTrue);
    });

    test('anything but 6 digits is refused without using a try', () async {
      store.give('048213');
      for (final code in ['12345', '1234567', 'abcdef', 123456, null]) {
        expect((await verify(code)).statusCode, 400);
      }
      expect(store.codes.values.single.attempts, 0);
    });

    test('a Firebase failure keeps the code usable', () async {
      store.give('048213');
      firebase.fail = true;
      expect((await verify('048213')).statusCode, 503);
      expect(store.codes.values.single.used, isFalse);

      firebase.fail = false;
      expect((await verify('048213')).statusCode, 200);
    });

    test('an already verified email is fine', () async {
      final response = await verify('000000', verified: true);
      expect(await _json(response), {'verified': true});
    });
  });

  group('BrevoEmailSender', () {
    test('posts the email to Brevo with the API key', () async {
      late http.Request sent;
      final sender = BrevoEmailSender(
        apiKey: 'key-123',
        senderEmail: 'hello@theotutoring.test',
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"messageId":"1"}', HttpStatus.created);
        }),
      );

      await sender.sendCode(
        to: 'thandi@example.com',
        name: 'Thandi Mokoena',
        code: '048213',
      );

      expect(sent.url.toString(), 'https://api.brevo.com/v3/smtp/email');
      expect(sent.headers['api-key'], 'key-123');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['sender'], {
        'name': 'TheoTutoring',
        'email': 'hello@theotutoring.test',
      });
      expect(body['to'], [
        {'email': 'thandi@example.com', 'name': 'Thandi Mokoena'},
      ]);
      expect(body['subject'], '048213 is your TheoTutoring verification code');
      expect(body['htmlContent'], contains('Hi Thandi,'));
      expect(body['textContent'], contains('048213'));
    });

    test('a refused email throws', () async {
      final sender = BrevoEmailSender(
        apiKey: 'bad',
        senderEmail: 'hello@theotutoring.test',
        client: MockClient((_) async => http.Response('{}', 401)),
      );
      expect(
        () => sender.sendCode(to: 'a@b.com', name: '', code: '000000'),
        throwsA(isA<EmailSendException>()),
      );
    });
  });
}
