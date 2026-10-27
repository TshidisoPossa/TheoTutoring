import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_availability_calendar.dart';

// Monday 2 November 2026 is "today" in every test.
final _calendar = AvailabilityCalendarData.fromJson({
  'today': '2026-11-02',
  'lastDate': '2027-01-31',
  'dateChanges': [
    {
      'date': '2026-11-03',
      'dayOff': false,
      'times': [
        {'startTime': '14:00', 'endTime': '16:00'},
      ],
    },
    {'date': '2026-11-09', 'dayOff': true, 'times': <Object>[]},
  ],
  'bookings': [
    {'date': '2026-11-16', 'startTime': '09:00', 'endTime': '10:00'},
    {'date': '2026-11-17', 'startTime': '14:00', 'endTime': '15:30'},
  ],
});

// Mondays 08:00-12:00 only.
const _weekly = {
  'Monday': {'Morning'},
  'Tuesday': <String>{},
};

void main() {
  group('calendar data', () {
    test('reads date changes and the hours booked lessons take', () {
      expect(_calendar.today, DateTime(2026, 11, 2));
      expect(_calendar.changes, {
        '2026-11-03': [14, 15],
        '2026-11-09': <int>[],
      });
      // 14:00-15:30 takes up both the 14:00 and 15:00 hours
      expect(_calendar.booked, {
        '2026-11-16': [9],
        '2026-11-17': [14, 15],
      });
    });

    test('turns hours into the ranges the backend takes', () {
      expect(hoursToTimes([14, 9, 10, 15, 18]), [
        {'startTime': '09:00', 'endTime': '11:00'},
        {'startTime': '14:00', 'endTime': '16:00'},
        {'startTime': '18:00', 'endTime': '19:00'},
      ]);
      expect(describeHours([8, 9, 10, 11]), '08:00–12:00');
    });

    test('the weekly grid gives each weekday its hours', () {
      expect(usualHoursOn(DateTime(2026, 11, 2), _weekly), [8, 9, 10, 11]);
      expect(usualHoursOn(DateTime(2026, 11, 3), _weekly), isEmpty);
      expect(usualHoursOn(DateTime(2026, 11, 8), _weekly), isEmpty); // Sun
    });

    test('each date shows usual, changed, day off, closed or outside', () {
      CalendarDayKind kind(int month, int day) =>
          calendarDayKind(DateTime(2026, month, day), _calendar, _weekly);

      expect(kind(11, 2), CalendarDayKind.usual); // Monday
      expect(kind(11, 3), CalendarDayKind.changed);
      expect(kind(11, 9), CalendarDayKind.off);
      expect(kind(11, 4), CalendarDayKind.closed); // no weekly hours
      expect(kind(11, 1), CalendarDayKind.outside); // yesterday
      expect(
        calendarDayKind(DateTime(2027, 2, 1), _calendar, _weekly),
        CalendarDayKind.outside, // after the last bookable date
      );
    });
  });

  group('AvailabilityCalendar', () {
    Future<List<DateTime>> pumpCalendar(WidgetTester tester) async {
      final tapped = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AvailabilityCalendar(
                data: _calendar,
                weekly: _weekly,
                onDateTap: tapped.add,
              ),
            ),
          ),
        ),
      );
      return tapped;
    }

    testWidgets('shows the month and counts the open and changed days', (
      tester,
    ) async {
      await pumpCalendar(tester);
      expect(find.text('November 2026'), findsOneWidget);
      // Mondays 2, 16, 23, 30 plus the changed 3rd; the 9th is a day off
      expect(find.text('5 days open for booking · 2 changed'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Monday 16 November.*lesson')),
          findsOneWidget);
    });

    testWidgets('tapping a date opens it; past dates cannot be tapped', (
      tester,
    ) async {
      final tapped = await pumpCalendar(tester);
      await tester.tap(find.text('3'));
      await tester.tap(find.text('1')); // yesterday
      expect(tapped, [DateTime(2026, 11, 3)]);
    });

    testWidgets('moves between months only inside the booking window', (
      tester,
    ) async {
      await pumpCalendar(tester);
      final previous = find.widgetWithIcon(
        IconButton,
        Icons.chevron_left_rounded,
      );
      final next = find.widgetWithIcon(
        IconButton,
        Icons.chevron_right_rounded,
      );
      expect(tester.widget<IconButton>(previous).onPressed, isNull);

      await tester.tap(next);
      await tester.pump();
      expect(find.text('December 2026'), findsOneWidget);
      await tester.tap(next);
      await tester.pump();
      expect(find.text('January 2027'), findsOneWidget);
      expect(tester.widget<IconButton>(next).onPressed, isNull);
    });
  });

  group('DateHoursSheet', () {
    late List<String> saved; // "mode: hours"

    Future<void> pumpSheet(
      WidgetTester tester, {
      required DateTime date,
      List<int>? currentChange,
      List<int> bookedHours = const [],
      Object? failWith,
    }) async {
      saved = [];
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateHoursSheet(
              date: date,
              usualHours: usualHoursOn(date, _weekly),
              currentChange: currentChange,
              bookedHours: bookedHours,
              onSave: (mode, hours) async {
                if (failWith != null) throw failWith;
                saved.add('${mode.name}: ${hours.join(",")}');
              },
            ),
          ),
        ),
      );
    }

    ElevatedButton saveButton(WidgetTester tester) =>
        tester.widget(find.widgetWithText(ElevatedButton, 'Save'));

    testWidgets('offers only Day off and Custom hours, nothing picked yet', (
      tester,
    ) async {
      await pumpSheet(tester, date: DateTime(2026, 11, 23));
      expect(find.text('Day off'), findsOneWidget);
      expect(find.text('Custom hours'), findsOneWidget);
      expect(find.text('Usual'), findsNothing);
      expect(
        find.text(
          'Students can book 08:00–12:00. '
          'Choose Day off or Custom hours to change it.',
        ),
        findsOneWidget,
      );
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('takes a usual day off', (tester) async {
      await pumpSheet(tester, date: DateTime(2026, 11, 23));
      expect(find.text('Monday, 23 November'), findsOneWidget);
      expect(find.text('Usual Monday hours: 08:00–12:00'), findsOneWidget);

      await tester.tap(find.text('Day off'));
      await tester.pump();
      expect(
        find.text('Students will not see any times on this day.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved, ['off: ']);
    });

    testWidgets('custom hours start from the usual ones and can change', (
      tester,
    ) async {
      await pumpSheet(tester, date: DateTime(2026, 11, 23));
      await tester.tap(find.text('Custom hours'));
      await tester.pump();

      await tester.tap(find.text('10:00')); // off
      await tester.tap(find.text('11:00')); // off
      await tester.tap(find.text('18:00')); // on
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved, ['custom: 8,9,18']);
    });

    testWidgets('custom hours equal to the usual ones are saved as usual', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        date: DateTime(2026, 11, 23),
        currentChange: [8, 9],
      );
      // Opens on Custom because the date already has its own hours
      await tester.tap(find.text('10:00'));
      await tester.tap(find.text('11:00'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved, ['usual: ']);
    });

    testWidgets('opens extra hours on a day with no usual hours', (
      tester,
    ) async {
      await pumpSheet(tester, date: DateTime(2026, 11, 8)); // Sunday
      expect(find.text('You have no usual hours on Sundays.'), findsOneWidget);
      await tester.tap(find.text('Custom hours'));
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull); // nothing picked yet
      expect(
        find.text('Pick at least one hour, or choose Day off.'),
        findsOneWidget,
      );

      await tester.tap(find.text('10:00'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved, ['custom: 10']);
    });

    testWidgets('a booked lesson keeps its hour and blocks a day off', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        date: DateTime(2026, 11, 16),
        bookedHours: [9],
      );
      expect(
        find.text('Lesson booked at 09:00. That time stays open.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Day off')); // disabled
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull); // still nothing picked

      await tester.tap(find.text('Custom hours'));
      await tester.pump();
      for (final hour in ['08:00', '09:00', '10:00', '11:00']) {
        await tester.tap(find.text(hour));
      }
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved, ['custom: 9']);
    });

    testWidgets('shows the server message when saving fails', (tester) async {
      await pumpSheet(
        tester,
        date: DateTime(2026, 11, 23),
        failWith: Exception('You have a lesson booked'),
      );
      await tester.tap(find.text('Day off'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.textContaining('You have a lesson booked'), findsOneWidget);
      expect(find.text('Monday, 23 November'), findsOneWidget); // still open
    });
  });
}
