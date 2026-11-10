import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/login_page.dart';
import 'package:theo_tutoring_app/Pages/role_selection.dart';
import 'package:theo_tutoring_app/main.dart';
import 'package:theo_tutoring_app/services/auth_service.dart';

/// Nobody signed in, without touching Firebase.
class _SignedOutAuth extends AuthService {
  @override
  Future<User?> restoredUser() async => null;

  @override
  Stream<User?> authStateChanges() => const Stream.empty();
}

void main() {
  testWidgets('signed out, the app opens on the splash screen', (tester) async {
    await tester.pumpWidget(MyApp(authService: _SignedOutAuth()));
    await tester.pumpAndSettle();

    expect(find.text('TheoTutoring'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Log In'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Register'), findsOneWidget);
  });

  testWidgets('Log In opens the login screen', (tester) async {
    await tester.pumpWidget(MyApp(authService: _SignedOutAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('Register opens role selection', (tester) async {
    await tester.pumpWidget(MyApp(authService: _SignedOutAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Register'));
    await tester.pumpAndSettle();
    expect(find.byType(RoleSelectionPage), findsOneWidget);
  });
}
