import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:theo_tutoring_app/Pages/Student/student_bottom_nav.dart';
import 'package:theo_tutoring_app/Pages/Student/student_tutor_profile.dart';
import 'package:theo_tutoring_app/models/tutor.dart';

Tutor _tutor({List<TutorSubject>? subjects, double? rating = 4.5}) => Tutor(
  tutorId: 7,
  name: 'Theophilus Nkhabu',
  profilePhoto: null,
  bio: 'Engineering tutor.',
  experience: '5 years tutoring',
  subjects:
      subjects ??
      const [TutorSubject(subjectId: 3, subjectName: 'Mathematics')],
  hourlyRate: 100,
  averageRating: rating,
  reviewCount: 24,
);

Future<void> _pump(WidgetTester tester, Tutor tutor) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await tester.pumpWidget(
    MaterialApp(home: StudentTutorProfilePage(tutor: tutor)),
  );
}

void main() {
  testWidgets('shows supported tutor details, Book Session and shared nav', (
    tester,
  ) async {
    await _pump(tester, _tutor());

    expect(find.text('Tutor Profile'), findsOneWidget);
    expect(find.text('Theophilus Nkhabu'), findsOneWidget);
    expect(find.text('4.5 (24 reviews)'), findsOneWidget);
    expect(find.text('Engineering tutor.'), findsOneWidget);
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('5 years tutoring'), findsOneWidget);
    expect(find.text('100.00'), findsOneWidget);
    expect(find.text('Message Tutor'), findsNothing);
    expect(find.byType(StudentBottomNav), findsOneWidget);
    for (final label in ['Home', 'Lessons', 'Chat', 'Profile']) {
      expect(find.text(label), findsOneWidget);
    }
    final button = find.widgetWithText(FilledButton, 'Book Session');
    expect(button, findsOneWidget);
    expect(
      tester.getBottomLeft(button).dy,
      lessThan(tester.getTopLeft(find.byType(StudentBottomNav)).dy),
    );
  });

  testWidgets('single-subject tutor books directly with selected state', (
    tester,
  ) async {
    await _pump(tester, _tutor());
    await tester.tap(find.text('Book Session'));
    await tester.pumpAndSettle();

    expect(find.text('Lesson'), findsOneWidget);
    expect(find.text('Theophilus Nkhabu'), findsOneWidget);
    expect(find.textContaining('Mathematics'), findsOneWidget);
    expect(find.textContaining('R100.00'), findsOneWidget);
  });

  testWidgets('multi-subject tutor asks for the subject first', (tester) async {
    await _pump(
      tester,
      _tutor(
        subjects: const [
          TutorSubject(subjectId: 3, subjectName: 'Mathematics'),
          TutorSubject(subjectId: 4, subjectName: 'Physics'),
        ],
      ),
    );
    await tester.tap(find.text('Book Session'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a subject'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Physics'));
    await tester.pumpAndSettle();
    expect(find.text('Lesson'), findsOneWidget);
    expect(find.textContaining('Physics'), findsOneWidget);
  });

  testWidgets('no subjects disables booking; no rating is explained', (
    tester,
  ) async {
    await _pump(tester, _tutor(subjects: const [], rating: null));

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Book Session'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('No subjects listed.'), findsOneWidget);
  });

  testWidgets('non-home nav tabs show the same coming-soon message', (
    tester,
  ) async {
    await _pump(tester, _tutor());
    await tester.tap(find.text('Chat'));
    await tester.pump();
    expect(find.text('Chat will be connected soon.'), findsOneWidget);
  });
}
