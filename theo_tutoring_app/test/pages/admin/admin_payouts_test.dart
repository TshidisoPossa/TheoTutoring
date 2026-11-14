import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_access_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_payouts_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_access_guard.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_payouts.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/admin_payout_models.dart';
import 'package:theo_tutoring_app/config/api.dart';

Map<String, dynamic> _payoutJson(int id, String status) => {
  'payoutId': id,
  'status': status,
  'amount': 300.0,
  'commissionAmount': 30.0,
  'netAmount': 270.0,
  'createdAt': '2026-11-10T09:00:00',
  'approvedAt': status == 'pending' ? null : '2026-11-11T10:30:00',
  'paidAt': status == 'paid' ? '2026-11-12T08:15:00' : null,
  'approvedBy': status == 'pending' ? null : 'Finance Admin',
  'tutor': {'tutorId': 3, 'name': 'Tutor $id', 'email': 'tutor$id@x.com'},
  'booking': {
    'bookingId': 40 + id,
    'studentName': 'Student $id',
    'subject': 'Mathematics',
    'date': '2026-11-09',
    'startTime': '10:00',
    'endTime': '11:00',
    'status': 'Completed',
  },
};

AdminPayoutsPage _page(List<Map<String, dynamic>> payouts, {int? total}) =>
    AdminPayoutsPage.fromJson({
      'adminName': 'Admin Tester',
      'total': total ?? payouts.length,
      'page': 1,
      'pageSize': 20,
      'summary': {
        'pendingCount': 1,
        'pendingNetAmount': 270.0,
        'approvedCount': 1,
        'approvedNetAmount': 270.0,
        'paidCount': 1,
        'paidNetAmount': 270.0,
      },
      'payouts': payouts,
    });

/// Answers fetchPayouts from a queue (the last answer repeats) and records
/// every call.
class _FakePayoutsService extends AdminPayoutsService {
  _FakePayoutsService(this.responses, {this.actionError})
    : super(client: MockClient((_) async => http.Response('', 500)));

  final List<Future<AdminPayoutsPage> Function()> responses;
  final Exception? actionError;
  final fetches = <PayoutStatus?>[];
  final actions = <(String, int)>[];

  @override
  Future<AdminPayoutsPage> fetchPayouts({
    PayoutStatus? status,
    int page = 1,
    int pageSize = 20,
  }) {
    fetches.add(status);
    final next = responses.length > 1 ? responses.removeAt(0) : responses.first;
    return next();
  }

  @override
  Future<void> approve(int payoutId) async {
    actions.add(('approve', payoutId));
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> markPaid(int payoutId) async {
    actions.add(('mark-paid', payoutId));
    if (actionError != null) throw actionError!;
  }
}

const _manage = ['admin.finance.read', 'admin.payouts.manage'];

Future<void> _pump(
  WidgetTester tester,
  _FakePayoutsService service, {
  List<String> permissions = _manage,
}) async {
  // Below the shell's 900px sidebar breakpoint (its fixed-width header
  // overflows with the wide Ahem test font, which real fonts do not).
  tester.view.physicalSize = const Size(880, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AdminPermissionScope(
      access: AdminAccessResult.allowed(
        'Admin Tester',
        permissions: permissions,
      ),
      child: MaterialApp(home: AdminPayoutsScreen(service: service)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AdminPayoutsScreen', () {
    testWidgets('lists payouts with amounts, people, status and timestamps', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([
          _payoutJson(1, 'pending'),
          _payoutJson(2, 'approved'),
          _payoutJson(3, 'paid'),
        ]),
      ]);
      await _pump(tester, service);

      expect(find.text('Tutor 1'), findsOneWidget);
      expect(find.text('Payout #1 · tutor1@x.com'), findsOneWidget);
      expect(find.text('Gross amount'), findsNWidgets(3));
      expect(find.text('Commission'), findsNWidgets(3));
      expect(find.text('Tutor net'), findsNWidgets(3));
      expect(find.text('R 300.00'), findsNWidgets(3));
      expect(find.text('R 30.00'), findsNWidgets(3));
      expect(
        find.text(
          'Booking #41 · Mathematics · Student: Student 1 · '
          '2026-11-09 10:00–11:00',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Created 10 Nov 2026, 09:00'),
        findsNWidgets(3),
      );
      expect(
        find.textContaining('Approved 11 Nov 2026, 10:30 by Finance Admin'),
        findsNWidgets(2),
      );
      expect(find.textContaining('Marked paid 12 Nov 2026, 08:15'), findsOne);
      // Pending -> approve only, Approved -> mark paid only, Paid -> nothing.
      expect(find.text('Approve payout'), findsOneWidget);
      expect(find.text('Mark as paid'), findsOneWidget);
      expect(find.text('3 payouts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filters by status', (tester) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(1, 'pending')]),
      ]);
      await _pump(tester, service);
      await tester.tap(find.text('Approved').first);
      await tester.pumpAndSettle();
      expect(service.fetches, [null, PayoutStatus.approved]);
    });

    testWidgets('shows an empty state', (tester) async {
      final service = _FakePayoutsService([() async => _page([])]);
      await _pump(tester, service);
      expect(find.text('No payouts yet'), findsOneWidget);
    });

    testWidgets('shows the backend error with a working retry', (tester) async {
      final service = _FakePayoutsService([
        () async => throw Exception('Payouts are temporarily unavailable.'),
        () async => _page([_payoutJson(1, 'pending')]),
      ]);
      await _pump(tester, service);

      expect(find.text('Could not load payouts.'), findsOneWidget);
      expect(find.text('Payouts are temporarily unavailable.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Tutor 1'), findsOneWidget);
      expect(service.fetches, hasLength(2));
    });

    testWidgets('refresh reloads the list', (tester) async {
      final service = _FakePayoutsService([() async => _page([])]);
      await _pump(tester, service);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(service.fetches, hasLength(2));
    });

    testWidgets('approving asks for confirmation first', (tester) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(1, 'pending')]),
      ]);
      await _pump(tester, service);

      await tester.tap(find.text('Approve payout'));
      await tester.pumpAndSettle();
      expect(find.text('Approve payout?'), findsOneWidget);
      expect(find.textContaining('It does not pay the tutor'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.actions, isEmpty);

      await tester.tap(find.text('Approve payout'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Approve payout').last,
      );
      await tester.pumpAndSettle();
      expect(service.actions, [('approve', 1)]);
      expect(find.text('Payout approved.'), findsOneWidget);
      expect(service.fetches, hasLength(2));
    });

    testWidgets('marking as paid confirms it moves no money', (tester) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(2, 'approved')]),
      ]);
      await _pump(tester, service);

      await tester.tap(find.text('Mark as paid'));
      await tester.pumpAndSettle();
      expect(find.text('Mark payout as paid?'), findsOneWidget);
      expect(
        find.textContaining('It does not transfer any money'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid').last);
      await tester.pumpAndSettle();
      expect(service.actions, [('mark-paid', 2)]);
      expect(find.text('Payout recorded as paid.'), findsOneWidget);
    });

    testWidgets('shows why an action was refused and reloads', (tester) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(2, 'approved')]),
      ], actionError: Exception('This payout is already marked as paid.'));
      await _pump(tester, service);

      await tester.tap(find.text('Mark as paid'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Action failed: This payout is already marked as paid.'),
        findsOneWidget,
      );
      expect(service.fetches, hasLength(2));
    });

    testWidgets('an unexpected status shows Unknown with no actions', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(1, 'reversed')]),
      ]);
      await _pump(tester, service);
      expect(find.text('Tutor 1'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('Approve payout'), findsNothing);
      expect(find.text('Mark as paid'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing status shows Unknown with no actions', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(1, 'pending')..remove('status')]),
      ]);
      await _pump(tester, service);
      expect(find.text('Tutor 1'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('Approve payout'), findsNothing);
      expect(find.text('Mark as paid'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides actions without admin.payouts.manage', (tester) async {
      final service = _FakePayoutsService([
        () async =>
            _page([_payoutJson(1, 'pending'), _payoutJson(2, 'approved')]),
      ]);
      await _pump(tester, service, permissions: const ['admin.finance.read']);
      expect(find.text('Tutor 1'), findsOneWidget);
      expect(find.text('Approve payout'), findsNothing);
      expect(find.text('Mark as paid'), findsNothing);
    });
  });

  group('AdminPayoutsService', () {
    test('lists with the status filter and a bearer token', () async {
      late http.Request sent;
      final service = AdminPayoutsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'total': 1,
              'page': 1,
              'pageSize': 20,
              'summary': {'pendingCount': 1, 'pendingNetAmount': 270.0},
              'payouts': [_payoutJson(1, 'pending')],
            }),
            200,
          );
        }),
        tokenProvider: () async => 'token',
      );
      final page = await service.fetchPayouts(status: PayoutStatus.pending);
      expect(
        sent.url,
        Uri.parse(
          '$apiBaseUrl/admin/payouts?status=pending&page=1&pageSize=20',
        ),
      );
      expect(sent.headers['Authorization'], 'Bearer token');
      expect(page.payouts.single.status, PayoutStatus.pending);
      expect(page.payouts.single.netAmount, 270.0);
      expect(page.summary.pendingCount, 1);
    });

    test('posts approve and mark-paid to their endpoints', () async {
      final sent = <http.Request>[];
      final service = AdminPayoutsService(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('{"ok":true}', 200);
        }),
        tokenProvider: () async => 'token',
      );
      await service.approve(5);
      await service.markPaid(5);
      expect(sent.map((r) => (r.method, r.url.path)), [
        ('POST', Uri.parse('$apiBaseUrl/admin/payouts/5/approve').path),
        ('POST', Uri.parse('$apiBaseUrl/admin/payouts/5/mark-paid').path),
      ]);
    });

    test('surfaces the backend error message', () async {
      final service = AdminPayoutsService(
        client: MockClient(
          (_) async => http.Response(
            '{"error":"Approve this payout before marking it as paid."}',
            409,
          ),
        ),
        tokenProvider: () async => 'token',
      );
      await expectLater(
        service.markPaid(5),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Approve this payout before marking it as paid.',
          ),
        ),
      );
    });

    test('requires a signed-in user', () async {
      final service = AdminPayoutsService(
        client: MockClient((_) async => fail('no request expected')),
        tokenProvider: () async => null,
      );
      await expectLater(service.fetchPayouts(), throwsA(isA<Exception>()));
    });
  });
}
