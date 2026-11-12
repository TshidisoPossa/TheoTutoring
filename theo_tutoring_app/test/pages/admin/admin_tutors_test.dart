import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_tutors_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_tutors.dart';

Map<String, dynamic> _tutor(
  int id,
  String name,
  String status, {
  String? phone,
  int lessons = 0,
  double rating = 0,
  int reviews = 0,
}) => {
  'tutorId': id,
  'name': name,
  'email': '${name.split(' ').first.toLowerCase()}@example.com',
  'phone': phone,
  'subjects': 'Calculus, Physics',
  'experience': '1-2',
  'verification': status == 'Pending' ? 'Pending' : 'Approved',
  'averageRating': rating,
  'reviewCount': reviews,
  'totalLessons': lessons,
  'joinedAt': '2026-03-01T10:00:00Z',
  'status': status,
};

/// In-memory stand-in for the /admin/tutors endpoints.
class _Backend {
  _Backend({this.total});

  final int? total;
  final requests = <http.Request>[];
  bool missingEndpoints = false;
  http.Response? patchResponse;
  Future<List<Map<String, dynamic>>?> Function(http.Request)? tutorsFor;
  final tutors = [
    _tutor(
      12,
      'Lerato Mokoena',
      'Active',
      phone: '+27 82 000 0000',
      lessons: 20,
      rating: 4.5,
      reviews: 2,
    ),
    _tutor(13, 'Sipho Dlamini', 'Suspended', lessons: 5),
    _tutor(14, 'Ayesha Patel', 'Pending'),
  ];

  late final client = MockClient((request) async {
    requests.add(request);
    expect(request.headers['Authorization'], 'Bearer admin-token');
    if (missingEndpoints) return http.Response('Route not found', 404);
    if (request.method == 'PATCH') {
      if (patchResponse != null) return patchResponse!;
      final id = int.parse(request.url.pathSegments[2]);
      final status = (jsonDecode(request.body) as Map)['status'] as String;
      final tutor = tutors.firstWhere((t) => t['tutorId'] == id);
      tutor['status'] = status;
      return http.Response(jsonEncode(tutor), 200);
    }
    final override = await tutorsFor?.call(request);
    return http.Response(
      jsonEncode({
        'adminName': 'Admin Tester',
        'summary': {
          'totalTutors': total ?? tutors.length,
          'activeThisMonth': 1,
          'avgLessonsPerTutor': 8.33,
          'suspendedAccounts': 1,
        },
        'tutors': override ?? tutors,
        'total': total ?? tutors.length,
        'page': int.parse(request.url.queryParameters['page'] ?? '1'),
        'pageSize': 10,
      }),
      200,
    );
  });

  AdminTutorsService service() => AdminTutorsService(
    client: client,
    tokenProvider: () async => 'admin-token',
  );

  Map<String, String> get lastQuery =>
      requests.lastWhere((r) => r.method == 'GET').url.queryParameters;

  Iterable<http.Request> get patches =>
      requests.where((r) => r.method == 'PATCH');
}

Future<void> _pump(WidgetTester tester, _Backend backend) async {
  // Below the shell's 900px sidebar breakpoint (its fixed-width header
  // overflows with the wide Ahem test font, which real fonts do not).
  tester.view.physicalSize = const Size(880, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AdminTutorsScreen(service: backend.service())),
  );
  await tester.pumpAndSettle();
}

Future<void> _openActions(WidgetTester tester, int rowIndex) async {
  await tester.tap(find.byTooltip('Tutor actions').at(rowIndex));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a clear state when the backend has no tutor API', (
    tester,
  ) async {
    final backend = _Backend()..missingEndpoints = true;
    await _pump(tester, backend);

    expect(find.text('Tutor Roster'), findsOneWidget);
    expect(find.text('Tutor management is not available yet.'), findsOneWidget);
    expect(find.text('TUTOR NAME'), findsNothing);
  });

  testWidgets('renders summary figures and the roster from the API', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    expect(backend.lastQuery, {'status': 'all', 'page': '1', 'pageSize': '10'});
    expect(find.text('TOTAL TUTORS'), findsOneWidget);
    expect(find.text('AVG LESSONS/TUTOR'), findsOneWidget);
    expect(find.text('8.3'), findsOneWidget);
    expect(find.text('Lerato Mokoena'), findsOneWidget);
    expect(find.text('ID: TUT-12'), findsOneWidget);
    expect(find.text('+27 82 000 0000'), findsOneWidget);
    expect(find.text('Mar 1, 2026'), findsNWidgets(3));
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Showing 1–3 of 3 tutors'), findsOneWidget);
    expect(find.text('Add Tutor'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status filters (including Pending) and search reach the API', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    Finder chip(String label) => find
        .descendant(of: find.byType(InkWell), matching: find.text(label))
        .first;
    await tester.tap(chip('Pending'));
    await tester.pumpAndSettle();
    expect(backend.lastQuery['status'], 'pending');

    await tester.tap(chip('Suspended'));
    await tester.pumpAndSettle();
    expect(backend.lastQuery['status'], 'suspended');

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

    expect(find.text('Showing 1–3 of 25 tutors'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(backend.lastQuery['page'], '3');
  });

  testWidgets('the actions menu shows tutor info and suspends them', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await _openActions(tester, 0);
    final dialog = find.byType(AlertDialog);
    for (final text in [
      'Lerato Mokoena',
      'Calculus, Physics',
      '1-2 years',
      'Approved',
      '4.5 (2 reviews)',
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }

    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(ChoiceChip, 'Suspended'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save status'));
    await tester.pumpAndSettle();

    final patch = backend.patches.last;
    expect(patch.url.path, '/admin/tutors/12/status');
    expect(jsonDecode(patch.body), {'status': 'Suspended'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Lerato Mokoena is now Suspended.'), findsOneWidget);
  });

  testWidgets('removing a tutor needs confirmation and sends Deactivated', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await _openActions(tester, 1);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Removed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save status'));
    await tester.pumpAndSettle();

    expect(find.text('Remove Sipho Dlamini?'), findsOneWidget);
    expect(backend.patches, isEmpty);

    await tester.tap(find.text('Remove tutor'));
    await tester.pumpAndSettle();

    final patch = backend.patches.last;
    expect(patch.url.path, '/admin/tutors/13/status');
    expect(jsonDecode(patch.body), {'status': 'Deactivated'});
    expect(find.text('Sipho Dlamini is now Removed.'), findsOneWidget);
  });

  testWidgets('a tutor still in review is sent to the Applications page', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await _openActions(tester, 2);
    expect(
      find.text(
        'This tutor has not been approved yet. Approve or reject them on '
        'the Applications page.',
      ),
      findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    final save = find.widgetWithText(FilledButton, 'Save status');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
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
        jsonEncode({'error': 'Tutor not found.'}),
        404,
      );
    await _pump(tester, backend);

    await _openActions(tester, 1);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save status'));
    await tester.pumpAndSettle();

    expect(find.text('Tutor not found.'), findsOneWidget);
    expect(find.textContaining('not available'), findsNothing);
  });

  testWidgets('a slower older roster response cannot overwrite a newer one', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    final slow = Completer<void>();
    backend.tutorsFor = (request) async {
      if (request.url.queryParameters['status'] == 'all') {
        await slow.future;
        return [_tutor(20, 'Stale Tutor', 'Active')];
      }
      return [_tutor(21, 'Fresh Tutor', 'Suspended')];
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
    expect(find.text('Fresh Tutor'), findsOneWidget);

    slow.complete();
    await tester.pumpAndSettle();

    expect(find.text('Fresh Tutor'), findsOneWidget);
    expect(find.text('Stale Tutor'), findsNothing);
  });

  testWidgets('Add Tutor and Export CSV say they are not ready yet', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(find.text('Add Tutor'));
    await tester.pump();
    expect(find.text('Adding a tutor is not available yet.'), findsOneWidget);
    expect(backend.patches, isEmpty);
  });
}
