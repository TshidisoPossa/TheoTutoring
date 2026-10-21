import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/cloudinary_url.dart';
import 'package:theo_tutoring_backend/profile_tutor.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/Profile/availability.dart'
    as availability_route;
import '../../../routes/TutorLandingpage/Profile/index.dart' as profile_route;
import '../../../routes/TutorLandingpage/Profile/photo.dart' as photo_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('availabilityRanges', () {
    test('merges touching periods into one row per range', () {
      final rows = availabilityRanges({
        'Monday': ['Afternoon', 'Morning'],
        'Wednesday': ['Morning', 'Evening'],
      });
      expect(rows, [
        (day: 'Monday', start: 480, end: 1020), // 08:00-17:00
        (day: 'Wednesday', start: 480, end: 720), // 08:00-12:00
        (day: 'Wednesday', start: 1020, end: 1200), // 17:00-20:00
      ]);
    });

    test('rejects Sunday, unknown periods and an empty grid', () {
      expect(
        () => availabilityRanges({
          'Sunday': ['Morning'],
        }),
        throwsArgumentError,
      );
      expect(
        () => availabilityRanges({
          'Monday': ['Night'],
        }),
        throwsArgumentError,
      );
      expect(() => availabilityRanges({'Monday': []}), throwsArgumentError);
    });
  });

  group('findRemovedBooking', () {
    const booking = (date: '2026-10-27', day: 'Tuesday', start: 840, end: 900);
    const tuesdayAfternoon = (day: 'Tuesday', start: 720, end: 1020);

    test('blocks removing a period that holds an upcoming booking', () {
      expect(
        findRemovedBooking(
          before: [tuesdayAfternoon],
          after: [(day: 'Tuesday', start: 480, end: 720)],
          bookings: [booking],
        ),
        booking,
      );
    });

    test('allows the change while the booking stays covered', () {
      expect(
        findRemovedBooking(
          before: [tuesdayAfternoon],
          after: [(day: 'Tuesday', start: 480, end: 1020)],
          bookings: [booking],
        ),
        isNull,
      );
    });

    test('ignores bookings that were never inside the availability', () {
      expect(
        findRemovedBooking(before: [], after: [], bookings: [booking]),
        isNull,
      );
    });
  });

  test('lockedPeriods returns ticked periods that overlap a booking', () {
    const bookings = [
      (date: '2026-10-27', day: 'Tuesday', start: 690, end: 750), // 11:30-12:30
    ];
    expect(
      lockedPeriods('Tuesday', ['Morning', 'Afternoon', 'Evening'], bookings),
      ['Morning', 'Afternoon'],
    );
    expect(lockedPeriods('Tuesday', ['Evening'], bookings), isEmpty);
    expect(lockedPeriods('Monday', ['Morning'], bookings), isEmpty);
  });

  group('checkCloudinaryUrl', () {
    String? check(String url) =>
        checkCloudinaryUrl(url, 'Profile photo', cloudinaryImageTypes, 'demo');

    test('accepts a JPG or PNG from the project account', () {
      expect(
        check('https://res.cloudinary.com/demo/image/upload/v1/me.jpg'),
        isNull,
      );
      expect(
        check('https://res.cloudinary.com/demo/image/upload/v1/me.PNG'),
        isNull,
      );
    });

    test('rejects other accounts, plain http and other file types', () {
      expect(
        check('https://res.cloudinary.com/other/image/upload/v1/me.jpg'),
        isNotNull,
      );
      expect(
        check('http://res.cloudinary.com/demo/image/upload/v1/me.jpg'),
        isNotNull,
      );
      expect(
        check('https://res.cloudinary.com/demo/image/upload/v1/me.pdf'),
        isNotNull,
      );
    });
  });

  group('routes', () {
    late _MockRequestContext context;

    void request(String method, String path, {Object? body}) {
      when(() => context.request).thenReturn(
        Request(
          method,
          Uri.parse('http://localhost$path'),
          body: body == null ? null : jsonEncode(body),
        ),
      );
    }

    setUp(() {
      context = _MockRequestContext();
      when(() => context.read<TutorSession>()).thenReturn(
        const TutorSession('uid-1', 5),
      );
    });

    test('GET /Profile: only GET is allowed', () async {
      request('POST', '/TutorLandingpage/Profile');
      expect((await profile_route.onRequest(context)).statusCode, 405);
    });

    test('PUT /Profile/photo: only PUT is allowed', () async {
      request('GET', '/TutorLandingpage/Profile/photo');
      expect((await photo_route.onRequest(context)).statusCode, 405);
    });

    test('PUT /Profile/photo: a missing photo is a 400', () async {
      request('PUT', '/TutorLandingpage/Profile/photo', body: {});
      final response = await photo_route.onRequest(context);
      expect(response.statusCode, 400);
      expect(await response.json(), {'error': 'Please choose a photo.'});
    });

    test('PUT /Profile/availability: only PUT is allowed', () async {
      request('POST', '/TutorLandingpage/Profile/availability');
      expect((await availability_route.onRequest(context)).statusCode, 405);
    });

    test('PUT /Profile/availability: a bad body is a 400', () async {
      request(
        'PUT',
        '/TutorLandingpage/Profile/availability',
        body: {
          'availability': {'Monday': 'Morning'},
        },
      );
      expect((await availability_route.onRequest(context)).statusCode, 400);
    });
  });
}
