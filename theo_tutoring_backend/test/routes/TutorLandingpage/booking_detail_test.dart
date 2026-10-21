import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/bookings/[id]/index.dart'
    as detail_route;
import '../../../routes/TutorLandingpage/bookings/[id]/postpone.dart'
    as postpone_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('parsePostponeSlot', () {
    test('reads the date and 24-hour times', () {
      final slot = parsePostponeSlot({
        'date': '2026-10-31',
        'startTime': '16:00',
        'endTime': '17:30',
      });
      expect(slot.date, '2026-10-31');
      expect(slot.start, 960);
      expect(slot.end, 1050);
      expect(slot.startTime, '16:00:00');
      expect(slot.endTime, '17:30:00');
    });

    test('rejects missing, badly formatted and impossible values', () {
      Map<String, dynamic> body(String date, String start, String end) => {
        'date': date,
        'startTime': start,
        'endTime': end,
      };
      for (final bad in [
        <String, dynamic>{},
        body('31/10/2026', '16:00', '17:00'), // wrong date format
        body('2026-02-30', '16:00', '17:00'), // no 30 February
        body('2026-10-31', '4pm', '17:00'), // not 24-hour
        body('2026-10-31', '24:00', '25:00'), // no hour 24
        body('2026-10-31', '17:00', '16:00'), // ends before it starts
        body('2026-10-31', '16:00', '16:00'), // no length
        {'date': 20261031, 'startTime': '16:00', 'endTime': '17:00'},
      ]) {
        expect(() => parsePostponeSlot(bad), throwsFormatException);
      }
    });
  });

  group('availabilityCovers', () {
    const morning = (start: 8 * 60, end: 12 * 60);
    const afternoon = (start: 12 * 60, end: 17 * 60);
    const evening = (start: 18 * 60, end: 20 * 60);

    test('a slot inside one range is covered', () {
      expect(availabilityCovers([morning], 9 * 60, 10 * 60), isTrue);
      expect(availabilityCovers([morning], 8 * 60, 12 * 60), isTrue);
    });

    test('touching ranges join, so a slot can span them', () {
      expect(
        availabilityCovers([afternoon, morning], 11 * 60, 13 * 60),
        isTrue,
      );
    });

    test('a gap between ranges or no ranges at all is not covered', () {
      expect(
        availabilityCovers([afternoon, evening], 16 * 60, 19 * 60),
        isFalse,
      );
      expect(availabilityCovers([morning], 7 * 60, 9 * 60), isFalse);
      expect(availabilityCovers([], 9 * 60, 10 * 60), isFalse);
    });
  });

  group('weeklyRun', () {
    Map<String, dynamic> s(int id, String date) => {
      'bookingId': id,
      'date': date,
    };

    test('keeps consecutive weeks and stops at the first gap', () {
      final run = weeklyRun([
        s(1, '2026-10-27'),
        s(2, '2026-11-03'),
        s(3, '2026-11-10'),
        s(4, '2026-11-24'), // 17 Nov skipped
      ]);
      expect(run.map((x) => x['bookingId']), [1, 2, 3]);
    });

    test('crosses month and year ends', () {
      final run = weeklyRun([s(1, '2026-12-29'), s(2, '2027-01-05')]);
      expect(run.length, 2);
    });

    test('one session, or no second week, is not recurring', () {
      expect(weeklyRun([s(1, '2026-10-27')]), isEmpty);
      expect(weeklyRun([s(1, '2026-10-27'), s(2, '2026-11-10')]), isEmpty);
    });
  });

  test('sessionLabel and hhmm format times for messages', () {
    expect(sessionLabel('2026-10-24', '16:00'), 'Sat 24 Oct, 16:00');
    expect(hhmm(960), '16:00');
    expect(hhmm(65), '01:05');
  });

  group('booking routes reject bad requests before the database', () {
    late _MockRequestContext context;

    void request(String method, {String? body}) {
      when(() => context.request).thenReturn(
        Request(
          method,
          Uri.parse('http://localhost/TutorLandingpage/bookings/5'),
          body: body,
        ),
      );
    }

    setUp(() {
      context = _MockRequestContext();
      when(() => context.read<TutorSession>()).thenReturn(
        const TutorSession('uid-1', 5),
      );
    });

    test('GET details: only GET, and the id must be a number', () async {
      request('POST');
      var response = await detail_route.onRequest(context, '5');
      expect(response.statusCode, 405);

      request('GET');
      response = await detail_route.onRequest(context, 'abc');
      expect(response.statusCode, 400);
      response = await detail_route.onRequest(context, '0');
      expect(response.statusCode, 400);
    });

    test('POST postpone: only POST, a numeric id and a valid body', () async {
      request('GET');
      var response = await postpone_route.onRequest(context, '5');
      expect(response.statusCode, 405);

      request('POST', body: '{}');
      response = await postpone_route.onRequest(context, 'abc');
      expect(response.statusCode, 400);

      request('POST', body: 'not json');
      response = await postpone_route.onRequest(context, '5');
      expect(response.statusCode, 400);

      request(
        'POST',
        body: '{"date":"2026-10-31","startTime":"17:00","endTime":"16:00"}',
      );
      response = await postpone_route.onRequest(context, '5');
      expect(response.statusCode, 400);
      expect(
        (await response.json() as Map)['error'],
        'endTime must be after startTime.',
      );
    });
  });
}
