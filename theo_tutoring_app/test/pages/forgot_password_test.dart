import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/forgot_password.dart';
import 'package:theo_tutoring_app/services/password_reset_api.dart';

class _FakeAuth extends Fake implements FirebaseAuth {
  final sentTo = <String>[];
  FirebaseAuthException? error;

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    if (error != null) throw error!;
    sentTo.add(email);
  }
}

/// A backend that knows [registered] emails, recording each check.
PasswordResetApi _api(
  Set<String> registered, {
  List<String>? checked,
  int status = 200,
}) => PasswordResetApi(
  client: MockClient((request) async {
    final email = (jsonDecode(request.body) as Map)['email'] as String;
    checked?.add(email);
    return http.Response(
      jsonEncode({'exists': registered.contains(email)}),
      status,
    );
  }),
);

Future<void> _submit(
  WidgetTester tester, {
  required _FakeAuth auth,
  required PasswordResetApi api,
  required String email,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ForgotPasswordPage(auth: auth, resetApi: api),
    ),
  );
  await tester.enterText(find.byType(TextFormField), email);
  await tester.tap(find.text('Send Reset Link'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a registered email is checked first, then the reset is sent', (
    tester,
  ) async {
    final auth = _FakeAuth();
    final checked = <String>[];
    await _submit(
      tester,
      auth: auth,
      api: _api({'student@example.com'}, checked: checked),
      email: '  student@example.com ',
    );

    expect(checked, ['student@example.com']);
    expect(auth.sentTo, ['student@example.com']);
    expect(
      find.text('A password reset link has been sent to student@example.com.'),
      findsOneWidget,
    );
  });

  testWidgets('an email with no Firebase account gets no reset email', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await _submit(
      tester,
      auth: auth,
      api: _api({'student@example.com'}),
      email: 'nobody@example.com',
    );

    expect(auth.sentTo, isEmpty);
    expect(
      find.text('No account found for that email. Please register first.'),
      findsOneWidget,
    );
  });

  testWidgets('if the check fails no reset email is sent', (tester) async {
    final auth = _FakeAuth();
    await _submit(
      tester,
      auth: auth,
      api: _api({'student@example.com'}, status: 503),
      email: 'student@example.com',
    );

    expect(auth.sentTo, isEmpty);
    expect(
      find.text('Could not check that email right now. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('the server is unreachable', (tester) async {
    final auth = _FakeAuth();
    await _submit(
      tester,
      auth: auth,
      api: PasswordResetApi(
        client: MockClient((_) async => throw http.ClientException('down')),
      ),
      email: 'student@example.com',
    );

    expect(auth.sentTo, isEmpty);
    expect(
      find.text('Could not connect to the server. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a Firebase error while sending is shown', (tester) async {
    final auth = _FakeAuth()
      ..error = FirebaseAuthException(code: 'too-many-requests');
    await _submit(
      tester,
      auth: auth,
      api: _api({'student@example.com'}),
      email: 'student@example.com',
    );

    expect(
      find.text('Too many attempts. Please try again shortly.'),
      findsOneWidget,
    );
  });

  testWidgets('an invalid email never reaches the backend', (tester) async {
    final auth = _FakeAuth();
    final checked = <String>[];
    await _submit(
      tester,
      auth: auth,
      api: _api({}, checked: checked),
      email: 'not-an-email',
    );

    expect(checked, isEmpty);
    expect(auth.sentTo, isEmpty);
    expect(find.text('Please enter a valid email address'), findsOneWidget);
  });
}
