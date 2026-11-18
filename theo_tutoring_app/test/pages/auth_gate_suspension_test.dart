import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/account_suspension_page.dart';
import 'package:theo_tutoring_app/Pages/auth_gate.dart';
import 'package:theo_tutoring_app/Pages/Student/student_dashboard.dart';
import 'package:theo_tutoring_app/services/account_suspension_api.dart';
import 'package:theo_tutoring_app/services/auth_service.dart';

class _FakeUser implements User {
  @override
  String get uid => 'uid-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A signed-in user whose /auth/me answer is [status]; no Firebase.
class _Auth extends AuthService {
  _Auth(this.role, this.status);
  final String role;
  String status;
  int signOuts = 0;

  @override
  Future<User?> restoredUser() async => _FakeUser();

  @override
  Stream<User?> authStateChanges() => const Stream.empty();

  @override
  User? get currentUser => _FakeUser();

  @override
  Future<SignedInAccount> fetchAccount() async => SignedInAccount(
    userId: 1,
    role: role,
    accountStatus: status,
    name: 'Lerato',
    email: 'lerato@example.test',
    emailVerified: true,
  );

  @override
  Future<String> idToken({bool refresh = false}) async => 'token';

  @override
  Future<void> signOut() async => signOuts++;
}

AccountSuspensionApi _api({bool suspended = true}) => AccountSuspensionApi(
  tokenProvider: () async => 'token',
  client: MockClient(
    (_) async => http.Response(
      jsonEncode({
        'role': 'student',
        'accountStatus': suspended ? 'Suspended' : 'Active',
        'suspension': {
          'suspensionId': 1,
          'reason': 'Repeated no-shows for booked lessons.',
          'suspendedAt': '2026-11-10T08:30:00Z',
          'status': suspended ? 'Active' : 'Lifted',
        },
        'appeal': null,
        'canAppeal': suspended,
      }),
      200,
    ),
  ),
);

void main() {
  for (final role in ['student', 'tutor']) {
    testWidgets('a suspended $role sees the suspension screen, not the app', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = _Auth(role, 'Suspended');
      await tester.pumpWidget(
        MaterialApp(home: AuthGate(service: auth, suspensionApi: _api())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AccountSuspensionPage), findsOneWidget);
      expect(
        find.text('Repeated no-shows for booked lessons.'),
        findsOneWidget,
      );
      expect(find.text('Appeal this suspension'), findsOneWidget);
      expect(find.byType(StudentDashboard), findsNothing);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
      expect(find.byType(AccountSuspensionPage), findsNothing);
    });
  }

  testWidgets('a deactivated account still gets the plain message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          service: _Auth('student', 'Deactivated'),
          suspensionApi: _api(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccountSuspensionPage), findsNothing);
    expect(
      find.text('This account is not active. Please contact support.'),
      findsOneWidget,
    );
  });
}
