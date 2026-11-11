import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/google_meet.dart';
import 'package:theo_tutoring_backend/tutor_account_status.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/Profile/meet-link.dart' as meet_link;
import '../../../routes/TutorLandingpage/_middleware.dart' as tutor_middleware;

// POST /TutorLandingpage/Profile/meet-link (Google Meet card on Profile)
// with a fake database and Google. The Firebase check is the TutorLandingpage
// middleware's job, so it is tested on its own at the end.

class _MockRequestContext extends Mock implements RequestContext {}

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

const _room = 'https://meet.google.com/abc-mnop-xyz';
const _path = '/TutorLandingpage/Profile/meet-link';

/// Keeps whatever the route saves in TutorProfile.MeetLink for tutor 5.
class _FakeDb {
  _FakeDb([this.meetLink]) {
    final result = _MockResult();
    when(() => result.rows).thenReturn(const []);
    when(() => connection.execute(any(), any())).thenAnswer((call) async {
      final sql = call.positionalArguments[0] as String;
      final params = call.positionalArguments[1] as Map<String, dynamic>;
      expect(sql, contains('UPDATE tutorprofile SET MeetLink'));
      expect(params['tutorId'], 5);
      meetLink = params['link'] as String;
      return result;
    });
  }

  final connection = _MockConnection();
  String? meetLink;
}

RequestContext _request(String method, {Object? body}) {
  final context = _MockRequestContext();
  when(() => context.read<TutorSession>()).thenReturn(
    const TutorSession('uid-5', 5, accountStatus: 'Pending'),
  );
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost$_path'),
      body: body == null ? null : jsonEncode(body),
    ),
  );
  return context;
}

void main() {
  Future<Response> connect(
    _FakeDb db, {
    Object? body = const {'accessToken': 'google-token'},
    Future<String> Function(String)? roomCreator,
  }) {
    return meet_link.handleProfileMeetLink(
      _request('POST', body: body),
      connectionFactory: () async => db.connection,
      roomCreator: roomCreator ?? (_) async => _room,
    );
  }

  test('only POST is allowed', () async {
    expect((await meet_link.onRequest(_request('GET'))).statusCode, 405);
  });

  test('a missing Google token is a 400 and nothing is saved', () async {
    final db = _FakeDb();
    final response = await connect(db, body: const <String, dynamic>{});
    expect(response.statusCode, 400);
    expect(await response.json(), {
      'error': "Google Meet wasn't connected. Please try again.",
    });
    expect(db.meetLink, isNull);
  });

  test('Connect saves the new room as the tutor link', () async {
    final db = _FakeDb();
    final response = await connect(
      db,
      roomCreator: (token) async {
        expect(token, 'google-token');
        return _room;
      },
    );
    expect(response.statusCode, 200);
    expect(await response.json(), {'meetConnected': true});
    expect(db.meetLink, _room);
  });

  test('Reconnect replaces the existing link', () async {
    final db = _FakeDb('https://meet.google.com/old-room-one');
    final response = await connect(
      db,
      roomCreator: (_) async => 'https://meet.google.com/new-room-two',
    );
    expect(response.statusCode, 200);
    expect(db.meetLink, 'https://meet.google.com/new-room-two');
  });

  test('Google refusing the account keeps the old link', () async {
    final db = _FakeDb('https://meet.google.com/old-room-one');
    final response = await connect(
      db,
      roomCreator: (_) async => throw const GoogleMeetDenied(),
    );
    expect(response.statusCode, 400);
    expect(db.meetLink, 'https://meet.google.com/old-room-one');
  });

  test('Google being down is a 503 and keeps the old link', () async {
    final db = _FakeDb('https://meet.google.com/old-room-one');
    final response = await connect(
      db,
      roomCreator: (_) async => throw const GoogleMeetUnavailable(),
    );
    expect(response.statusCode, 503);
    expect(db.meetLink, 'https://meet.google.com/old-room-one');
  });

  group('Firebase token and account status (middleware)', () {
    test('a missing Firebase token is a 401', () async {
      var reached = false;
      final handler = tutor_middleware.middleware((_) {
        reached = true;
        return Response();
      });
      final response = await handler(_request('POST'));
      expect(response.statusCode, 401);
      expect(reached, isFalse);
    });

    test('Pending and Active tutors may connect, others may not', () {
      final uri = Uri.parse('http://localhost$_path');
      expect(canAccessTutorRoute('Pending', uri), isTrue);
      expect(canAccessTutorRoute('Active', uri), isTrue);
      expect(canAccessTutorRoute('Rejected', uri), isFalse);
      expect(canAccessTutorRoute('Incomplete', uri), isFalse);
    });
  });
}
