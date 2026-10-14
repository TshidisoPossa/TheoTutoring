import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/tutor_account_status.dart';

import '../../../../routes/auth/tutor/availability.dart' as availability;
import '../../../../routes/auth/tutor/profile.dart' as profile;
import '../../../../routes/auth/tutor/register.dart' as registration;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('tutor account status access', () {
    const restricted = [
      'Incomplete',
      'Pending',
      'Rejected',
      'Suspended',
      'Deactivated',
    ];

    test('only Active tutors can access tutor landing routes', () {
      expect(canAccessTutorLandingPage('Active'), isTrue);
      for (final status in restricted) {
        expect(canAccessTutorLandingPage(status), isFalse, reason: status);
      }
      expect(canAccessTutorLandingPage(null), isFalse);
    });

    test('only Incomplete accounts can submit the profile step', () {
      expect(canUpdateTutorRegistrationProfile('Incomplete'), isTrue);
      for (final status in ['Pending', 'Active', ...restricted.skip(2)]) {
        expect(
          canUpdateTutorRegistrationProfile(status),
          isFalse,
          reason: status,
        );
      }
    });

    test('availability accepts Incomplete and Pending only', () {
      expect(canSubmitTutorAvailability('Incomplete'), isTrue);
      expect(canSubmitTutorAvailability('Pending'), isTrue);
      for (final status in ['Active', 'Rejected', 'Suspended', 'Deactivated']) {
        expect(canSubmitTutorAvailability(status), isFalse, reason: status);
      }
    });
  });

  group('POST /auth/tutor/register', () {
    test('requires Firebase authentication', () async {
      expect(
        (await registration.onRequest(_context())).statusCode,
        401,
      );
    });

    test('validates tutor details without accepting client credentials', () {
      expect(
        registration.validateTutorRegistration({
          'name': 'Ada Lovelace',
          'phoneNum': '1234567890',
        }),
        isEmpty,
      );
      final errors = registration.validateTutorRegistration({
        'name': '',
        'phoneNum': 123,
      });
      expect(errors.keys, contains('name'));
      expect(errors.keys, contains('phoneNum'));
    });
  });

  group('POST /auth/tutor/profile', () {
    test('requires Firebase authentication', () async {
      expect((await profile.onRequest(_context())).statusCode, 401);
    });
  });

  group('POST /auth/tutor/availability', () {
    test('requires Firebase authentication', () async {
      expect((await availability.onRequest(_context())).statusCode, 401);
    });

    test('accepts valid slots and rejects invalid or overlapping slots', () {
      expect(
        availability.parseTutorAvailabilitySlots([
          {'day': 'Monday', 'startTime': '09:00', 'endTime': '10:00'},
          {'day': 'Monday', 'startTime': '10:00', 'endTime': '11:00'},
        ]),
        hasLength(2),
      );
      expect(
        () => availability.parseTutorAvailabilitySlots([
          {'day': 'Sunday', 'startTime': '09:00', 'endTime': '10:00'},
        ]),
        throwsFormatException,
      );
      expect(
        () => availability.parseTutorAvailabilitySlots([
          {'day': 'Monday', 'startTime': '09:00', 'endTime': '10:00'},
          {'day': 'Monday', 'startTime': '09:30', 'endTime': '10:30'},
        ]),
        throwsFormatException,
      );
    });
  });
}

RequestContext _context() {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request.post(Uri.parse('http://localhost/auth/tutor/register')),
  );
  return context;
}
