import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/login_page.dart';
import 'package:theo_tutoring_app/Pages/verify_email_page.dart';
import 'package:theo_tutoring_app/services/auth_service.dart';

/// Backend stand-in: [rightCode] is the code in the "email".
class _FakeAuth extends AuthService {
  String rightCode = '048213';
  int codesSent = 0;
  final tried = <String>[];
  bool signedOut = false;
  VerificationCodeException? sendError;

  @override
  Future<VerificationCodeSent> sendVerificationCode() async {
    final error = sendError;
    if (error != null) throw error;
    codesSent++;
    return const VerificationCodeSent(alreadyVerified: false, resendIn: 60);
  }

  @override
  Future<void> verifyCode(String code) async {
    tried.add(code);
    if (code != rightCode) {
      throw const VerificationCodeException(
        'That code is incorrect. 4 tries left.',
        statusCode: 400,
        attemptsLeft: 4,
      );
    }
  }

  @override
  Future<void> signOut() async => signedOut = true;

  @override
  Future<User?> restoredUser() async => null;

  @override
  Stream<User?> authStateChanges() => const Stream.empty();
}

Widget _app(Widget page) => MaterialApp(home: page);

void main() {
  const email = 'thandi@gmail.com';

  testWidgets('opening the page emails a code and shows six boxes', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(VerifyEmailPage(email: email, service: auth)));
    await tester.pump();

    expect(auth.codesSent, 1);
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('Enter the 6-digit code we sent to'), findsOneWidget);
    expect(find.text(email), findsOneWidget);
    expect(find.text('Open Gmail'), findsOneWidget);
    expect(find.text('resend in 1:00'), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing); // verification required
  });

  testWidgets('the right code shows success, then goes on to log in', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(VerifyEmailPage(email: email, service: auth)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '048213');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // success animation

    expect(auth.tried, ['048213']);
    expect(find.text('Email verified'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue to log in'));
    await tester.tap(find.text('Continue to log in'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, isTrue);
    final login = tester.widget<LoginPage>(find.byType(LoginPage));
    expect(login.initialEmail, email);
  });

  testWidgets('a wrong code shows the error and clears the boxes', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(VerifyEmailPage(email: email, service: auth)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '111111');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // shake

    expect(find.text('That code is incorrect. 4 tries left.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('Email verified'), findsNothing);
  });

  testWidgets('nothing is checked until all 6 digits are in', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(VerifyEmailPage(email: email, service: auth)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '04821');
    await tester.pump();
    expect(auth.tried, isEmpty);
  });

  testWidgets('at login, the right code opens the app', (tester) async {
    final auth = _FakeAuth();
    var opened = false;
    await tester.pumpWidget(
      _app(
        VerifyEmailPage(
          email: email,
          service: auth,
          onVerified: () async => opened = true,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '048213');
    await tester.pump();
    expect(opened, isTrue);
    expect(find.text('Email verified'), findsNothing);
  });

  testWidgets('resend waits for the cooldown, then sends a new code', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(VerifyEmailPage(email: email, service: auth)));
    await tester.pump();

    await tester.pump(const Duration(seconds: 60));
    await tester.ensureVisible(find.text('resend code'));
    await tester.tap(find.text('resend code'));
    await tester.pump();

    expect(auth.codesSent, 2);
    expect(find.textContaining('We sent a new code'), findsOneWidget);
    expect(find.text('resend in 1:00'), findsOneWidget);
  });

  testWidgets('reopened too soon: waits without an error', (tester) async {
    final auth = _FakeAuth()
      ..sendError = const VerificationCodeException(
        'Please wait 40 seconds before asking for a new code.',
        statusCode: 429,
        retryAfter: 40,
      );
    await tester.pumpWidget(_app(VerifyEmailPage(email: email, service: auth)));
    await tester.pump();

    expect(find.text('resend in 0:40'), findsOneWidget);
    expect(find.textContaining('Please wait'), findsNothing);
  });

  testWidgets('no Open-inbox button for unknown email providers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(VerifyEmailPage(email: 'thandi@uni.ac.za', service: _FakeAuth())),
    );
    await tester.pump();

    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    expect(find.text('Paste code'), findsOneWidget);
  });
}
