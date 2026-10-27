import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/password_reset.dart';

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeLookup implements FirebaseAccountLookup {
  _FakeLookup(this.existing, {this.unavailable = false});

  final Set<String> existing;
  final bool unavailable;
  final asked = <String>[];

  @override
  Future<bool> emailExists(String email) async {
    asked.add(email);
    if (unavailable) throw const AccountLookupUnavailable();
    return existing.contains(email);
  }
}

RequestContext _context(HttpMethod method, [Object? body]) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      method.value,
      Uri.parse('http://localhost/auth/password-reset/check'),
      body: body == null ? null : (body is String ? body : jsonEncode(body)),
    ),
  );
  return context;
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

void main() {
  test('an email registered in Firebase is reported as existing', () async {
    final lookup = _FakeLookup({'student@example.com'});
    final response = await handlePasswordResetCheck(
      _context(HttpMethod.post, {'email': '  student@example.com '}),
      lookupFactory: () => lookup,
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(await _json(response), {'exists': true});
    expect(lookup.asked, ['student@example.com']);
  });

  test('an email with no Firebase account is reported as missing', () async {
    final response = await handlePasswordResetCheck(
      _context(HttpMethod.post, {'email': 'nobody@example.com'}),
      lookupFactory: () => _FakeLookup({'student@example.com'}),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(await _json(response), {'exists': false});
  });

  test('blank, malformed or non-text emails are rejected', () async {
    for (final body in <Object>[
      {'email': ''},
      {'email': 'not-an-email'},
      {'email': 42},
      <String, dynamic>{},
      '[1, 2]',
      'not json',
    ]) {
      final lookup = _FakeLookup({});
      final response = await handlePasswordResetCheck(
        _context(HttpMethod.post, body),
        lookupFactory: () => lookup,
      );
      expect(response.statusCode, HttpStatus.badRequest, reason: '$body');
      expect(lookup.asked, isEmpty);
    }
  });

  test('only POST is accepted', () async {
    final response = await handlePasswordResetCheck(
      _context(HttpMethod.get),
      lookupFactory: () => _FakeLookup({}),
    );
    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });

  test('Firebase being unreachable is a 503, not a "missing" answer', () async {
    final response = await handlePasswordResetCheck(
      _context(HttpMethod.post, {'email': 'student@example.com'}),
      lookupFactory: () => _FakeLookup({}, unavailable: true),
    );
    expect(response.statusCode, HttpStatus.serviceUnavailable);
  });

  group('IdentityToolkitAccountLookup', () {
    late Directory dir;
    late File serviceAccount;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('reset_lookup_');
      serviceAccount = File('${dir.path}/sa.json')
        ..writeAsStringSync(
          jsonEncode({
            'client_email': 'svc@demo.iam.gserviceaccount.com',
            'private_key': 'unused',
            'project_id': 'demo-project',
          }),
        );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    FirebaseAdmin admin() => FirebaseAdmin.fromEnvironment(
      serviceAccountFile: serviceAccount.path,
      fetchToken: () async =>
          (token: 'admin-token', expiresIn: const Duration(hours: 1)),
    );

    test('asks the project accounts:lookup API with the admin token', () async {
      late http.Request seen;
      final lookup = IdentityToolkitAccountLookup(
        firebaseAdmin: admin,
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'users': [
                {'localId': 'uid-1', 'email': 'student@example.com'},
              ],
            }),
            200,
          );
        }),
      );

      expect(await lookup.emailExists('student@example.com'), isTrue);
      expect(
        seen.url.toString(),
        'https://identitytoolkit.googleapis.com/v1/projects/demo-project/'
        'accounts:lookup',
      );
      expect(seen.headers['Authorization'], 'Bearer admin-token');
      expect(jsonDecode(seen.body), {
        'email': ['student@example.com'],
      });
    });

    test('no users in the response means no such account', () async {
      final lookup = IdentityToolkitAccountLookup(
        firebaseAdmin: admin,
        client: MockClient((_) async => http.Response('{"kind":"x"}', 200)),
      );
      expect(await lookup.emailExists('nobody@example.com'), isFalse);
    });

    test('a Firebase error is reported as unavailable', () async {
      final lookup = IdentityToolkitAccountLookup(
        firebaseAdmin: admin,
        client: MockClient((_) async => http.Response('{}', 500)),
      );
      expect(
        lookup.emailExists('student@example.com'),
        throwsA(isA<AccountLookupUnavailable>()),
      );
    });
  });
}
