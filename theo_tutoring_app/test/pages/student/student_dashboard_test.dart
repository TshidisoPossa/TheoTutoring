import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_confirmation.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_flow_context.dart';
import 'package:theo_tutoring_app/Pages/Student/search_tutor.dart';
import 'package:theo_tutoring_app/Pages/Student/student_bottom_nav.dart';
import 'package:theo_tutoring_app/Pages/Student/student_chatlist.dart';
import 'package:theo_tutoring_app/Pages/Student/student_dashboard.dart';
import 'package:theo_tutoring_app/Pages/Student/student_lesson.dart';
import 'package:theo_tutoring_app/Pages/Student/student_notifications.dart';
import 'package:theo_tutoring_app/Pages/Student/student_profile.dart';
import 'package:theo_tutoring_app/Pages/Student/student_tutor_profile.dart';
import 'package:theo_tutoring_app/models/tutor.dart';
import 'package:theo_tutoring_app/services/tutor_search_api.dart';

// Firebase is not initialised in widget tests, so the dashboard and the chat
// list both land in their error states; these tests only cover navigation.
Future<void> _pump(WidgetTester tester) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: StudentDashboard(studentName: 'Lerato')),
  );
  await tester.pumpAndSettle();
}

const _tutor = Tutor(
  tutorId: 7,
  userId: 42,
  name: 'Theophilus Nkhabu',
  profilePhoto: null,
  bio: '',
  experience: '3-5',
  subjects: [TutorSubject(subjectId: 3, subjectName: 'Mathematics')],
  hourlyRate: 100,
  averageRating: null,
  reviewCount: 0,
  qualification: '',
);

Finder get _topBar => find.byIcon(Icons.notifications_none_rounded);

void main() {
  testWidgets('the Chat tab shows the conversation list', (tester) async {
    await _pump(tester);
    expect(find.byType(ChatsScreen), findsNothing);
    expect(_topBar, findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatsScreen), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Chat will be connected soon.'), findsNothing);
    // ChatsScreen has its own header and no second bottom bar
    expect(_topBar, findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('Home brings the dashboard back from Chat', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatsScreen), findsNothing);
    expect(_topBar, findsOneWidget);
  });

  testWidgets('the Profile tab has Dark Mode and Log Out', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.byType(StudentProfileTab), findsOneWidget);
    expect(find.text('Profile will be connected soon.'), findsNothing);
    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
    // The Profile tab has its own header
    expect(_topBar, findsNothing);
  });

  testWidgets('the top-bar profile photo opens the Profile tab', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    expect(find.byType(StudentProfileTab), findsOneWidget);
    expect(_topBar, findsNothing);
  });

  for (final (tab, page) in [
    (1, StudentLessonsPage),
    (2, ChatsScreen),
    (3, StudentProfileTab),
  ]) {
    testWidgets('a page on top can open tab $tab without stacking copies', (
      tester,
    ) async {
      await _pump(tester);
      final dashboardContext = tester.element(find.byType(StudentDashboard));
      // Two pages deep, like Search > Tutor Profile
      for (var i = 0; i < 2; i++) {
        Navigator.of(dashboardContext).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openStudentTab(context, tab),
                child: Text('open $i'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('open 1'));
      await tester.pumpAndSettle();

      expect(find.text('open 0'), findsNothing);
      expect(find.text('open 1'), findsNothing);
      expect(find.byType(StudentDashboard), findsOneWidget);
      expect(find.byType(page), findsOneWidget);
      expect(Navigator.of(dashboardContext).canPop(), isFalse);
      expect(studentTabRequest.value, isNull);
    });
  }

  // The real pages opened from the dashboard: tutor search (side menu
  // "Subjects") and the bell. Each bar tab must land on the matching
  // dashboard tab with nothing left on top.
  Future<void> openSearch(WidgetTester tester) async {
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subjects'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchTutorPage), findsOneWidget);
  }

  Future<void> openBell(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.byType(StudentNotificationsScreen), findsOneWidget);
  }

  for (final (name, open) in [
    ('tutor search', openSearch),
    ('notifications', openBell),
  ]) {
    for (final (label, page) in [
      ('Lessons', StudentLessonsPage),
      ('Chat', ChatsScreen),
      ('Profile', StudentProfileTab),
    ]) {
      testWidgets('$label in the $name bottom bar opens that tab', (
        tester,
      ) async {
        await _pump(tester);
        await open(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(StudentBottomNav),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StudentBottomNav), findsNothing);
        expect(find.byType(page), findsOneWidget);
        expect(find.byType(StudentDashboard), findsOneWidget);
        final nav = Navigator.of(tester.element(find.byType(StudentDashboard)));
        expect(nav.canPop(), isFalse); // no duplicate dashboards or pages
      });
    }

    testWidgets('Home in the $name bottom bar goes back to Home', (
      tester,
    ) async {
      await _pump(tester);
      // Start from the Chat tab so Home has to switch back
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await open(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(StudentBottomNav),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StudentBottomNav), findsNothing);
      expect(_topBar, findsOneWidget);
      expect(find.byType(ChatsScreen), findsNothing);
    });
  }

  testWidgets('the tutor search profile photo opens the Profile tab', (
    tester,
  ) async {
    await _pump(tester);
    await openSearch(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(SearchTutorPage),
        matching: find.byTooltip('Profile'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SearchTutorPage), findsNothing);
    expect(find.byType(StudentProfileTab), findsOneWidget);
  });

  // Tutor profile > booking confirmation on top of the real dashboard (the
  // search page's API cannot be faked, so the profile is pushed directly).
  for (final (from, label, page) in [
    ('booking confirmation', 'Chat', ChatsScreen),
    ('booking confirmation', 'Lessons', StudentLessonsPage),
    ('tutor profile', 'Chat', ChatsScreen),
    ('tutor profile', 'Profile', StudentProfileTab),
  ]) {
    testWidgets('$label from the $from returns to that dashboard tab', (
      tester,
    ) async {
      await _pump(tester);
      final nav = Navigator.of(tester.element(find.byType(StudentDashboard)));
      final api = TutorSearchApi(
        client: MockClient((_) async => http.Response('{}', 404)),
      );
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => StudentTutorProfilePage(tutor: _tutor, api: api),
        ),
      );
      await tester.pumpAndSettle();
      if (from == 'booking confirmation') {
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => BookingConfirmationPage(
              flow: BookingFlowContext(
                tutor: _tutor,
                subject: _tutor.subjects.first,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(
        find.descendant(
          of: find.byType(StudentBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StudentTutorProfilePage), findsNothing);
      expect(find.byType(BookingConfirmationPage), findsNothing);
      expect(find.byType(page), findsOneWidget);
      expect(nav.canPop(), isFalse);
      expect(find.textContaining('will be connected soon'), findsNothing);
    });
  }

  testWidgets('the menu button still opens the side menu', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('Session History'), findsOneWidget);
    expect(find.byType(StudentProfileTab), findsNothing);
  });

  testWidgets('the side menu has no Settings item', (tester) async {
    await _pump(tester);
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Session History'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
  });
}
