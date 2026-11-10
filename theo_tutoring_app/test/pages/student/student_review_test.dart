import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Student/student_lesson.dart';
import 'package:theo_tutoring_app/Pages/Student/student_lessons_api.dart';
import 'package:theo_tutoring_app/Pages/Student/student_review.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_theme.dart';

final _lesson = Lesson.fromJson({
  'bookingId': 41,
  'status': 'Completed',
  'subject': 'Mathematics',
  'tutorName': 'Dr. Elena Rostova',
  'date': '2026-10-19',
  'startTime': '16:00',
  'endTime': '17:00',
  'myRating': null,
  'tutorRating': 4.9,
  'tutorReviewCount': 142,
  'tutorVerified': true,
  'tutorSubjects': 'Mathematics, Physics',
});

const _student = ReviewStudent(
  name: 'Lerato Dube',
  year: '2',
  institution: 'University of Pretoria',
);

Future<void> _pump(
  WidgetTester tester,
  SubmitReview submit, {
  ReportLesson? report,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => LeaveReviewScreen(
                  lesson: _lesson,
                  student: _student,
                  submit: submit,
                  report: report,
                  now: () => DateTime(2026, 10, 19, 18),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('a Completed lesson reads the review header details', () {
    expect(_lesson.isCompleted, isTrue);
    expect(_lesson.myRating, isNull);
    expect(_lesson.tutorRating, 4.9);
    expect(_lesson.tutorReviewCount, 142);
    expect(_lesson.tutorVerified, isTrue);
    final reviewed = Lesson.fromJson({
      'bookingId': 42,
      'status': 'Completed',
      'date': '2026-10-19',
      'startTime': '09:00',
      'endTime': '10:00',
      'myRating': 4,
    });
    expect(reviewed.myRating, 4);
    expect(reviewed.tutorReviewCount, 0);
    expect(reviewed.tutorVerified, isFalse);
  });

  testWidgets('shows the session like the design', (tester) async {
    await _pump(tester, (_, _) async {});

    expect(find.text('Leave A Review'), findsOneWidget);
    expect(find.text('Completed Session • Mathematics'), findsOneWidget);
    expect(find.text('60 mins'), findsOneWidget);
    expect(find.text('Dr. Elena Rostova'), findsOneWidget);
    expect(find.text('Mathematics, Physics tutor'), findsOneWidget);
    expect(find.text('4.9 (142 reviews)'), findsOneWidget);
    expect(find.byTooltip('Verified tutor'), findsOneWidget);
    expect(find.text('Today, 4:00 PM - 5:00 PM'), findsOneWidget);
    expect(find.text('Lerato Dube (Year 2)'), findsOneWidget);
    expect(find.text('How was your session with Elena?'), findsOneWidget);
    expect(find.text('What made this session great?'), findsOneWidget);
    expect(find.text('Public Review for Elena'), findsOneWidget);
    expect(find.text('Private note for platform support'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
    expect(find.text('Need help with this session?'), findsOneWidget);
  });

  testWidgets('submits stars, review, badges and private note', (tester) async {
    int? savedBooking;
    ReviewDraft? saved;
    await _pump(tester, (bookingId, draft) async {
      savedBooking = bookingId;
      saved = draft;
    });

    // Submit stays disabled until a star is chosen
    final button = find.widgetWithText(FilledButton, 'Submit Review');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('review-star-5')));
    await tester.pump();
    expect(find.text('Outstanding!'), findsOneWidget);

    await tester.tap(find.text('Patient with questions'));
    await tester.tap(find.text('Clear explanations'));
    await tester.tap(find.text('Encouraging atmosphere'));
    await tester.tap(find.text('Encouraging atmosphere')); // and off again
    await tester.enterText(
      find.byKey(const ValueKey('review-public')),
      'Very patient tutor.',
    );
    await tester.pump();
    expect(find.text('19 / 500'), findsOneWidget);

    await tester.tap(find.text('Private note for platform support'));
    await tester.pump();
    expect(
      find.text('Only the TheoTutoring team reads this. Elena never sees it.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('review-private')),
      'The Meet link changed at the last minute.',
    );

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(savedBooking, 41);
    expect(saved?.rating, 5);
    expect(saved?.comment, 'Very patient tutor.');
    expect(saved?.highlights, ['Clear explanations', 'Patient with questions']);
    expect(saved?.privateNote, 'The Meet link changed at the last minute.');
    expect(find.byType(LeaveReviewScreen), findsNothing);
    expect(find.text('Thank you! Your review was posted.'), findsOneWidget);
  });

  testWidgets('only the stars are required', (tester) async {
    ReviewDraft? saved;
    await _pump(tester, (_, draft) async => saved = draft);

    await tester.tap(find.byKey(const ValueKey('review-star-3')));
    await tester.pump();
    // A lower rating asks a softer question
    expect(find.text('What went well?'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Submit Review');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(saved?.rating, 3);
    expect(saved?.comment, isNull);
    expect(saved?.highlights, isEmpty);
    expect(saved?.privateNote, isNull);
  });

  testWidgets('Skip for now closes without saving', (tester) async {
    var saves = 0;
    await _pump(tester, (_, _) async => saves++);

    await tester.ensureVisible(find.text('Skip for now'));
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(saves, 0);
    expect(find.byType(LeaveReviewScreen), findsNothing);
  });

  testWidgets('Need help sends a report to the admin', (tester) async {
    int? reportedBooking;
    String? reason;
    await _pump(
      tester,
      (_, _) async {},
      report: (bookingId, text) async {
        reportedBooking = bookingId;
        reason = text;
      },
    );

    await tester.ensureVisible(find.text('Need help with this session?'));
    await tester.tap(find.text('Need help with this session?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'My tutor never joined the call.',
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(reportedBooking, 41);
    expect(reason, 'My tutor never joined the call.');
    expect(
      find.text('Sent. An administrator will look into it.'),
      findsOneWidget,
    );
    expect(find.byType(LeaveReviewScreen), findsOneWidget); // still reviewing
  });

  testWidgets('a failed save keeps the screen open with the error', (
    tester,
  ) async {
    await _pump(
      tester,
      (_, _) async => throw const StudentLessonsException(
        'You have already reviewed this lesson.',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('review-star-3')));
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Submit Review');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(LeaveReviewScreen), findsOneWidget);
    expect(find.text('You have already reviewed this lesson.'), findsOneWidget);
  });

  testWidgets('fits an iPhone-sized screen', (tester) async {
    await _pump(tester, (_, _) async {});
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the dark colours in dark mode', (tester) async {
    await _pump(tester, (_, _) async {}, theme: TutorTheme.darkTheme);

    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(LeaveReviewScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor, TutorDark.background);
  });
}
