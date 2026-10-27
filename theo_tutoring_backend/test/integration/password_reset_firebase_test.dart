import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/password_reset.dart';

// Forgot password against the REAL Firebase project. Run from
// theo_tutoring_backend:
//
//   $env:THEO_FIREBASE_RESET_TEST = '1'
//   dart test test/integration/password_reset_firebase_test.dart
//
// The web API key is read from the app's lib/firebase_options.dart (it is
// public, the same key the app ships with).
//
// It creates a throwaway Firebase account, checks the email through the
// reset-check handler, resets the password with a real reset code (the same
// code the reset email's link carries), signs in with the new password and
// deletes the account again. No email is sent.

const _identityToolkit = 'https://identitytoolkit.googleapis.com/v1';

class _MockRequestContext extends Mock implements RequestContext {}

const _firebaseOptionsPath = '../theo_tutoring_app/lib/firebase_options.dart';

/// The `web` apiKey from the app's firebase_options.dart. Read as text
/// because that file imports Flutter, which the backend cannot.
final String? _webApiKey = () {
  final file = File(_firebaseOptionsPath);
  if (!file.existsSync()) return null;
  final match = RegExp(
    r"FirebaseOptions web = FirebaseOptions\([^)]*?apiKey: '([^']+)'",
  ).firstMatch(file.readAsStringSync());
  return match?.group(1);
}();

final String? _skip = () {
  if (Platform.environment['THEO_FIREBASE_RESET_TEST'] != '1') {
    return 'Set THEO_FIREBASE_RESET_TEST=1 to run against real Firebase.';
  }
  if (_webApiKey == null) {
    return 'No web apiKey found in $_firebaseOptionsPath.';
  }
  return null;
}();

String get _apiKey => _webApiKey!;

Future<bool> _checkEmail(String email) async {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      'POST',
      Uri.parse('http://localhost/auth/password-reset/check'),
      body: jsonEncode({'email': email}),
    ),
  );
  final response = await handlePasswordResetCheck(context);
  expect(response.statusCode, HttpStatus.ok, reason: await response.body());
  return (jsonDecode(await response.body()) as Map)['exists'] as bool;
}

Future<Map<String, dynamic>> _post(
  String url,
  Map<String, Object?> body, {
  String? adminToken,
  int expectStatus = 200,
}) async {
  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      if (adminToken != null) 'Authorization': 'Bearer $adminToken',
    },
    body: jsonEncode(body),
  );
  expect(response.statusCode, expectStatus, reason: response.body);
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _signIn(
  String email,
  String password, {
  int expectStatus = 200,
}) => _post(
  '$_identityToolkit/accounts:signInWithPassword?key=$_apiKey',
  {'email': email, 'password': password, 'returnSecureToken': true},
  expectStatus: expectStatus,
);

void main() {
  late FirebaseAdmin admin;
  late String adminToken;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'reset-test-$stamp@theotutoring-test.example.com';
  const oldPassword = 'OldPassword#1';
  const newPassword = 'NewPassword#2';
  String? uid;

  setUpAll(() async {
    if (_skip != null) return;
    admin = FirebaseAdmin.instance;
    adminToken = await admin.accessToken();
    final created = await _post(
      '$_identityToolkit/projects/${admin.projectId}/accounts',
      {'email': email, 'password': oldPassword},
      adminToken: adminToken,
    );
    uid = created['localId'] as String;
  });

  tearDownAll(() async {
    if (uid == null) return;
    await _post(
      '$_identityToolkit/projects/${admin.projectId}/accounts:delete',
      {'localId': uid},
      adminToken: adminToken,
    );
  });

  test('the check finds the registered email', () async {
    expect(await _checkEmail(email), isTrue);
  }, skip: _skip);

  test('the check reports an unregistered email as missing', () async {
    expect(await _checkEmail('nobody-$stamp@theotutoring-test.example.com'),
        isFalse);
  }, skip: _skip);

  test('the reset updates the password and the new one signs in', () async {
    // Same reset code Firebase puts in the email link; returnOobLink means
    // it is handed back here instead of being emailed.
    final oob = await _post(
      '$_identityToolkit/projects/${admin.projectId}/accounts:sendOobCode',
      {
        'requestType': 'PASSWORD_RESET',
        'email': email,
        'returnOobLink': true,
      },
      adminToken: adminToken,
    );
    final oobCode =
        Uri.parse(oob['oobLink'] as String).queryParameters['oobCode']!;

    // What Firebase's reset page does when the user submits a new password.
    final reset = await _post(
      '$_identityToolkit/accounts:resetPassword?key=$_apiKey',
      {'oobCode': oobCode, 'newPassword': newPassword},
    );
    expect(reset['email'], email);

    final signedIn = await _signIn(email, newPassword);
    expect(signedIn['localId'], uid);
    expect(signedIn['idToken'], isA<String>());

    final rejected = await _signIn(email, oldPassword, expectStatus: 400);
    expect(
      (rejected['error'] as Map)['message'],
      anyOf('INVALID_LOGIN_CREDENTIALS', 'INVALID_PASSWORD'),
    );

    // A reset code works once only.
    await _post(
      '$_identityToolkit/accounts:resetPassword?key=$_apiKey',
      {'oobCode': oobCode, 'newPassword': 'Another#3'},
      expectStatus: 400,
    );
  }, skip: _skip);
}
