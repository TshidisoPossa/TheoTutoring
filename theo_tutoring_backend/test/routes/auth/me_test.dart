import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';
// Same import as the route, so AuthTokenException is the same type.
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/auth/me.dart' as me;

// GET /auth/me with a fake identity and database.

class _MockRequestContext extends Mock implements RequestContext {}

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

MySQLConnection _db(Map<String, String?>? user) {
  final connection = _MockConnection();
  final result = _MockResult();
  final rows = <ResultSetRow>[];
  if (user != null) {
    final row = _MockRow();
    when(() => row.colByName(any())).thenAnswer(
      (call) => user[call.positionalArguments.first as String],
    );
    rows.add(row);
  }
  when(() => result.rows).thenReturn(rows);
  when(() => connection.execute(any(), any())).thenAnswer((call) async {
    final params = call.positionalArguments[1] as Map<String, dynamic>;
    expect(params['uid'], 'firebase-uid');
    return result;
  });
  return connection;
}

Map<String, String?> _user(
  String role, {
  String status = 'Active',
  String? studentId,
  String? tutorId,
  String? adminId,
}) => {
  'UserId': '12',
  'Name': 'Thandi Mokoena',
  'Email': 'thandi@example.com',
  'Role': role,
  'AccountStatus': status,
  'StudentID': studentId,
  'TutorID': tutorId,
  'AdminID': adminId,
};

RequestContext _request(String method, {String? authorization}) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/auth/me'),
      headers: {if (authorization != null) 'Authorization': authorization},
    ),
  );
  return context;
}

Future<FirebaseUser> _verified(String? _) async => const FirebaseUser(
  uid: 'firebase-uid',
  email: 'thandi@example.com',
  emailVerified: true,
);

Future<FirebaseUser> _unverified(String? _) async => const FirebaseUser(
  uid: 'firebase-uid',
  email: 'thandi@example.com',
  emailVerified: false,
);

void main() {
  group('GET /auth/me', () {
    Future<Response> get(
      Map<String, String?>? user, {
      Future<FirebaseUser> Function(String?) tokenVerifier = _verified,
    }) => me.handleAuthMe(
      _request('GET', authorization: 'Bearer test'),
      tokenVerifier: tokenVerifier,
      connectionFactory: () async => _db(user),
    );

    test('only GET is allowed', () async {
      final response = await me.handleAuthMe(
        _request('POST', authorization: 'Bearer test'),
        tokenVerifier: _verified,
        connectionFactory: () async => _db(null),
      );
      expect(response.statusCode, 405);
    });

    test('a missing Firebase token is a 401', () async {
      final response = await me.handleAuthMe(
        _request('GET'),
        connectionFactory: () async => _db(null),
      );
      expect(response.statusCode, 401);
    });

    test('an invalid Firebase token is a 401', () async {
      final response = await get(
        _user('student', studentId: '4'),
        tokenVerifier: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
      );
      expect(response.statusCode, 401);
      expect(await response.json(), {'error': 'Invalid sign-in token.'});
    });

    test('a student gets their role, status and student id', () async {
      final response = await get(_user('student', studentId: '4'));
      expect(response.statusCode, 200);
      expect(await response.json(), {
        'userId': 12,
        'role': 'student',
        'accountStatus': 'Active',
        'name': 'Thandi Mokoena',
        'email': 'thandi@example.com',
        'emailVerified': true,
        'studentId': 4,
      });
    });

    test('a tutor gets their tutor id and real status', () async {
      final response = await get(
        _user('tutor', status: 'Pending', tutorId: '7'),
      );
      final body = await response.json() as Map<String, dynamic>;
      expect(response.statusCode, 200);
      expect(body['role'], 'tutor');
      expect(body['accountStatus'], 'Pending');
      expect(body['tutorId'], 7);
      expect(body.containsKey('studentId'), isFalse);
    });

    test('an admin gets their admin id', () async {
      final response = await get(_user('admin', adminId: '2'));
      final body = await response.json() as Map<String, dynamic>;
      expect(body['role'], 'admin');
      expect(body['adminId'], 2);
    });

    test('emailVerified comes from the Firebase token', () async {
      final response = await get(
        _user('student', studentId: '4'),
        tokenVerifier: _unverified,
      );
      final body = await response.json() as Map<String, dynamic>;
      expect(body['emailVerified'], false);
    });

    test('a Firebase account with no MySQL user is a 404', () async {
      final response = await get(null);
      expect(response.statusCode, 404);
    });

    test('a user without the profile for their role is a 404', () async {
      final response = await get(_user('student'));
      expect(response.statusCode, 404);
    });
  });
}
