import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Student/student_lesson.dart';
import 'package:theo_tutoring_app/Pages/Student/student_lessons_api.dart';

// Shape from GET /students/lessons (lib/student_lessons.dart). The response
// no longer has a 'link': it only comes from the join route.
Map<String, dynamic> _lesson(int id, String status) => {
  'bookingId': id,
  'status': status,
  'subject': 'Calculus',
  'tutorName': 'Amahle Tshabalala',
  'tutorPhoto': null,
  'date': '2026-11-04',
  'startTime': '15:00',
  'endTime': '16:00',
  'cancellationReason': null,
};

/// Answers fetch and join without Firebase or the network.
class _FakeLessonsApi extends StudentLessonsApi {
  _FakeLessonsApi({required this.lessons, required this.onJoin});

  final List<Map<String, dynamic>> lessons;
  final Future<String> Function(int bookingId) onJoin;
  final joined = <int>[];

  @override
  Future<Map<String, dynamic>> fetch() async => {
    'upcoming': lessons,
    'cancelled': <Map<String, dynamic>>[],
  };

  @override
  Future<String> join(int bookingId) {
    joined.add(bookingId);
    return onJoin(bookingId);
  }
}

Future<void> _pump(WidgetTester tester, _FakeLessonsApi api) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: StudentLessonsPage(api: api))),
  );
  await tester.pumpAndSettle();
}

// The nearest InkWell above the label is the button's own.
Finder _startButton() => find
    .ancestor(of: find.text('Start session'), matching: find.byType(InkWell))
    .first;

void main() {
  testWidgets("Start session shows the server's message when it refuses", (
    tester,
  ) async {
    final api = _FakeLessonsApi(
      lessons: [_lesson(7, 'Confirmed')],
      onJoin: (_) async => throw const StudentLessonsException(
        'This session opens 15 minutes before it starts.',
      ),
    );
    await _pump(tester, api);

    await tester.tap(find.text('Start session'));
    await tester.pumpAndSettle();

    expect(api.joined, [7]);
    expect(
      find.text('This session opens 15 minutes before it starts.'),
      findsOneWidget,
    );
    expect(find.text('Your session is ready'), findsNothing);
  });

  testWidgets('Start session shows a plain message when the server is '
      'unreachable', (tester) async {
    final api = _FakeLessonsApi(
      lessons: [_lesson(7, 'Confirmed')],
      onJoin: (_) async => throw Exception('timed out'),
    );
    await _pump(tester, api);

    await tester.tap(find.text('Start session'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not reach the server. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('Start session opens the ready dialog with Open Google Meet '
      'and Close', (tester) async {
    final api = _FakeLessonsApi(
      lessons: [_lesson(7, 'Postponed')],
      onJoin: (_) async => 'https://meet.google.com/aaa-bbbb-ccc',
    );
    await _pump(tester, api);

    await tester.tap(find.text('Start session'));
    await tester.pumpAndSettle();

    expect(find.text('Your session is ready'), findsOneWidget);
    expect(find.text('Open Google Meet'), findsOneWidget);
    // The link itself is not shown: Meet opens from the button.
    expect(find.text('https://meet.google.com/aaa-bbbb-ccc'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Your session is ready'), findsNothing);
  });

  testWidgets('Start session is disabled for a Pending lesson', (
    tester,
  ) async {
    final api = _FakeLessonsApi(
      lessons: [_lesson(7, 'Pending')],
      onJoin: (_) async => 'https://meet.google.com/aaa-bbbb-ccc',
    );
    await _pump(tester, api);

    expect(tester.widget<InkWell>(_startButton()).onTap, isNull);
    await tester.tap(find.text('Start session'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.joined, isEmpty);
  });
}
