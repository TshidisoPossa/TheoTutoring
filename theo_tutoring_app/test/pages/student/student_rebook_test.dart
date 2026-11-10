import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_flow_context.dart';
import 'package:theo_tutoring_app/Pages/Student/student_rebook.dart';
import 'package:theo_tutoring_app/models/tutor.dart';

const _tutor = Tutor(
  tutorId: 3,
  name: 'Thabo Mokoena',
  profilePhoto: null,
  bio: null,
  experience: null,
  subjects: [
    TutorSubject(subjectId: 5, subjectName: 'Physics'),
    TutorSubject(subjectId: 7, subjectName: 'Calculus'),
  ],
  hourlyRate: 250,
  averageRating: null,
  reviewCount: 0,
);

void main() {
  testWidgets('opens the booking page for the same tutor and subject', (
    tester,
  ) async {
    BookingFlowContext? flow;
    await tester.pumpWidget(
      MaterialApp(
        home: StudentRebookPage(
          tutorId: 3,
          subjectId: 7,
          studentName: 'Lerato',
          loadTutor: (id) async => _tutor,
          bookingPage: (f) {
            flow = f;
            return const Scaffold(body: Text('choose a lesson'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('choose a lesson'), findsOneWidget);
    expect(find.byType(StudentRebookPage), findsNothing); // replaced
    expect(flow?.tutor.tutorId, 3);
    expect(flow?.subject.subjectName, 'Calculus');
    expect(flow?.studentName, 'Lerato');
  });

  testWidgets('shows the error and tries again', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StudentRebookPage(
          tutorId: 3,
          subjectId: 7,
          loadTutor: (id) async {
            attempts++;
            if (attempts == 1) throw Exception('offline');
            return _tutor;
          },
          bookingPage: (_) => const Scaffold(body: Text('choose a lesson')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open the booking page. Check your connection.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('choose a lesson'), findsOneWidget);
  });
}
