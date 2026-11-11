import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/cloudinary_url.dart';
import 'package:theo_tutoring_backend/database.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/Profile/availability.dart'
    as availability_route;
import '../../../routes/TutorLandingpage/Profile/index.dart' as profile_route;
import '../../../routes/TutorLandingpage/Profile/meet-link.dart'
    as meet_link_route;
import '../../../routes/TutorLandingpage/Profile/photo.dart' as photo_route;

// Runs the Profile routes against the real database from .env, as one tutor.
// Opt in, so a normal `dart test` never touches the database:
//   PROFILE_MYSQL_TEST_TUTOR_ID=1 dart test test/routes/TutorLandingpage/profile_mysql_test.dart
// Everything the tests change for that tutor is put back afterwards.
// The Firebase login check (middleware) is skipped: the tutor is given directly.

class _MockRequestContext extends Mock implements RequestContext {}

final _tutorId = int.tryParse(
  Platform.environment['PROFILE_MYSQL_TEST_TUTOR_ID'] ?? '',
);

void main() {
  if (_tutorId == null) {
    test(
      'Profile routes against MySQL',
      () {},
      skip: 'Set PROFILE_MYSQL_TEST_TUTOR_ID to run against the database',
    );
    return;
  }

  late MySQLConnection conn;
  late _Snapshot original;
  final addedBookings = <int>[];

  Future<Response> call(
    Future<Response> Function(RequestContext) route,
    String method,
    String path, {
    Object? body,
  }) {
    final context = _MockRequestContext();
    when(() => context.read<TutorSession>()).thenReturn(
      TutorSession('profile-mysql-test', _tutorId!),
    );
    when(() => context.request).thenReturn(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return route(context);
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await call(
      profile_route.onRequest,
      'GET',
      '/TutorLandingpage/Profile',
    );
    expect(response.statusCode, 200);
    return await response.json() as Map<String, dynamic>;
  }

  Future<Response> putAvailability(Map<String, List<String>> grid) => call(
    availability_route.onRequest,
    'PUT',
    '/TutorLandingpage/Profile/availability',
    body: {'availability': grid},
  );

  Map<String, dynamic> dayOf(Map<String, dynamic> profile, String day) =>
      (profile['availability'] as List).cast<Map<String, dynamic>>().firstWhere(
        (d) => d['day'] == day,
      );

  List<String> periodsOf(Map<String, dynamic> day) => [
    for (final s in (day['slots'] as List).cast<Map<String, dynamic>>())
      s['period'] as String,
  ];

  setUpAll(() async {
    conn = await getConnection();
    original = await _Snapshot.take(conn, _tutorId!);
  });

  tearDownAll(() async {
    for (final id in addedBookings) {
      await conn.execute(
        'DELETE FROM booking WHERE Booking_id = :id',
        {'id': id},
      );
    }
    await original.restore(conn);
    await conn.close();
  });

  group('GET /TutorLandingpage/Profile', () {
    test('returns the tutor name and every box of the page', () async {
      final profile = await getProfile();
      expect(profile['tutorId'], _tutorId);
      expect(profile['name'], original.name);
      expect(profile['profilePhotoUrl'], original.photo);
      expect(profile['about'], original.bio);
      expect(profile, contains('sessionRate'));
      expect(profile['subjects'], isA<List<dynamic>>());
      expect(profile['qualifications'], isA<List<dynamic>>());
      final days = (profile['availability'] as List)
          .map((d) => (d as Map)['day'])
          .toList();
      expect(days, [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ]);
    });

    test('shows subjects and qualifications saved in MySQL', () async {
      final subject = await conn.execute(
        'SELECT subjectId, subjectName FROM subjects ORDER BY subjectId LIMIT 1',
      );
      final subjectId = int.parse(subject.rows.first.reqStr('subjectId'));
      await conn.execute(
        'DELETE FROM tutorsubjects WHERE TutorID = :t',
        {'t': _tutorId},
      );
      await conn.execute(
        'INSERT INTO tutorsubjects (TutorID, SubjectID) VALUES (:t, :s)',
        {'t': _tutorId, 's': subjectId},
      );
      await conn.execute(
        'DELETE FROM qualification WHERE TutorID = :t',
        {'t': _tutorId},
      );
      await conn.execute(
        'INSERT INTO qualification (TutorID, Degree, Institution) '
        "VALUES (:t, 'BSc Test Degree', 'Test University')",
        {'t': _tutorId},
      );

      final profile = await getProfile();
      expect(profile['subjects'], [
        {
          'subjectId': subjectId,
          'subjectName': subject.rows.first.str('subjectName'),
        },
      ]);
      final qualification =
          (profile['qualifications'] as List).single as Map<String, dynamic>;
      expect(qualification['degree'], 'BSc Test Degree');
      expect(qualification['institution'], 'Test University');
    });
  });

  group('Google Meet card', () {
    Future<void> setMeetLink(String? link) => conn.execute(
      'UPDATE tutorprofile SET MeetLink = :link WHERE TutorID = :t',
      {'link': link, 't': _tutorId},
    );

    Future<String?> savedMeetLink() async => (await conn.execute(
      'SELECT MeetLink FROM tutorprofile WHERE TutorID = :t',
      {'t': _tutorId},
    )).rows.single.str('MeetLink');

    Future<Response> connect(String room) {
      final context = _MockRequestContext();
      when(() => context.read<TutorSession>()).thenReturn(
        TutorSession('profile-mysql-test', _tutorId!),
      );
      when(() => context.request).thenReturn(
        Request(
          'POST',
          Uri.parse('http://localhost/TutorLandingpage/Profile/meet-link'),
          body: jsonEncode({'accessToken': 'fake-google-token'}),
        ),
      );
      return meet_link_route.handleProfileMeetLink(
        context,
        roomCreator: (_) async => room, // no real Google room
      );
    }

    test('meetConnected is false without a link', () async {
      await setMeetLink(null);
      expect((await getProfile())['meetConnected'], isFalse);
    });

    test('meetConnected is true with a link', () async {
      await setMeetLink('https://meet.google.com/abc-mnop-xyz');
      expect((await getProfile())['meetConnected'], isTrue);
    });

    test('Connect saves the link and Reconnect replaces it', () async {
      await setMeetLink(null);
      final first = await connect('https://meet.google.com/abc-mnop-xyz');
      expect(first.statusCode, 200);
      expect(await first.json(), {'meetConnected': true});
      expect(await savedMeetLink(), 'https://meet.google.com/abc-mnop-xyz');
      expect((await getProfile())['meetConnected'], isTrue);

      final again = await connect('https://meet.google.com/new-room-two');
      expect(again.statusCode, 200);
      expect(await savedMeetLink(), 'https://meet.google.com/new-room-two');
    });
  });

  group('PUT /TutorLandingpage/Profile/photo', () {
    test('saves the new photo and the profile shows it', () async {
      final url =
          'https://res.cloudinary.com/${cloudinaryCloudName()}'
          '/image/upload/v1/profile-test.jpg';
      final response = await call(
        photo_route.onRequest,
        'PUT',
        '/TutorLandingpage/Profile/photo',
        body: {'profilePhotoUrl': url},
      );
      expect(response.statusCode, 200);
      final body = await response.json() as Map<String, dynamic>;
      expect((body['tutor'] as Map)['profilePhotoUrl'], url);

      expect((await getProfile())['profilePhotoUrl'], url);
    });

    test('refuses a photo from another Cloudinary account', () async {
      final before = (await getProfile())['profilePhotoUrl'];
      final response = await call(
        photo_route.onRequest,
        'PUT',
        '/TutorLandingpage/Profile/photo',
        body: {
          'profilePhotoUrl':
              'https://res.cloudinary.com/someone-else/image/upload/v1/x.jpg',
        },
      );
      expect(response.statusCode, 400);
      expect((await getProfile())['profilePhotoUrl'], before); // unchanged
    });

    test('refuses a PDF as a profile photo', () async {
      final response = await call(
        photo_route.onRequest,
        'PUT',
        '/TutorLandingpage/Profile/photo',
        body: {
          'profilePhotoUrl':
              'https://res.cloudinary.com/${cloudinaryCloudName()}'
              '/image/upload/v1/x.pdf',
        },
      );
      expect(response.statusCode, 400);
    });
  });

  group('PUT /TutorLandingpage/Profile/availability', () {
    test('saves the ticked grid and the profile shows it', () async {
      final response = await putAvailability({
        'Monday': ['Morning', 'Afternoon'],
        'Tuesday': ['Afternoon'],
        'Saturday': ['Evening'],
      });
      expect(response.statusCode, 200);

      final profile = await getProfile();
      expect(periodsOf(dayOf(profile, 'Monday')), ['Morning', 'Afternoon']);
      expect(periodsOf(dayOf(profile, 'Tuesday')), ['Afternoon']);
      expect(periodsOf(dayOf(profile, 'Saturday')), ['Evening']);
      expect(dayOf(profile, 'Wednesday')['available'], isFalse);

      // Monday Morning + Afternoon is saved as one 08:00-17:00 row.
      final rows = await conn.execute(
        'SELECT Day, StartTime, end_Time FROM tutavailability '
        'WHERE TutorID = :t ORDER BY Day, StartTime',
        {'t': _tutorId},
      );
      expect(rows.rows.map((r) => r.textAssoc()).toList(), [
        {'Day': 'Monday', 'StartTime': '08:00:00', 'end_Time': '17:00:00'},
        {'Day': 'Tuesday', 'StartTime': '12:00:00', 'end_Time': '17:00:00'},
        {'Day': 'Saturday', 'StartTime': '17:00:00', 'end_Time': '20:00:00'},
      ]);
    });

    test('rejects Sunday and leaves the saved grid alone', () async {
      final response = await putAvailability({
        'Sunday': ['Morning'],
      });
      expect(response.statusCode, 400);
      expect(periodsOf(dayOf(await getProfile(), 'Tuesday')), ['Afternoon']);
    });

    test('rejects an empty grid', () async {
      expect((await putAvailability({})).statusCode, 400);
    });

    test('a booked period is locked and cannot be removed', () async {
      // A Confirmed booking next Tuesday 14:00-15:00 (inside Tuesday Afternoon)
      final student = await conn.execute(
        'SELECT StudentID FROM studentprofile ORDER BY StudentID LIMIT 1',
      );
      final subject = await conn.execute(
        'SELECT subjectId FROM subjects ORDER BY subjectId LIMIT 1',
      );
      final date = _nextWeekday(DateTime.tuesday);
      final insert = await conn.execute(
        'INSERT INTO booking (StudentID, TutorID, SubjectID, `Date`, '
        'StartTime, EndTime, Note, Status, Created_at) '
        "VALUES (:s, :t, :subj, :d, '14:00:00', '15:00:00', "
        "'profile-mysql-test', 'Confirmed', NOW())",
        {
          's': student.rows.first.str('StudentID'),
          't': _tutorId,
          'subj': subject.rows.first.str('subjectId'),
          'd': date,
        },
      );
      addedBookings.add(insert.lastInsertID.toInt());

      // The page marks Tuesday Afternoon as locked.
      expect(dayOf(await getProfile(), 'Tuesday')['locked'], ['Afternoon']);

      // Unticking it is refused, and nothing is changed.
      final response = await putAvailability({
        'Monday': ['Morning'],
      });
      expect(response.statusCode, 409);
      expect(
        ((await response.json()) as Map)['error'],
        contains('upcoming booking'),
      );
      expect(periodsOf(dayOf(await getProfile(), 'Monday')), [
        'Morning',
        'Afternoon',
      ]);

      // Changing other days while keeping Tuesday Afternoon is allowed.
      final allowed = await putAvailability({
        'Tuesday': ['Afternoon', 'Evening'],
        'Friday': ['Morning'],
      });
      expect(allowed.statusCode, 200);
      final profile = await getProfile();
      expect(periodsOf(dayOf(profile, 'Tuesday')), ['Afternoon', 'Evening']);
      expect(dayOf(profile, 'Tuesday')['locked'], ['Afternoon']);
      expect(dayOf(profile, 'Monday')['available'], isFalse);
    });
  });
}

// "2026-10-27": the given weekday, at least 2 days from today.
String _nextWeekday(int weekday) {
  var d = DateTime.now().add(const Duration(days: 2));
  while (d.weekday != weekday) {
    d = d.add(const Duration(days: 1));
  }
  return d.toIso8601String().substring(0, 10);
}

// What the tutor had before the tests, so it can be put back exactly.
class _Snapshot {
  _Snapshot(
    this.tutorId,
    this.name,
    this.photo,
    this.bio,
    this.meetLink,
    this.availability,
    this.subjects,
    this.qualifications,
  );

  final int tutorId;
  final String? name;
  final String? photo;
  final String? bio;
  final String? meetLink;
  final List<Map<String, String?>> availability;
  final List<String?> subjects;
  final List<Map<String, String?>> qualifications;

  static Future<_Snapshot> take(MySQLConnection conn, int tutorId) async {
    final p = {'t': tutorId};
    final tutor = await conn.execute(
      'SELECT u.Name, u.ProfilePhoto, tp.Bio, tp.MeetLink FROM tutorprofile tp '
      'JOIN `user` u ON u.UserId = tp.UserID WHERE tp.TutorID = :t',
      p,
    );
    if (tutor.rows.isEmpty) throw StateError('No tutor with TutorID $tutorId');
    final t = tutor.rows.first.textAssoc();
    final availability = await conn.execute(
      'SELECT Day, StartTime, end_Time FROM tutavailability WHERE TutorID = :t',
      p,
    );
    final subjects = await conn.execute(
      'SELECT SubjectID FROM tutorsubjects WHERE TutorID = :t',
      p,
    );
    final qualifications = await conn.execute(
      'SELECT Degree, Institution FROM qualification WHERE TutorID = :t',
      p,
    );
    return _Snapshot(
      tutorId,
      t['Name'],
      t['ProfilePhoto'],
      t['Bio'],
      t['MeetLink'],
      availability.rows.map((r) => r.textAssoc()).toList(),
      subjects.rows.map((r) => r.str('SubjectID')).toList(),
      qualifications.rows.map((r) => r.textAssoc()).toList(),
    );
  }

  Future<void> restore(MySQLConnection conn) async {
    final p = {'t': tutorId};
    await conn.execute(
      'UPDATE `user` u JOIN tutorprofile tp ON tp.UserID = u.UserId '
      'SET u.ProfilePhoto = :photo WHERE tp.TutorID = :t',
      {'photo': photo, 't': tutorId},
    );
    await conn.execute(
      'UPDATE tutorprofile SET MeetLink = :link WHERE TutorID = :t',
      {'link': meetLink, 't': tutorId},
    );
    await conn.execute('DELETE FROM tutavailability WHERE TutorID = :t', p);
    for (final a in availability) {
      await conn.execute(
        'INSERT INTO tutavailability (TutorID, Day, StartTime, end_Time) '
        'VALUES (:t, :d, :s, :e)',
        {'t': tutorId, 'd': a['Day'], 's': a['StartTime'], 'e': a['end_Time']},
      );
    }
    await conn.execute('DELETE FROM tutorsubjects WHERE TutorID = :t', p);
    for (final s in subjects) {
      await conn.execute(
        'INSERT INTO tutorsubjects (TutorID, SubjectID) VALUES (:t, :s)',
        {'t': tutorId, 's': s},
      );
    }
    await conn.execute('DELETE FROM qualification WHERE TutorID = :t', p);
    for (final q in qualifications) {
      await conn.execute(
        'INSERT INTO qualification (TutorID, Degree, Institution) '
        'VALUES (:t, :d, :i)',
        {'t': tutorId, 'd': q['Degree'], 'i': q['Institution']},
      );
    }
  }
}
