import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';

// Same imports as the routes, so they are the same types.
import '../../../../lib/firebase_auth.dart';
import '../../../../lib/google_meet.dart';
import '../../../../routes/auth/tutor/availability.dart' as availability;
import '../../../../routes/auth/tutor/meet-link.dart' as meet_link;

// POST /auth/tutor/meet-link (registration Step 3) with a fake identity,
// database and Google. No real rooms, tokens or database are used.

class _MockRequestContext extends Mock implements RequestContext {}

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

const _room = 'https://meet.google.com/abc-mnop-xyz';

/// One tutor in a pretend TutorProfile: answers the route's SELECT with
/// [row] and keeps whatever the UPDATE saves in [meetLink].
class _FakeDb {
  _FakeDb(this.row) {
    final selected = _MockResult();
    final rows = [if (row != null) _row(row!)];
    when(() => selected.rows).thenReturn(rows);
    final updated = _MockResult();
    when(() => updated.rows).thenReturn(const []);
    when(() => connection.execute(any(), any())).thenAnswer((call) async {
      final sql = call.positionalArguments[0] as String;
      final params = call.positionalArguments[1] as Map<String, dynamic>?;
      if (sql.contains('UPDATE TutorProfile SET MeetLink')) {
        expect(params!['tutorId'], 7);
        meetLink = params['link'] as String?;
        return updated;
      }
      return selected;
    });
  }

  final Map<String, String?>? row;
  final connection = _MockConnection();
  String? meetLink;
}

ResultSetRow _row(Map<String, String?> values) {
  final row = _MockRow();
  when(() => row.colByName(any())).thenAnswer(
    (call) => values[call.positionalArguments.first as String],
  );
  return row;
}

Map<String, String?> _tutor(String status) => {
  'TutorID': '7',
  'AccountStatus': status,
};

RequestContext _post(String path, Object? body, {String? authorization}) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      'POST',
      Uri.parse('http://localhost$path'),
      headers: {if (authorization != null) 'Authorization': authorization},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  return context;
}

Future<FirebaseUser> _signedIn(String? _) async => const FirebaseUser(
  uid: 'tutor-uid',
  email: 't@x.test',
  emailVerified: true,
);

void main() {
  group('POST /auth/tutor/meet-link', () {
    var roomsMade = 0;

    Future<String> google(String token) async {
      expect(token, 'google-token');
      roomsMade++;
      return roomsMade == 1 ? _room : 'https://meet.google.com/new-room-two';
    }

    Future<Response> connect(
      _FakeDb db, {
      Object? body = const {'accessToken': 'google-token'},
      Future<FirebaseUser> Function(String?) tokenVerifier = _signedIn,
      Future<String> Function(String)? roomCreator,
    }) {
      return meet_link.handleTutorMeetLink(
        _post('/auth/tutor/meet-link', body, authorization: 'Bearer test'),
        tokenVerifier: tokenVerifier,
        connectionFactory: () async => db.connection,
        roomCreator: roomCreator ?? google,
      );
    }

    setUp(() => roomsMade = 0);

    test('a missing Firebase token is a 401', () async {
      final db = _FakeDb(_tutor('Incomplete'));
      final response = await meet_link.handleTutorMeetLink(
        _post('/auth/tutor/meet-link', {'accessToken': 'google-token'}),
        connectionFactory: () async => db.connection,
        roomCreator: google,
      );
      expect(response.statusCode, 401);
      expect(roomsMade, 0);
    });

    test('an invalid Firebase token is a 401', () async {
      final response = await connect(
        _FakeDb(_tutor('Incomplete')),
        tokenVerifier: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
      );
      expect(response.statusCode, 401);
      expect(await response.json(), {'error': 'Invalid sign-in token.'});
      expect(roomsMade, 0);
    });

    test('an account that is not registering is refused', () async {
      for (final status in ['Active', 'Suspended']) {
        final db = _FakeDb(_tutor(status));
        final response = await connect(db);
        expect(response.statusCode, 403, reason: status);
        expect(db.meetLink, isNull);
      }
      expect(roomsMade, 0);
    });

    test('a Firebase user with no tutor account is a 404', () async {
      final response = await connect(_FakeDb(null));
      expect(response.statusCode, 404);
      expect(roomsMade, 0);
    });

    test('a missing Google token is a 400 and nothing is saved', () async {
      for (final body in [
        <String, dynamic>{},
        {'accessToken': '  '},
      ]) {
        final db = _FakeDb(_tutor('Incomplete'));
        final response = await connect(db, body: body);
        expect(response.statusCode, 400);
        expect(await response.json(), {
          'error': "Google Meet wasn't connected. Please try again.",
        });
        expect(db.meetLink, isNull);
      }
      expect(roomsMade, 0);
    });

    test('saves the new room as the tutor link', () async {
      final db = _FakeDb(_tutor('Incomplete'));
      final response = await connect(db);
      expect(response.statusCode, 200);
      expect(await response.json(), {'meetConnected': true});
      expect(db.meetLink, _room);
    });

    test('pending and rejected tutors can connect too', () async {
      for (final status in ['Pending', 'Rejected']) {
        final db = _FakeDb(_tutor(status));
        expect((await connect(db)).statusCode, 200, reason: status);
        expect(db.meetLink, isNotNull);
      }
    });

    test('connecting again replaces the existing link', () async {
      final db = _FakeDb(_tutor('Incomplete'));
      await connect(db);
      expect(db.meetLink, _room);
      expect((await connect(db)).statusCode, 200);
      expect(db.meetLink, 'https://meet.google.com/new-room-two');
    });

    test('Google refusing the account saves nothing', () async {
      final db = _FakeDb(_tutor('Incomplete'));
      final response = await connect(
        db,
        roomCreator: (_) async => throw const GoogleMeetDenied(),
      );
      expect(response.statusCode, 400);
      expect(await response.json(), {
        'error':
            "We couldn't create a Meet room with this account. "
            'Try another Google account.',
      });
      expect(db.meetLink, isNull);
    });

    test('Google being down is a 503 and saves nothing', () async {
      final db = _FakeDb(_tutor('Incomplete'));
      final response = await connect(
        db,
        roomCreator: (_) async => throw const GoogleMeetUnavailable(),
      );
      expect(response.statusCode, 503);
      expect(await response.json(), {
        'error': "We couldn't connect Google Meet. Please try again.",
      });
      expect(db.meetLink, isNull);
    });

    test('only POST is allowed', () async {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(
        Request('GET', Uri.parse('http://localhost/auth/tutor/meet-link')),
      );
      expect((await meet_link.onRequest(context)).statusCode, 405);
    });
  });

  group('POST /auth/tutor/availability', () {
    test('Step 3 is refused until Google Meet is connected', () async {
      final db = _FakeDb({
        'TutorID': '7',
        'UserId': '3',
        'AccountStatus': 'Incomplete',
        'Bio': 'I teach first-year maths.',
        'Certificate': 'https://example.test/cert.pdf',
        'SubjectCount': '1',
        'QualificationCount': '1',
        'MeetLink': null,
      });
      final response = await availability.handleTutorAvailability(
        _post('/auth/tutor/availability', {
          'availability': [
            {'day': 'Monday', 'startTime': '08:00', 'endTime': '12:00'},
          ],
        }, authorization: 'Bearer test'),
        tokenVerifier: _signedIn,
        connectionFactory: () async => db.connection,
      );
      expect(response.statusCode, 400);
      expect(await response.json(), {
        'error': 'Please connect Google Meet first.',
      });
      // Only the tutor lookup ran: nothing was saved or submitted.
      verify(() => db.connection.execute(any(), any())).called(1);
    });
  });
}
