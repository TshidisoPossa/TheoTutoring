import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_dashboard.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_schedule.dart';

Future<void> _pump(WidgetTester tester, Map<String, dynamic> data) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: TutorDashboard(initialData: data)));
  await tester.pump();
}

const _tutor = {'name': 'Test Tutor'};

void main() {
  testWidgets('Active tutor sees stats, not the application status', (
    tester,
  ) async {
    await _pump(tester, {'tutor': _tutor, 'accountStatus': 'Active'});
    expect(find.text('Active Students'), findsOneWidget);
    expect(find.text('Application under review'), findsNothing);
  });

  for (final status in ['Pending', 'Incomplete', 'Rejected', '']) {
    testWidgets('non-Active tutor ($status) is blocked from Schedule and Chats', (
      tester,
    ) async {
      await _pump(tester, {
        'tutor': _tutor,
        'accountStatus': status,
        'application': {'status': 'Pending'},
      });
      expect(find.text('Active Students'), findsNothing);
      expect(find.text('Application under review'), findsWidgets);

      for (final (icon, what) in [
        (Icons.inbox_rounded, 'Your schedule opens once'),
        (Icons.chat_bubble_outline_rounded, 'Chats opens once'),
      ]) {
        await tester.tap(find.byIcon(icon));
        await tester.pump();
        expect(find.textContaining(what), findsOneWidget);
        expect(find.byType(TutorDashboard), findsOneWidget);
      }
    });
  }

  testWidgets('Active tutor can leave the dashboard from the bottom nav', (
    tester,
  ) async {
    await _pump(tester, {'tutor': _tutor, 'accountStatus': 'Active'});
    expect(find.byType(TutorScheduleScreen), findsNothing);
    await tester.tap(find.byIcon(Icons.inbox_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.byType(TutorScheduleScreen), findsOneWidget);
    expect(find.byType(TutorDashboard), findsNothing);
  });

  testWidgets('Rejected tutor sees feedback and Correct and resubmit', (
    tester,
  ) async {
    await _pump(tester, {
      'tutor': _tutor,
      'accountStatus': 'Rejected',
      'application': {
        'status': 'Rejected',
        'adminFeedback': 'Please upload a clearer certificate.',
      },
    });
    expect(find.text('Application not approved'), findsWidgets);
    expect(find.text('Please upload a clearer certificate.'), findsOneWidget);
    expect(find.text('Correct and resubmit'), findsOneWidget);
    expect(find.text('Active Students'), findsNothing);
  });
}
