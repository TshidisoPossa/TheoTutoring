import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_appeals_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_appeals.dart';

Map<String, dynamic> _appeal(
  int id, {
  String status = 'Pending',
  String name = 'Lerato Mokoena',
  String role = 'student',
  String? note,
}) => {
  'appealId': id,
  'status': status,
  'explanation': 'I was in hospital that week and could not attend.',
  'submittedAt': '2026-11-11T09:00:00Z',
  'decisionNote': note,
  'decidedAt': status == 'Pending' ? null : '2026-11-12T10:00:00Z',
  'reviewedBy': status == 'Pending' ? null : 'Ada Admin',
  'suspension': {
    'suspensionId': id,
    'reason': 'Repeated no-shows for booked lessons.',
    'suspendedAt': '2026-11-10T08:30:00Z',
    'suspendedBy': 'Bo Admin',
    'status': 'Active',
  },
  'user': {
    'userId': 100 + id,
    'role': role,
    'profileId': id,
    'name': name,
    'email': 'lerato@example.com',
    'phone': '+27 82 000 0000',
    'accountStatus': 'Suspended',
  },
};

/// Stand-in for GET /admin/appeals and POST /admin/appeals/{id}/decision.
class _Backend {
  final requests = <http.Request>[];
  List<Map<String, dynamic>> appeals = [_appeal(1), _appeal(2, role: 'tutor')];
  http.Response? listResponse;
  http.Response? decisionResponse;
  Completer<void>? holdList;

  late final client = MockClient((request) async {
    requests.add(request);
    expect(request.headers['Authorization'], 'Bearer admin-token');
    if (request.method == 'GET') {
      await holdList?.future;
      if (listResponse != null) return listResponse!;
      final status = request.url.queryParameters['status'];
      final rows = appeals
          .where(
            (a) => status == 'all' || '${a['status']}'.toLowerCase() == status,
          )
          .toList();
      return http.Response(
        jsonEncode({
          'adminName': 'Ada Admin',
          'summary': {
            'pending': appeals.where((a) => a['status'] == 'Pending').length,
          },
          'appeals': rows,
        }),
        200,
      );
    }
    if (decisionResponse != null) return decisionResponse!;
    final id = int.parse(request.url.pathSegments[2]);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final appeal = appeals.firstWhere((a) => a['appealId'] == id);
    appeal['status'] = body['decision'] == 'approve' ? 'Approved' : 'Rejected';
    appeal['decisionNote'] = body['note'];
    appeal['decidedAt'] = '2026-11-12T10:00:00Z';
    return http.Response(
      jsonEncode({'appeal': appeal, 'notificationDelivered': true}),
      200,
    );
  });

  AdminAppealsService service() =>
      AdminAppealsService(client: client, tokenProvider: () async => 'admin-token');

  Iterable<http.Request> get decisions =>
      requests.where((r) => r.method == 'POST');
}

Future<void> _pump(WidgetTester tester, _Backend backend) async {
  // Below the shell's 900px sidebar breakpoint, as the other admin tests do
  tester.view.physicalSize = const Size(880, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AdminAppealsScreen(service: backend.service())),
  );
  await tester.pumpAndSettle();
}

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

void main() {
  testWidgets('lists pending appeals with the account, reason and explanation',
      (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);

    expect(backend.requests.first.url.queryParameters, {'status': 'pending'});
    expect(find.text('Appeals'), findsWidgets);
    expect(find.text('2 waiting for a decision.'), findsOneWidget);
    expect(find.text('Lerato Mokoena'), findsNWidgets(2));
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Tutor'), findsOneWidget);
    expect(
      find.text('Repeated no-shows for booked lessons.'),
      findsNWidgets(2),
    );
    expect(
      find.text('I was in hospital that week and could not attend.'),
      findsNWidgets(2),
    );
    expect(find.textContaining('by Bo Admin'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Approve'), findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    final backend = _Backend()..holdList = Completer<void>();
    tester.view.physicalSize = const Size(880, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: AdminAppealsScreen(service: backend.service())),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    backend.holdList!.complete();
    await tester.pumpAndSettle();
    expect(find.text('2 waiting for a decision.'), findsOneWidget);
  });

  testWidgets('empty and filtered states', (tester) async {
    final backend = _Backend()..appeals = [];
    await _pump(tester, backend);
    expect(find.text('No appeals waiting'), findsOneWidget);

    await tester.tap(find.text('Rejected'));
    await tester.pumpAndSettle();
    expect(backend.requests.last.url.queryParameters['status'], 'rejected');
    expect(find.text('No appeals match this filter.'), findsOneWidget);
  });

  testWidgets('a load error can be retried', (tester) async {
    final backend = _Backend()
      ..listResponse = http.Response(
        jsonEncode({'error': 'Appeals could not be loaded.'}),
        500,
      );
    await _pump(tester, backend);
    expect(find.text('Could not load appeals.'), findsOneWidget);
    expect(find.text('Appeals could not be loaded.'), findsOneWidget);

    backend.listResponse = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('2 waiting for a decision.'), findsOneWidget);
  });

  testWidgets('approving asks for confirmation, then reinstates', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pumpAndSettle();
    expect(find.text('Approve appeal?'), findsOneWidget);
    expect(
      _inDialog(find.textContaining('The suspension will be lifted')),
      findsOneWidget,
    );

    // Cancel sends nothing
    await tester.tap(_inDialog(find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(backend.decisions, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pumpAndSettle();
    await tester.tap(_inDialog(find.text('Approve and reinstate')));
    await tester.pumpAndSettle();

    final post = backend.decisions.single;
    expect(post.url.path, '/admin/appeals/1/decision');
    expect(jsonDecode(post.body), {'decision': 'approve'}); // note optional
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('Appeal approved. Lerato Mokoena has been reinstated and '
          'notified.'),
      findsOneWidget,
    );
    // Reloaded: only the other pending appeal is left
    expect(find.text('1 waiting for a decision.'), findsOneWidget);
  });

  testWidgets('a rejection needs a reason for the user', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').first);
    await tester.pumpAndSettle();
    expect(find.text('Reject appeal?'), findsOneWidget);
    await tester.tap(_inDialog(find.text('Reject appeal')));
    await tester.pumpAndSettle();
    expect(
      _inDialog(find.textContaining('Explain the decision in at least 10')),
      findsOneWidget,
    );
    expect(backend.decisions, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('decision-note')),
      'The missed lessons were confirmed by three tutors.',
    );
    await tester.tap(_inDialog(find.text('Reject appeal')));
    await tester.pumpAndSettle();
    expect(jsonDecode(backend.decisions.single.body), {
      'decision': 'reject',
      'note': 'The missed lessons were confirmed by three tutors.',
    });
    expect(
      find.text('Appeal rejected. Lerato Mokoena has been notified.'),
      findsOneWidget,
    );
  });

  testWidgets('a conflicting decision is shown in the dialog', (tester) async {
    final backend = _Backend()
      ..decisionResponse = http.Response(
        jsonEncode({
          'error': 'This appeal has already been decided.',
          'code': 'appeal_already_decided',
        }),
        409,
      );
    await _pump(tester, backend);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pumpAndSettle();
    await tester.tap(_inDialog(find.text('Approve and reinstate')));
    await tester.pumpAndSettle();
    expect(
      _inDialog(find.text('This appeal has already been decided.')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('an undelivered notice is reported after a decision', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);
    backend.decisionResponse = http.Response(
      jsonEncode({
        'appeal': {...backend.appeals.first, 'status': 'Approved'},
        'notificationDelivered': false,
        'warning':
            'The decision was saved, but the notification could not be '
            'delivered right now.',
      }),
      200,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pumpAndSettle();
    await tester.tap(_inDialog(find.text('Approve and reinstate')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('notification could not be delivered'),
      findsOneWidget,
    );
  });

  testWidgets('decided appeals show the decision and no buttons', (
    tester,
  ) async {
    final backend = _Backend()
      ..appeals = [
        _appeal(5, status: 'Rejected', note: 'Confirmed by three tutors.'),
      ];
    await _pump(tester, backend);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Rejected'), findsWidgets);
    expect(find.text('Confirmed by three tutors.'), findsOneWidget);
    expect(find.textContaining('by Ada Admin'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
  });
}
