import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:theo_tutoring_app/Pages/Student/student_chatlist.dart';
import 'package:theo_tutoring_app/Pages/Student/student_dashboard.dart';

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

  testWidgets('Profile still shows its placeholder', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Profile'));
    await tester.pump();

    expect(find.text('Profile will be connected soon.'), findsOneWidget);
    expect(find.byType(ChatsScreen), findsNothing);
    expect(_topBar, findsOneWidget);
  });
}
