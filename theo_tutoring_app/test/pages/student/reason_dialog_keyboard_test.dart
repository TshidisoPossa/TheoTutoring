import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Student/student_lesson.dart';

// iPhone SE-sized screen with the keyboard open: the reason dialog must not
// overflow, and its buttons must still be on screen and tappable.
void main() {
  testWidgets('the reason dialog fits above the phone keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300); // keyboard
    addTearDown(tester.view.reset);

    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const ReasonDialog(
                      title: 'Cancel this lesson?',
                      message:
                          'Your tutor is told straight away. A refund follows '
                          'the cancellation policy: 48 hours or more before '
                          'the lesson is a full refund, 24 to 48 hours is '
                          'half, and under 24 hours is no refund.',
                      label: 'Reason',
                      dismissLabel: 'Keep lesson',
                      submitLabel: 'Cancel lesson',
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // no overflow
    await tester.enterText(find.byType(TextFormField), 'Feeling unwell today');
    await tester.pump();

    final button = find.text('Cancel lesson');
    final visibleBottom = 667 - 300;
    expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(visibleBottom));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result, 'Feeling unwell today');
  });
}
