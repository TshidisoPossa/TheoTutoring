import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_students_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_students.dart';

Map<String, dynamic> _student(
  int id,
  String name,
  String status, {
  String? phone,
  int lessons = 0,
}) => {
  'studentId': id,
  'name': name,
  'email': '${name.split(' ').first.toLowerCase()}@example.com',
  'phone': phone,
  'course': 'BSc Computer Science',
  'institutionYear': '2nd year',
  'subjectOfInterest': 'Calculus',
  'totalLessons': lessons,
  'joinedAt': '2026-03-01T10:00:00Z',
  'status': status,
  'institution': 'University of Pretoria',
  // Sipho (13) has no proof of registration on file
  'proofOfRegistrationUrl': id == 13
      ? null
      : 'https://res.cloudinary.com/demo/image/upload/proof-$id.png',
};

/// In-memory stand-in for the expected /admin/students endpoints.
class _Backend {
  _Backend({this.total});

  final int? total;
  final requests = <http.Request>[];
  bool missingEndpoints = false;
  http.Response? patchResponse;
  Future<List<Map<String, dynamic>>?> Function(http.Request)? studentsFor;
  final students = [
    _student(
      12,
      'Lerato Mokoena',
      'Active',
      phone: '+27 82 000 0000',
      lessons: 20,
    ),
    _student(13, 'Sipho Dlamini', 'Suspended', lessons: 5),
    _student(14, 'Ayesha Patel', 'Pending'),
  ];

  late final client = MockClient((request) async {
    requests.add(request);
    expect(request.headers['Authorization'], 'Bearer admin-token');
    if (missingEndpoints) return http.Response('Route not found', 404);
    if (request.method == 'PATCH') {
      if (patchResponse != null) return patchResponse!;
      final id = int.parse(request.url.pathSegments[2]);
      final status = (jsonDecode(request.body) as Map)['status'] as String;
      final student = students.firstWhere((s) => s['studentId'] == id);
      student['status'] = status;
      return http.Response(jsonEncode(student), 200);
    }
    final override = await studentsFor?.call(request);
    return http.Response(
      jsonEncode({
        'adminName': 'Admin Tester',
        'summary': {
          'totalStudents': total ?? students.length,
          'activeThisMonth': 1,
          'avgLessonsPerStudent': 8.33,
          'suspendedAccounts': 1,
        },
        'students': override ?? students,
        'total': total ?? students.length,
        'page': int.parse(request.url.queryParameters['page'] ?? '1'),
        'pageSize': 10,
      }),
      200,
    );
  });

  AdminStudentsService service() => AdminStudentsService(
    client: client,
    tokenProvider: () async => 'admin-token',
  );

  Map<String, String> get lastQuery =>
      requests.lastWhere((r) => r.method == 'GET').url.queryParameters;
}

Future<void> _pump(WidgetTester tester, _Backend backend) async {
  // Below the shell's 900px sidebar breakpoint (its fixed-width header
  // overflows with the wide Ahem test font, which real fonts do not).
  tester.view.physicalSize = const Size(880, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AdminStudentsScreen(service: backend.service())),
  );
  await tester.pumpAndSettle();
}

Future<void> _openActions(WidgetTester tester, int rowIndex) async {
  await tester.tap(find.byTooltip('Student actions').at(rowIndex));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a clear state when the backend has no student API', (
    tester,
  ) async {
    final backend = _Backend()..missingEndpoints = true;
    await _pump(tester, backend);

    expect(find.text('Student Roster'), findsOneWidget);
    expect(
      find.text('Student management is not available yet.'),
      findsOneWidget,
    );
    expect(find.text('STUDENT NAME'), findsNothing);
  });

  testWidgets('renders summary figures and the roster from the API', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    expect(backend.lastQuery, {'status': 'all', 'page': '1', 'pageSize': '10'});
    expect(find.text('TOTAL STUDENTS'), findsOneWidget);
    expect(find.text('8.3'), findsOneWidget);
    expect(find.text('Lerato Mokoena'), findsOneWidget);
    expect(find.text('ID: STU-12'), findsOneWidget);
    expect(find.text('+27 82 000 0000'), findsOneWidget);
    expect(find.text('No phone number'), findsNWidgets(2));
    expect(find.text('Mar 1, 2026'), findsNWidgets(3));
    expect(find.text('Suspended'), findsWidgets);
    expect(find.text('Showing 1–3 of 3 students'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status filters and search are sent to the API', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(
      find
          .descendant(
            of: find.byType(InkWell),
            matching: find.text('Suspended'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(backend.lastQuery['status'], 'suspended');

    // The shared top bar has its own search box; use the roster's.
    await tester.enterText(
      find.widgetWithText(TextField, 'Search by name or email...'),
      'sipho',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(backend.lastQuery['search'], 'sipho');
    expect(backend.lastQuery['page'], '1');
  });

  testWidgets('pagination requests the chosen page', (tester) async {
    final backend = _Backend(total: 25);
    await _pump(tester, backend);

    expect(find.text('Showing 1–3 of 25 students'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(backend.lastQuery['page'], '3');
  });

  testWidgets('the actions menu shows student info and suspends them', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await _openActions(tester, 0);
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Lerato Mokoena')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('BSc Computer Science')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Calculus')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(ChoiceChip, 'Suspended'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save status'));
    await tester.pumpAndSettle();

    final patch = backend.requests.lastWhere((r) => r.method == 'PATCH');
    expect(patch.url.path, '/admin/students/12/status');
    expect(jsonDecode(patch.body), {'status': 'Suspended'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Lerato Mokoena is now Suspended.'), findsOneWidget);
  });

  testWidgets('removing a student needs confirmation and sends Deactivated', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await _openActions(tester, 2);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Removed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save status'));
    await tester.pumpAndSettle();

    expect(find.text('Remove Ayesha Patel?'), findsOneWidget);
    expect(backend.requests.where((r) => r.method == 'PATCH'), isEmpty);

    await tester.tap(find.text('Remove student'));
    await tester.pumpAndSettle();

    final patch = backend.requests.lastWhere((r) => r.method == 'PATCH');
    expect(patch.url.path, '/admin/students/14/status');
    expect(jsonDecode(patch.body), {'status': 'Deactivated'});
    expect(find.text('Ayesha Patel is now Removed.'), findsOneWidget);
  });

  testWidgets('a rejected status change is reported in the dialog', (
    tester,
  ) async {
    final backend = _Backend()
      ..patchResponse = http.Response(
        jsonEncode({
          'error': 'The administrator lacks the required permission.',
        }),
        403,
      );
    await _pump(tester, backend);

    await _openActions(tester, 1);
    // The current status is preselected, so saving is disabled until changed.
    final save = find.widgetWithText(FilledButton, 'Save status');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      find.text('The administrator lacks the required permission.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('a PATCH 404 shows the backend message, not "unavailable"', (
    tester,
  ) async {
    final backend = _Backend()
      ..patchResponse = http.Response(
        jsonEncode({'error': 'Student not found.'}),
        404,
      );
    await _pump(tester, backend);

    await _openActions(tester, 1);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save status'));
    await tester.pumpAndSettle();

    expect(find.text('Student not found.'), findsOneWidget);
    expect(find.textContaining('not available'), findsNothing);
  });

  testWidgets('a slower older roster response cannot overwrite a newer one', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    final slow = Completer<void>();
    backend.studentsFor = (request) async {
      if (request.url.queryParameters['status'] == 'all') {
        await slow.future;
        return [_student(20, 'Stale Student', 'Active')];
      }
      return [_student(21, 'Fresh Student', 'Suspended')];
    };

    await tester.enterText(
      find.widgetWithText(TextField, 'Search by name or email...'),
      'sipho',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find
          .descendant(
            of: find.byType(InkWell),
            matching: find.text('Suspended'),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Fresh Student'), findsOneWidget);

    slow.complete();
    await tester.pumpAndSettle();

    expect(find.text('Fresh Student'), findsOneWidget);
    expect(find.text('Stale Student'), findsNothing);
  });

  testWidgets('the overview shows the proof of registration to check', (
    tester,
  ) async {
    await _pump(tester, _Backend());

    await tester.tap(find.byTooltip('Student actions').at(0)); // Lerato
    await tester.pumpAndSettle();
    var dialog = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('University of Pretoria'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('View Proof of registration'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('Close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Student actions').at(1)); // Sipho
    await tester.pumpAndSettle();
    dialog = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Proof of registration: not provided'),
      ),
      findsOneWidget,
    );
  });
}
