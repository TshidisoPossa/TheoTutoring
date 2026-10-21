import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_dashboard.dart';

Future<void> _pump(WidgetTester tester, Map<String, dynamic> data) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: TutorDashboard(initialData: data)));
  await tester.pump();
}

int _tabIndex(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

const _tutor = {'name': 'Test Tutor'};

void main() {
  testWidgets('Active tutor reaches Requests from the bottom nav', (
    tester,
  ) async {
    await _pump(tester, {'tutor': _tutor, 'accountStatus': 'Active'});
    expect(find.text('Active Students'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.inbox_outlined));
    await tester.pump();
    expect(_tabIndex(tester), 1);
  });

  for (final status in ['Pending', 'Incomplete', 'Rejected', '']) {
    testWidgets('non-Active tutor ($status) is blocked from restricted tabs', (
      tester,
    ) async {
      await _pump(tester, {
        'tutor': _tutor,
        'accountStatus': status,
        'application': {'status': 'Pending', 'adminFeedback': 'Add a CV'},
      });
      expect(find.text('Active Students'), findsNothing);
      expect(find.text('Your application is under review'), findsOneWidget);

      for (final icon in [
        Icons.inbox_outlined,
        Icons.calendar_today_outlined,
        Icons.person_outline,
      ]) {
        await tester.tap(find.byIcon(icon));
        await tester.pump();
        expect(_tabIndex(tester), 0);
      }
      expect(
        find.text('Available once your application is approved.'),
        findsWidgets,
      );
    });
  }
}
