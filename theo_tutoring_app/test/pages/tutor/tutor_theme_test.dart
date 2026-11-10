import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theo_tutoring_app/Pages/Student/student_profile.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_availability_calendar.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_notifications.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_theme.dart';

final _calendar = AvailabilityCalendarData.fromJson({
  'today': '2026-11-02',
  'lastDate': '2027-01-31',
  'dateChanges': <Object>[],
  'bookings': <Object>[],
});

/// The app as main.dart builds it, following TutorTheme.mode.
Widget _app(Widget home) => ValueListenableBuilder<ThemeMode>(
  valueListenable: TutorTheme.mode,
  builder: (_, mode, _) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    darkTheme: TutorTheme.darkTheme,
    themeMode: mode,
    home: home,
  ),
);

Color? _scaffoldColour(WidgetTester tester) =>
    tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TutorTheme.signedOut();
    await TutorTheme.setDark(false);
  });

  group('TutorTheme', () {
    test('is light until a signed-in tutor turns dark mode on', () async {
      await TutorTheme.load();
      expect(TutorTheme.darkChosen, isFalse);
      expect(TutorTheme.mode.value, ThemeMode.light);

      TutorTheme.signedIn();
      expect(TutorTheme.mode.value, ThemeMode.light);

      await TutorTheme.setDark(true);
      expect(TutorTheme.mode.value, ThemeMode.dark);
    });

    test('the login screen is light again after signing out', () async {
      TutorTheme.signedIn();
      await TutorTheme.setDark(true);
      TutorTheme.signedOut();
      expect(TutorTheme.mode.value, ThemeMode.light);
      expect(TutorTheme.darkChosen, isTrue); // still the tutor's choice

      TutorTheme.signedIn(); // next sign-in on this device
      expect(TutorTheme.mode.value, ThemeMode.dark);
    });

    test('students and tutors each keep their own choice', () async {
      TutorTheme.signedIn('tutor');
      await TutorTheme.setDark(true);
      TutorTheme.signedOut();

      TutorTheme.signedIn('student');
      expect(TutorTheme.darkChosen, isFalse);
      expect(TutorTheme.mode.value, ThemeMode.light);

      await TutorTheme.setDark(true);
      expect(TutorTheme.mode.value, ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('student_dark_mode'), isTrue);

      await TutorTheme.setDark(false);
      TutorTheme.signedOut();
      TutorTheme.signedIn('tutor'); // still the tutor's own choice
      expect(TutorTheme.mode.value, ThemeMode.dark);
      await TutorTheme.setDark(false);
    });

    test('the choice is remembered on the device', () async {
      await TutorTheme.setDark(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tutor_dark_mode'), isTrue);

      SharedPreferences.setMockInitialValues({'tutor_dark_mode': true});
      await TutorTheme.setDark(false); // forget the in-memory value
      SharedPreferences.setMockInitialValues({'tutor_dark_mode': true});
      await TutorTheme.load();
      expect(TutorTheme.darkChosen, isTrue);
    });
  });

  group('tutor screens follow the switch', () {
    testWidgets('the notifications page turns dark and back', (tester) async {
      TutorTheme.signedIn();
      await tester.pumpWidget(
        _app(
          TutorNotificationsScreen(
            loadNotifications: () async => {
              'unreadCount': 0,
              'notifications': <Object>[],
            },
          ),
        ),
      );
      await tester.pump();
      expect(_scaffoldColour(tester), const Color(0xFFF2F4F8));

      await TutorTheme.setDark(true);
      await tester.pumpAndSettle();
      expect(_scaffoldColour(tester), TutorDark.background);

      await TutorTheme.setDark(false);
      await tester.pumpAndSettle();
      expect(_scaffoldColour(tester), const Color(0xFFF2F4F8));
    });

    testWidgets('the student Profile switch turns their screens dark', (
      tester,
    ) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      TutorTheme.signedIn('student');
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: StudentProfileTab(
              name: 'Lerato Dube',
              email: 'lerato@example.com',
              institution: 'University of Pretoria',
              photo: null,
            ),
          ),
        ),
      );
      Color background() => tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(StudentProfileTab),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color;

      expect(find.text('University of Pretoria'), findsOneWidget);
      expect(background(), const Color(0xFFF7F9FE));

      // Dark Mode sits below the profile details
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(TutorTheme.mode.value, ThemeMode.dark);
      expect(background(), TutorDark.background);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(background(), const Color(0xFFF7F9FE));
    });

    testWidgets('calendar dates use the dark tints', (tester) async {
      TutorTheme.signedIn();
      await TutorTheme.setDark(true);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: AvailabilityCalendar(
              data: _calendar,
              weekly: const {
                'Monday': {'Morning'},
              },
              onDateTap: (_) {},
            ),
          ),
        ),
      );
      // Monday 2 November has its usual hours
      final cell = tester.widget<Material>(
        find
            .ancestor(of: find.text('2'), matching: find.byType(Material))
            .first,
      );
      expect(cell.color, TutorDark.blueTint);
    });
  });
}
