import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/splash_screen.dart';
import 'package:theo_tutoring_app/main.dart';
import 'package:theo_tutoring_app/services/auth_service.dart';

/// Nobody signed in, without touching Firebase.
class _SignedOutAuth extends AuthService {
  @override
  Future<User?> restoredUser() async => null;

  @override
  Stream<User?> authStateChanges() => const Stream.empty();
}

/// Counts how often the splash continued to it.
class _Next extends StatefulWidget {
  const _Next(this.opened);
  final List<int> opened;

  @override
  State<_Next> createState() => _NextState();
}

class _NextState extends State<_Next> {
  @override
  void initState() {
    super.initState();
    widget.opened.add(1);
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('next screen'));
}

Future<List<int>> _pumpSplash(WidgetTester tester) async {
  final opened = <int>[];
  await tester.pumpWidget(
    MaterialApp(home: SplashScreen(next: (_) => _Next(opened))),
  );
  return opened;
}

final _continue = find.widgetWithText(ElevatedButton, 'Continue');

void main() {
  testWidgets('shows the TheoTutoring branding and animates it in', (
    tester,
  ) async {
    await _pumpSplash(tester);
    // Late in the animation (5.1 of 6.2 s) everything is on screen.
    await tester.pump(const Duration(milliseconds: 5100));
    expect(find.text('TheoTutoring'), findsOneWidget);
    expect(find.text('UNLOCKING YOUR POTENTIAL'), findsOneWidget);
    expect(find.textContaining('brings university students'), findsOneWidget);
    expect(_continue, findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets); // the open book
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays on screen after the animation until Continue', (
    tester,
  ) async {
    final opened = await _pumpSplash(tester);
    await tester.pumpAndSettle(); // the whole animation has finished
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(opened, isEmpty); // no automatic navigation
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('UNLOCKING YOUR POTENTIAL'), findsOneWidget);
    // The button is still there and works.
    expect(tester.widget<ElevatedButton>(_continue).onPressed, isNotNull);
    await tester.tap(_continue);
    await tester.pumpAndSettle();
    expect(opened, [1]);
    expect(find.text('next screen'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('Continue navigates exactly once, even when tapped repeatedly', (
    tester,
  ) async {
    final opened = await _pumpSplash(tester);
    await tester.pumpAndSettle();
    // Several taps before the transition has finished.
    await tester.tap(_continue);
    await tester.pump();
    await tester.tap(_continue, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_continue, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(opened, [1]);
    expect(find.text('next screen'), findsOneWidget);
    // Nothing more happens later either.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(opened, [1]);
  });

  testWidgets('it replaces itself: Back cannot return to the splash', (
    tester,
  ) async {
    await _pumpSplash(tester);
    await tester.pumpAndSettle();
    await tester.tap(_continue);
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('the app opens on the splash, then the existing entry', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(authService: _SignedOutAuth()));
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Log In'), findsNothing);

    await tester.tap(_continue);
    await tester.pumpAndSettle();
    // Signed out: the app's own Log In / Register screen, unchanged.
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Log In'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Register'), findsOneWidget);
  });
}
