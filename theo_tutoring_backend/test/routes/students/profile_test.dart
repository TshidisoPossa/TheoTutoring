import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';
// Same import as the route, so AuthTokenException is the same type.
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/students/profile.dart' as profile;

// GET and PATCH /students/profile with a fake identity and database.

class _MockRequestContext extends Mock implements RequestContext {}

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

const _photo = 'https://res.cloudinary.com/demo/image/upload/lerato.jpg';

Map<String, String?> _lerato() => {
  'UserId': '7',
  'Name': 'Lerato Dube',
  'Email': 'lerato@example.com',
  'ProfilePhoto': _photo,
  'Institution': 'University of Pretoria',
  'Subject_of_interest': 'Mathematics, Physics ,',
};

/// A fake database holding [student] (null: no active student). UPDATEs
/// change the row, so the PATCH answer shows the saved values, and are
/// recorded in [updates].
class _FakeDb {
  _FakeDb(this.student);

  final Map<String, String?>? student;
  final updates = <({String sql, Map<String, dynamic> params})>[];

  MySQLConnection connection() {
    final connection = _MockConnection();
    when(() => connection.execute(any(), any())).thenAnswer((call) async {
      final sql = call.positionalArguments[0] as String;
      final params = call.positionalArguments[1] as Map<String, dynamic>;
      final result = _MockResult();
      if (sql.trimLeft().startsWith('UPDATE')) {
        updates.add((sql: sql, params: params));
        _apply(sql, params);
        when(() => result.rows).thenReturn(const []);
        return result;
      }
      // Only the signed-in, active student's own row
      expect(params['uid'], 'firebase-uid');
      expect(sql, contains("u.Role = 'student'"));
      expect(sql, contains("u.AccountStatus = 'Active'"));
      final rows = <ResultSetRow>[];
      if (student != null) {
        final row = _MockRow();
        final snapshot = Map<String, String?>.of(student!);
        when(() => row.colByName(any())).thenAnswer(
          (c) => snapshot[c.positionalArguments.first as String],
        );
        rows.add(row);
      }
      when(() => result.rows).thenReturn(rows);
      return result;
    });
    return connection;
  }

  void _apply(String sql, Map<String, dynamic> params) {
    const columns = {
      'name': 'Name',
      'photo': 'ProfilePhoto',
      'institution': 'Institution',
      'subjects': 'Subject_of_interest',
    };
    for (final entry in columns.entries) {
      if (params.containsKey(entry.key)) {
        student![entry.value] = params[entry.key] as String?;
      }
    }
  }
}

RequestContext _request(
  String method, {
  String? authorization,
  Object? body,
}) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/students/profile'),
      headers: {if (authorization != null) 'Authorization': authorization},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  return context;
}

Future<FirebaseUser> _verified(String? _) async => const FirebaseUser(
  uid: 'firebase-uid',
  email: 'lerato@example.com',
  emailVerified: true,
);

void main() {
  group('GET /students/profile', () {
    Future<Response> get(
      Map<String, String?>? student, {
      Future<FirebaseUser> Function(String?) tokenVerifier = _verified,
    }) => profile.handleStudentProfile(
      _request('GET', authorization: 'Bearer test'),
      tokenVerifier: tokenVerifier,
      connectionFactory: () async => _FakeDb(student).connection(),
    );

    test('returns the details the Profile tab shows', () async {
      final response = await get(_lerato());
      expect(response.statusCode, 200);
      expect(await response.json(), {
        'name': 'Lerato Dube',
        'email': 'lerato@example.com',
        'photo': _photo,
        'institution': 'University of Pretoria',
        'subjectsOfInterest': ['Mathematics', 'Physics'],
      });
    });

    test('blank details come back as null or an empty list', () async {
      final response = await get({
        ..._lerato(),
        'ProfilePhoto': '  ',
        'Institution': null,
        'Subject_of_interest': '',
      });
      final body = await response.json() as Map<String, dynamic>;
      expect(response.statusCode, 200);
      expect(body['photo'], isNull);
      expect(body['institution'], isNull);
      expect(body['subjectsOfInterest'], isEmpty);
    });

    test('a tutor, admin or suspended student gets a 403', () async {
      final response = await get(null);
      expect(response.statusCode, 403);
      expect(await response.json(), {
        'error': 'An active student account is required.',
      });
    });

    test('a missing Firebase token is a 401', () async {
      final response = await profile.handleStudentProfile(
        _request('GET'),
        connectionFactory: () async => _FakeDb(null).connection(),
      );
      expect(response.statusCode, 401);
    });

    test('an invalid Firebase token is a 401', () async {
      final response = await get(
        null,
        tokenVerifier: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
      );
      expect(response.statusCode, 401);
      expect(await response.json(), {'error': 'Invalid sign-in token.'});
    });

    test('a database failure is a 500 without the details', () async {
      final response = await profile.handleStudentProfile(
        _request('GET', authorization: 'Bearer test'),
        tokenVerifier: _verified,
        connectionFactory: () async => throw StateError('db down'),
      );
      expect(response.statusCode, 500);
      expect(await response.json(), {
        'error': 'Your profile is temporarily unavailable.',
      });
    });

    test('only GET and PATCH are allowed', () async {
      final response = await profile.handleStudentProfile(
        _request('POST', authorization: 'Bearer test'),
        tokenVerifier: _verified,
        connectionFactory: () async => _FakeDb(null).connection(),
      );
      expect(response.statusCode, 405);
    });
  });

  group('PATCH /students/profile', () {
    late _FakeDb db;

    Future<Response> patch(Object? body, {Map<String, String?>? student}) {
      db = _FakeDb(student ?? _lerato());
      return profile.handleStudentProfile(
        _request('PATCH', authorization: 'Bearer test', body: body),
        tokenVerifier: _verified,
        connectionFactory: () async => db.connection(),
        cloudName: () => 'demo',
      );
    }

    test('Save Changes stores every field and returns the profile', () async {
      final response = await patch({
        'name': '  Lerato Pillay ',
        'institution': 'Hyde Park High School',
        'subjectsOfInterest': ['Mathematics', 'Chemistry', 'mathematics', ''],
      });

      expect(response.statusCode, 200);
      final body = await response.json() as Map<String, dynamic>;
      expect(body['message'], 'Your profile has been saved.');
      expect(body['name'], 'Lerato Pillay');
      expect(body['institution'], 'Hyde Park High School');
      expect(body['subjectsOfInterest'], ['Mathematics', 'Chemistry']);

      // Only this student's rows
      expect(db.updates, hasLength(2));
      for (final update in db.updates) {
        expect(update.params['userId'], '7');
      }
      expect(db.updates.first.sql, contains('UPDATE `User`'));
      expect(db.updates.first.sql, isNot(contains('ProfilePhoto')));
      expect(db.updates.last.params['subjects'], 'Mathematics, Chemistry');
    });

    test('the camera badge saves only the photo', () async {
      const newPhoto = 'https://res.cloudinary.com/demo/image/upload/new.png';
      final response = await patch({'photo': newPhoto});

      expect(response.statusCode, 200);
      final body = await response.json() as Map<String, dynamic>;
      expect(body['message'], 'Profile photo updated.');
      expect(body['photo'], newPhoto);
      expect(body['name'], 'Lerato Dube');
      expect(db.updates, hasLength(1));
      expect(db.updates.single.sql, isNot(contains('Name')));
    });


    final invalid = <String, (Object?, String)>{
      'a blank name': ({'name': '  '}, 'Your name cannot be empty.'),
      'a blank school': (
        {'institution': ''},
        'Your school or university cannot be empty.',
      ),
      'no subjects': (
        {'subjectsOfInterest': <String>[]},
        'Choose at least one subject.',
      ),
      'too many subjects': (
        {
          'subjectsOfInterest': [for (var i = 0; i < 11; i++) 'Subject $i'],
        },
        'Choose up to 10 subjects of interest.',
      ),
      'subjects that are not a list': (
        {'subjectsOfInterest': 'Maths'},
        'subjectsOfInterest must be a list of text.',
      ),
      'a photo from elsewhere': (
        {'photo': 'https://example.com/me.jpg'},
        'Profile photo must be a file uploaded through the app.',
      ),
      'nothing to change': (<String, Object?>{}, 'Nothing to update.'),
      'a body that is not an object': (
        ['name'],
        'Request body must be a JSON object.',
      ),
    };
    for (final MapEntry(key: name, value: (body, message)) in invalid.entries) {
      test('$name is a 400 and saves nothing', () async {
        final response = await patch(body);
        expect(response.statusCode, 400);
        expect(await response.json(), {'error': message});
        expect(db.updates, isEmpty);
      });
    }

    test('a tutor or suspended student gets a 403', () async {
      db = _FakeDb(null);
      final response = await profile.handleStudentProfile(
        _request(
          'PATCH',
          authorization: 'Bearer test',
          body: {'name': 'Someone'},
        ),
        tokenVerifier: _verified,
        connectionFactory: () async => db.connection(),
      );
      expect(response.statusCode, 403);
      expect(db.updates, isEmpty);
    });

    test('a database failure is a 500 without the details', () async {
      final response = await profile.handleStudentProfile(
        _request(
          'PATCH',
          authorization: 'Bearer test',
          body: {'name': 'Lerato'},
        ),
        tokenVerifier: _verified,
        connectionFactory: () async => throw StateError('db down'),
      );
      expect(response.statusCode, 500);
      expect(await response.json(), {
        'error': 'Your profile could not be saved. Please try again.',
      });
    });
  });
}
