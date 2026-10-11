import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/students/register.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('POST /students/register', () {
    test('rejects a missing Firebase ID token', () async {
      final context = _context();
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/students/register'),
          body: jsonEncode(_validRegistration),
        ),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, 401);
    });

    test('rejects an invalid Firebase ID token', () async {
      final context = _context();
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/students/register'),
          headers: {'authorization': 'Bearer not-a-jwt'},
          body: jsonEncode(_validRegistration),
        ),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, 401);
    });

    test('rejects invalid student details', () {
      final errors = route.validateStudentRegistration({
        ..._validRegistration,
        'fullName': '',
        'email': 'not-an-email',
        'institutionYear': 'This year value is too long',
        'termsAccepted': false,
      });

      expect(errors['fullName'], isNotNull);
      expect(errors['email'], isNotNull);
      expect(errors['institutionYear'], isNotNull);
      expect(errors['termsAccepted'], isNotNull);
    });

    test('requires institutionYear and validates optional URLs', () {
      final errors = route.validateStudentRegistration({
        ..._validRegistration,
        'institutionYear': null,
        'profilePhotoUrl': 'javascript:alert(1)',
        'proofOfRegistrationUrl': 'javascript:alert(1)',
      });

      expect(errors['institutionYear'], isNotNull);
      expect(errors['profilePhotoUrl'], isNotNull);
      expect(errors['proofOfRegistrationUrl'], isNotNull);
    });

    test('requires proof of registration URL', () {
      for (final url in [null, '', '   ']) {
        expect(
          route.validateStudentRegistration({
            ..._validRegistration,
            'proofOfRegistrationUrl': url,
          })['proofOfRegistrationUrl'],
          isNotNull,
        );
      }
      expect(
        route.validateStudentRegistration(
          Map.of(_validRegistration)..remove('proofOfRegistrationUrl'),
        )['proofOfRegistrationUrl'],
        isNotNull,
      );
    });

    test('rejects proof URLs longer than the schema limit', () {
      final url = 'https://example.com/${List.filled(240, 'a').join()}';
      expect(url.length, greaterThan(255));
      expect(
        route.validateStudentRegistration({
          ..._validRegistration,
          'proofOfRegistrationUrl': url,
        })['proofOfRegistrationUrl'],
        isNotNull,
      );
    });

    test('accepts valid details without a password', () {
      expect(route.validateStudentRegistration(_validRegistration), isEmpty);
    });

    test('accepts uploaded Firebase Storage URLs', () {
      expect(
        route.validateStudentRegistration({
          ..._validRegistration,
          'profilePhotoUrl': 'https://storage.example/photo.jpg',
          'proofOfRegistrationUrl': 'https://storage.example/proof.pdf',
        }),
        isEmpty,
      );
    });

    test('accepts absent, blank, and valid profile-photo URLs', () {
      for (final value in [null, '', '   ', 'https://example.com/photo']) {
        expect(
          route.validateStudentRegistration({
            ..._validRegistration,
            'profilePhotoUrl': value,
          }),
          isEmpty,
        );
      }
    });

    test('rejects non-string or invalid profile-photo URLs', () {
      for (final value in [123, 'ftp://example.com/photo']) {
        expect(
          route.validateStudentRegistration({
            ..._validRegistration,
            'profilePhotoUrl': value,
          })['profilePhotoUrl'],
          isNotNull,
        );
      }
    });

    test('rejects profile-photo URLs over 255 characters', () {
      final url = 'https://example.com/${List.filled(240, 'a').join()}';
      expect(
        route.validateStudentRegistration({
          ..._validRegistration,
          'profilePhotoUrl': url,
        })['profilePhotoUrl'],
        isNotNull,
      );
    });
  });
}

_MockRequestContext _context() => _MockRequestContext();

const _validRegistration = <String, dynamic>{
  'fullName': 'Ada Lovelace',
  'email': 'ada@example.com',
  'phone': '1234567890',
  'address': '1 Analytical Engine Way',
  'institutionYear': 'Year 2',
  'course': 'Computer Science',
  'tutoringModule': 'Algorithms',
  'proofOfRegistrationUrl': 'https://storage.example/proof.pdf',
  'termsAccepted': true,
};
