import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/schedule_tutor.dart';
// Same import as the routes, so it is the same TutorSession type.
import '../../../lib/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/schedule/index.dart' as schedule_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('parseScheduleQuery', () {
    test('defaults to Upcoming, All Dates and every subject', () {
      final q = parseScheduleQuery({});
      expect(q.tab, ScheduleTab.upcoming);
      expect(q.date, ScheduleDate.all);
      expect(q.subjectIds, isEmpty);
    });

    test('reads the New tab, a date chip and subject filters', () {
      final q = parseScheduleQuery({
        'tab': 'new',
        'date': 'week',
        'subjectId': '3, 5,3',
      });
      expect(q.tab, ScheduleTab.newRequests);
      expect(q.date, ScheduleDate.week);
      expect(q.subjectIds, [3, 5]); // duplicate removed
    });

    test('rejects unknown tabs, dates and bad subject ids', () {
      expect(
        () => parseScheduleQuery({'tab': 'pending'}),
        throwsFormatException,
      );
      expect(
        () => parseScheduleQuery({'date': 'yesterday'}),
        throwsFormatException,
      );
      expect(
        () => parseScheduleQuery({'subjectId': '3,abc'}),
        throwsFormatException,
      );
      expect(
        () => parseScheduleQuery({'subjectId': '-1'}),
        throwsFormatException,
      );
    });
  });

  test('groupSessionsByDay keeps the order and counts each day', () {
    final days = groupSessionsByDay([
      {'bookingId': 1, 'date': '2026-09-30', 'daysFromToday': 0},
      {'bookingId': 2, 'date': '2026-09-30', 'daysFromToday': 0},
      {'bookingId': 3, 'date': '2026-10-01', 'daysFromToday': 1},
    ]);
    expect(days.length, 2);
    expect(days[0]['date'], '2026-09-30');
    expect(days[0]['count'], 2);
    expect(days[1]['daysFromToday'], 1);
    expect(
      (days[1]['sessions'] as List).map((s) => (s as Map)['bookingId']),
      [3],
    );
  });

  group('GET /TutorLandingpage/schedule', () {
    late _MockRequestContext context;

    void request(String method, String path) {
      when(() => context.request).thenReturn(
        Request(method, Uri.parse('http://localhost$path')),
      );
    }

    setUp(() {
      context = _MockRequestContext();
      when(() => context.read<TutorSession>()).thenReturn(
        const TutorSession('uid-1', 5),
      );
    });

    test('only GET is allowed', () async {
      request('POST', '/TutorLandingpage/schedule');
      expect((await schedule_route.onRequest(context)).statusCode, 405);
    });

    test('an unknown tab is a 400', () async {
      request('GET', '/TutorLandingpage/schedule?tab=bogus');
      final response = await schedule_route.onRequest(context);
      expect(response.statusCode, 400);
      expect(
        await response.json(),
        {'error': 'tab must be upcoming, new, past or all.'},
      );
    });
  });
}
