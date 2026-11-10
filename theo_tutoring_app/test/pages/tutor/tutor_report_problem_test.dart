import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_api.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_report_problem.dart';

/// Records what the page sends instead of calling the backend.
class _Backend {
  final sent = <Map<String, Object?>>[];
  int studentLoads = 0;
  Object? sendError;

  Future<List<Map<String, dynamic>>> loadStudents() async {
    studentLoads++;
    return [
      {'userId': 15, 'name': 'Dumisani Khumalo', 'photo': null},
      {'userId': 22, 'name': 'Lerato Dube', 'photo': null},
    ];
  }

  Future<Map<String, dynamic>> send({
    required String category,
    required String description,
    int? studentUserId,
  }) async {
    final error = sendError;
    if (error != null) throw error;
    sent.add({
      'category': category,
      'description': description,
      'studentUserId': studentUserId,
    });
    return {'reportId': 1, 'message': 'Report sent. The admin team will look into it.'};
  }
}

/// Opens the page from a button, like the Profile does, and keeps what it
/// popped with.
Future<List<String?>> _open(WidgetTester tester, _Backend backend) async {
  final popped = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => popped.add(
              await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => TutorReportProblemPage(
                    loadStudents: backend.loadStudents,
                    sendReport: backend.send,
                  ),
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
  return popped;
}

Future<void> _choose(WidgetTester tester, Key field, String item) async {
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Send report'));
  await tester.tap(find.text('Send report'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the dropdown has the three categories', (tester) async {
    await _open(tester, _Backend());
    await tester.tap(find.byKey(const ValueKey('report-category')));
    await tester.pumpAndSettle();

    expect(find.text('Payments & Payouts'), findsWidgets);
    expect(find.text('Student issues'), findsWidgets);
    expect(find.text('Other'), findsWidgets);
  });

  testWidgets('a payments report is sent with its description', (
    tester,
  ) async {
    final backend = _Backend();
    final popped = await _open(tester, backend);

    await _choose(
      tester,
      const ValueKey('report-category'),
      'Payments & Payouts',
    );
    expect(find.text('Student'), findsNothing); // no student to pick
    await tester.enterText(
      find.byKey(const ValueKey('report-description')),
      '  My payout for October has not arrived.  ',
    );
    await _send(tester);

    expect(backend.sent.single, {
      'category': 'Payments & Payouts',
      'description': 'My payout for October has not arrived.',
      'studentUserId': null,
    });
    expect(backend.studentLoads, 0);
    expect(popped, ['Report sent. The admin team will look into it.']);
  });

  testWidgets('Student issues asks which student', (tester) async {
    final backend = _Backend();
    await _open(tester, backend);

    await _choose(tester, const ValueKey('report-category'), 'Student issues');
    expect(backend.studentLoads, 1);
    await tester.enterText(
      find.byKey(const ValueKey('report-description')),
      'The student was rude during our lesson.',
    );

    // Not sent until a student is chosen
    await _send(tester);
    expect(find.text('Choose the student this report is about.'), findsOneWidget);
    expect(backend.sent, isEmpty);

    await _choose(tester, const ValueKey('report-student'), 'Lerato Dube');
    await _send(tester);
    expect(backend.sent.single['studentUserId'], 22);
    expect(backend.sent.single['category'], 'Student issues');
  });

  testWidgets('nothing is sent without a category and description', (
    tester,
  ) async {
    final backend = _Backend();
    await _open(tester, backend);
    await _send(tester);

    expect(find.text('Choose a category.'), findsOneWidget);
    expect(
      find.text('Describe the problem in at least 10 characters.'),
      findsOneWidget,
    );
    expect(backend.sent, isEmpty);
  });

  testWidgets('a server error stays on the page', (tester) async {
    final backend = _Backend()
      ..sendError = const TutorApiException(
        'You have already reported this student.',
        statusCode: 409,
      );
    final popped = await _open(tester, backend);

    await _choose(tester, const ValueKey('report-category'), 'Other');
    await tester.enterText(
      find.byKey(const ValueKey('report-description')),
      'The app logged me out twice today.',
    );
    await _send(tester);

    expect(find.text('You have already reported this student.'), findsOneWidget);
    expect(find.byType(TutorReportProblemPage), findsOneWidget);
    expect(popped, isEmpty);
  });
}
