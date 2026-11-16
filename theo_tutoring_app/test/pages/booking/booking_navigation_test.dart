import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_confirmation.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_flow_context.dart';
import 'package:theo_tutoring_app/Pages/Student/student_bottom_nav.dart';
import 'package:theo_tutoring_app/models/tutor.dart';

final _flow = BookingFlowContext(
  tutor: const Tutor(
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
  ),
  subject: const TutorSubject(subjectId: 3, subjectName: 'Mathematics'),
  studentName: 'Lerato Mokoena',
);

// The confirmation page opened on top of a stand-in dashboard (the root).
Future<void> _pump(WidgetTester tester) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => studentTabRequest.value = null);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BookingConfirmationPage(flow: _flow),
              ),
            ),
            child: const Text('root'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('root'));
  await tester.pumpAndSettle();
  expect(find.byType(BookingConfirmationPage), findsOneWidget);
}

void main() {
  for (final (label, tab) in [('Lessons', 1), ('Chat', 2), ('Profile', 3)]) {
    testWidgets('$label in the bottom nav returns to that dashboard tab', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(StudentBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BookingConfirmationPage), findsNothing);
      expect(studentTabRequest.value, tab);
      expect(find.textContaining('will be connected soon'), findsNothing);
    });
  }

  testWidgets('the top-bar profile photo opens the Profile tab', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    expect(find.byType(BookingConfirmationPage), findsNothing);
    expect(studentTabRequest.value, 3);
  });
}
