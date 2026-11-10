import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/help_center.dart';

void main() {
  testWidgets('Help Center lists topics and expands an answer', (tester) async {
    // Tall enough that the list builds every topic.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HelpCenterPage()));

    expect(find.text('Help Center'), findsOneWidget);
    expect(find.text('Getting Started'), findsOneWidget);
    expect(find.text('Joining a Lesson on Google Meet'), findsOneWidget);

    const question = 'How long is a lesson?';
    const answer =
        'Every lesson is 60 minutes long. All times are shown in South '
        'African Standard Time.';
    expect(find.text(answer), findsNothing);

    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(find.text(answer), findsOneWidget);
  });
}
