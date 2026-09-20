import 'package:test/test.dart';

import '../../../routes/students/register.dart';

void main() {
  group('validateStudentRegistration', () {
    test('accepts a complete registration', () {
      expect(validateStudentRegistration(_validRegistration), isEmpty);
    });

    test('rejects missing fields, invalid email, short password, and terms', () {
      final errors = validateStudentRegistration({
        ..._validRegistration,
        'fullName': ' ',
        'email': 'invalid-email',
        'password': 'short',
        'confirmPassword': 'different',
        'termsAccepted': false,
      });

      expect(errors['fullName'], isNotNull);
      expect(errors['email'], isNotNull);
      expect(errors['password'], isNotNull);
      expect(errors['confirmPassword'], isNotNull);
      expect(errors['termsAccepted'], isNotNull);
    });

    test('rejects non-string field values', () {
      final errors = validateStudentRegistration({
        ..._validRegistration,
        'phone': 123456789,
      });

      expect(errors['phone'], 'This field is required.');
    });
  });
}

const _validRegistration = <String, dynamic>{
  'fullName': 'Ada Lovelace',
  'email': 'ada@example.com',
  'password': 'correct horse battery staple',
  'confirmPassword': 'correct horse battery staple',
  'phone': '+1234567890',
  'address': '1 Analytical Engine Way',
  'institutionYear': 'Year 2',
  'course': 'Computer Science',
  'tutoringModule': 'Algorithms',
  'termsAccepted': true,
};