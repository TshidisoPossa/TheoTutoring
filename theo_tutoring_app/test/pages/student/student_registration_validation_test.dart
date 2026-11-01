import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/registration_validators.dart';
import 'package:theo_tutoring_app/Pages/student_registration.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: StudentRegistrationPage()));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String hint, String text) =>
    tester.enterText(find.widgetWithText(TextFormField, hint), text);

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tester.tap(find.text('Create Account'));
  await tester.pumpAndSettle();
}

void main() {
  group('shared registration validators', () {
    test('email', () {
      expect(validateRegistrationEmail(''), 'Please enter your email address.');
      expect(
        validateRegistrationEmail('student@'),
        'Enter a valid email address.',
      );
      expect(
        validateRegistrationEmail('a b@uj.ac.za'),
        'Enter a valid email address.',
      );
      expect(validateRegistrationEmail(' student@uj.ac.za '), isNull);
    });

    test('password confirmation', () {
      expect(
        validateRegistrationPasswordConfirmation('', 'Secret123'),
        'Please confirm your password.',
      );
      expect(
        validateRegistrationPasswordConfirmation('Secret124', 'Secret123'),
        'Passwords do not match.',
      );
      expect(
        validateRegistrationPasswordConfirmation('Secret123', 'Secret123'),
        isNull,
      );
      expect(
        validateRegistrationPassword('short'),
        'Password must be at least 8 characters.',
      );
    });

    test('phone must have 8–15 digits', () {
      const message = 'Enter a valid phone number with 8–15 digits.';
      expect(validateRegistrationPhone(''), 'Please enter your phone number.');
      expect(validateRegistrationPhone('1234567'), message);
      expect(validateRegistrationPhone('1234567890123456'), message);
      expect(validateRegistrationPhone('082-abc-4567'), message);
      expect(validateRegistrationPhone('12345678'), isNull);
      expect(validateRegistrationPhone('123456789012345'), isNull);
      expect(validateRegistrationPhone('+27 82 123 4567'), isNull);
    });
  });

  testWidgets('invalid account fields show field-level errors', (tester) async {
    await _pump(tester);

    await _enter(tester, 'Enter your full name', 'Lerato Mokoena');
    await _enter(tester, 'Enter your email address', 'lerato@');
    await _enter(tester, 'Enter your password', 'Secret123');
    await _enter(tester, 'Confirm your password', 'Secret124');
    await _enter(tester, 'Enter your phone number', '1234567');
    await _submit(tester);

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(
      find.text('Enter a valid phone number with 8–15 digits.'),
      findsOneWidget,
    );
    expect(find.text('Please correct the highlighted fields.'), findsOneWidget);
  });

  testWidgets('empty submission flags each account field', (tester) async {
    await _pump(tester);
    await _submit(tester);

    expect(find.text('Please enter your full name.'), findsOneWidget);
    expect(find.text('Please enter your email address.'), findsOneWidget);
    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
    expect(find.text('Please confirm your password.'), findsOneWidget);
    expect(find.text('Please enter your phone number.'), findsOneWidget);
  });

  testWidgets('valid account fields fall through to the other checks', (
    tester,
  ) async {
    await _pump(tester);

    await _enter(tester, 'Enter your full name', 'Lerato Mokoena');
    await _enter(tester, 'Enter your email address', 'lerato@uj.ac.za');
    await _enter(tester, 'Enter your password', 'Secret123');
    await _enter(tester, 'Confirm your password', 'Secret123');
    await _enter(tester, 'Enter your phone number', '+27 82 123 4567');
    await _submit(tester);

    expect(find.text('Please correct the highlighted fields.'), findsNothing);
    expect(find.text('Please complete all required fields.'), findsOneWidget);
  });
}
