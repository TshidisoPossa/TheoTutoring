import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_schedule.dart';

// Shape from GET /TutorLandingpage/schedule (lib/schedule_tutor.dart)
Map<String, dynamic> _session(int id, String student, String? note) => {
  'bookingId': id,
  'subject': 'Calculus',
  'student': {'name': student},
  'date': '2026-10-24',
  'startTime': '15:00',
  'endTime': '16:00',
  'durationMinutes': 60,
  'status': 'Confirmed',
  'confirmedMinutesAgo': 25,
  'link': 'https://meet.google.com/abc',
  'note': note,
};

final _page = {
  'tutor': {'name': 'Amahle Tshabalala'},
  'counts': {'upcoming': 2, 'new': 0, 'past': 0, 'all': 2},
  'subjects': [],
  'days': [
    {
      'date': '2026-10-24',
      'daysFromToday': 0,
      'sessions': [
        _session(1, 'Emma Roberts', 'Looking for help with derivatives.'),
        _session(2, 'Alex Rivera', null),
      ],
    },
  ],
};

Future<Map<String, dynamic>> _load({
  String tab = 'upcoming',
  String date = 'all',
  List<int> subjectIds = const [],
}) async => _page;

void main() {
  testWidgets('day heading is centred on the page', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: TutorScheduleScreen(loadSchedule: _load)),
    );
    await tester.pump();

    final heading = find.text('Today, 24 Oct');
    expect(heading, findsOneWidget);
    // The heading and its "2 sessions" pill sit around the middle (x = 200)
    final left = tester.getTopLeft(heading).dx;
    final pill = find
        .ancestor(of: find.text('2 sessions'), matching: find.byType(Container))
        .first;
    final right = tester.getTopRight(pill).dx;
    expect((left + right) / 2, closeTo(200, 2));
  });

  testWidgets("each card shows the student's note", (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: TutorScheduleScreen(loadSchedule: _load)),
    );
    await tester.pump();

    expect(find.text('"Looking for help with derivatives."'), findsOneWidget);
    // A booking without a note still says so
    expect(find.text('No note from the student.'), findsOneWidget);
  });

  group('Join session', () {
    Map<String, dynamic> session(int id, {String? link, String? status}) => {
      ..._session(id, 'Student $id', null),
      'link': link,
      'status': status ?? 'Confirmed',
    };

    test('canJoin needs a link and a Confirmed or Postponed lesson', () {
      ScheduleSession s(String? link, String status) =>
          ScheduleSession.fromJson(session(1, link: link, status: status));
      const meet = 'https://meet.google.com/abc';
      expect(s(meet, 'Confirmed').canJoin, isTrue);
      expect(s(meet, 'Postponed').canJoin, isTrue);
      expect(s(null, 'Confirmed').canJoin, isFalse);
      expect(s('', 'Confirmed').canJoin, isFalse);
      expect(s(meet, 'Cancelled').canJoin, isFalse);
      expect(s(meet, 'Pending').canJoin, isFalse);
      expect(s(meet, 'Completed').canJoin, isFalse);
    });

    testWidgets('replaces Session link, and is disabled with no link or on a '
        'cancelled lesson', (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final page = {
        ..._page,
        'days': [
          {
            'date': '2026-10-24',
            'daysFromToday': 0,
            'sessions': [
              session(1, link: 'https://meet.google.com/abc'),
              session(2),
              session(3, link: 'https://meet.google.com/abc',
                  status: 'Cancelled'),
            ],
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: TutorScheduleScreen(
            loadSchedule: ({
              String tab = 'upcoming',
              String date = 'all',
              List<int> subjectIds = const [],
            }) async => page,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Session link'), findsNothing);
      final buttons = find.ancestor(
        of: find.text('Join session'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(buttons, findsNWidgets(3));
      final enabled = [
        for (final element in buttons.evaluate())
          (element.widget as ButtonStyleButton).enabled,
      ];
      expect(enabled, [true, false, false]);
      // The card without a link still says so
      expect(find.text('Session link not added yet'), findsOneWidget);
    });
  });
}
