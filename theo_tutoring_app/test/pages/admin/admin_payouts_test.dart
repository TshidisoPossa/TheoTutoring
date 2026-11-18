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

/// A reconciled overview, as GET /admin/payouts sends it.
Map<String, dynamic> _financeJson({
  String difference = '0.00',
  bool reconciled = true,
  List<Map<String, dynamic>> issues = const [],
}) => {
  'moneyReceived': '1445.00',
  'platformCommission': '37.50',
  'owedToTutors': '157.50',
  'paidToTutors': '180.00',
  'refunded': '272.50',
  'heldForUpcomingLessons': '185.00',
  'retainedCancellationRevenue': '262.50',
  'awaitingRefundDecision': '175.00',
  'awaitingPayoutGeneration': '175.00',
  'unallocated': '0.00',
  'accountedFor': '1445.00',
  'difference': difference,
  'reconciled': reconciled,
  'counts': {
    'eligibleLessons': 1,
    'awaitingPayoutGeneration': 1,
    'upcomingLessons': 1,
    'pendingPayouts': 1,
    'approvedPayouts': 0,
    'paidPayouts': 1,
  },
  'issues': issues,
};

AdminPayoutsPage _page(
  List<Map<String, dynamic>> payouts, {
  int? total,
  Map<String, dynamic>? finance,
}) => AdminPayoutsPage.fromJson({
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
  'finance': ?finance,
  'payouts': payouts,
});

/// Answers fetchPayouts from a queue (the last answer repeats) and records
/// every call.
class _FakePayoutsService extends AdminPayoutsService {
  _FakePayoutsService(this.responses, {this.actionError})
    : super(client: MockClient((_) async => http.Response('', 500)));

  final List<Future<AdminPayoutsPage> Function()> responses;
  final Exception? actionError;
  static const generated = 2;
  final fetches = <PayoutStatus?>[];
  final actions = <(String, int)>[];
  final references = <String?>[];

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
  Future<void> markPaid(int payoutId, {String? reference}) async {
    actions.add(('mark-paid', payoutId));
    references.add(reference);
    if (actionError != null) throw actionError!;
  }

  @override
  Future<({int generated, String message})> generate() async {
    actions.add(('generate', 0));
    if (actionError != null) throw actionError!;
    return (generated: generated, message: '$generated payouts generated.');
  }
}

const _manage = ['admin.finance.read', 'admin.payouts.manage'];

/// The payment-reference field of the Mark as paid dialog (the shell has its
/// own search field).
final _referenceField = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

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
      expect(service.references, ['']); // no reference entered
      expect(find.text('Payout recorded as paid.'), findsOneWidget);
    });

    testWidgets('marking as paid sends the optional external reference', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(2, 'approved')]),
      ]);
      await _pump(tester, service);

      await tester.tap(find.text('Mark as paid'));
      await tester.pumpAndSettle();
      await tester.enterText(_referenceField, '  EFT-2026-001  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid').last);
      await tester.pumpAndSettle();
      expect(service.references, ['EFT-2026-001']);
      expect(service.fetches, hasLength(2)); // totals and list refreshed
    });

    testWidgets('cancelling the payment dialog changes nothing', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(2, 'approved')]),
      ]);
      await _pump(tester, service);
      await tester.tap(find.text('Mark as paid'));
      await tester.pumpAndSettle();
      await tester.enterText(_referenceField, 'EFT-1');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.actions, isEmpty);
    });

    testWidgets('a paid payout shows who paid it and the reference', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([
          _payoutJson(3, 'paid')
            ..['paidBy'] = 'Finance Admin'
            ..['paymentReference'] = 'EFT-2026-001'
            ..['commissionRate'] = '10.00'
            ..['commissionRateBackfilled'] = true,
        ]),
      ]);
      await _pump(tester, service);
      expect(
        find.textContaining('Marked paid 12 Nov 2026, 08:15 by Finance Admin'),
        findsOneWidget,
      );
      expect(find.text('Payment reference: EFT-2026-001'), findsOneWidget);
      expect(find.text('Commission (10.00%, backfilled rate)'), findsOneWidget);
    });

    testWidgets('a refund recorded after the payout is flagged on it', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([
          _payoutJson(2, 'approved')
            ..['refund'] = {'status': 'approved', 'amount': 300.0}
            ..['flagged'] = true,
          _payoutJson(3, 'paid')
            ..['refund'] = {'status': 'approved', 'amount': 300.0}
            ..['flagged'] = true,
          _payoutJson(4, 'pending')
            ..['refund'] = {'status': 'pending', 'amount': 0.0}
            ..['flagged'] = true,
        ]),
      ]);
      await _pump(tester, service);
      expect(
        find.textContaining('Refund of R 300.00 approved after this payout'),
        findsNWidgets(2),
      );
      expect(
        find.textContaining(
          'cannot be approved or paid until the refund is resolved',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('recover the amount'), findsOneWidget);
      expect(
        find.textContaining('A refund is awaiting a decision'),
        findsOneWidget,
      );

      // An unresolved refund blocks approval and payment, as the backend
      // does: both buttons are shown but disabled.
      FilledButton button(String label) =>
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
      expect(button('Mark as paid').onPressed, isNull);
      expect(button('Approve payout').onPressed, isNull);
      await tester.tap(find.text('Mark as paid'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.actions, isEmpty);
    });

    testWidgets('a rejected refund does not block payment', (tester) async {
      final service = _FakePayoutsService([
        // The backend sends no refund for a rejected one.
        () async => _page([_payoutJson(2, 'approved')]),
      ]);
      await _pump(tester, service);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Mark as paid'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows the four figures and where the money is', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([_payoutJson(1, 'pending')], finance: _financeJson()),
      ]);
      await _pump(tester, service);

      expect(find.text('Money received'), findsOneWidget);
      expect(find.text('R 1,445.00'), findsNWidgets(3)); // card, total, sum
      expect(find.text('Platform commission'), findsNWidgets(2));
      expect(find.text('R 37.50'), findsNWidgets(2));
      expect(find.text('Owed to tutors'), findsNWidgets(2));
      expect(find.text('1 pending approval · 0 approved'), findsOneWidget);
      expect(find.text('Paid to tutors'), findsNWidgets(2));
      expect(find.text('Refunded to students'), findsOneWidget);
      expect(find.text('R 272.50'), findsOneWidget);
      expect(find.text('Retained from cancellations'), findsOneWidget);
      expect(find.textContaining('late cancellations'), findsNothing);
      expect(find.text('R 262.50'), findsOneWidget);
      expect(find.text('Held for upcoming lessons (1)'), findsOneWidget);
      expect(
        find.text('Finished lessons awaiting payout generation (1)'),
        findsOneWidget,
      );
      expect(
        find.text('Reconciled: every rand received is accounted for.'),
        findsOneWidget,
      );
      expect(find.textContaining('1 finished lesson is ready'), findsOneWidget);
      // The old per-status cards are replaced by the overview.
      expect(find.text('Pending approval'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a discrepancy is shown with its warnings, not hidden', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page(
          [],
          finance: _financeJson(
            difference: '-200.00',
            reconciled: false,
            issues: [
              {
                'code': 'refund_after_payout',
                'severity': 'warning',
                'count': 1,
                'amount': '200.00',
                'message': 'A refund was approved for a lesson that already '
                    'has a payout.',
              },
              {
                'code': 'backfilled_commission_rate',
                'severity': 'info',
                'count': 3,
                'amount': null,
                'message': 'Lessons use a backfilled rate.',
              },
            ],
          ),
        ),
      ]);
      await _pump(tester, service);
      expect(find.text('R -200.00'), findsOneWidget);
      expect(
        find.textContaining('Not reconciled: R -200.00 is not explained'),
        findsOneWidget,
      );
      expect(
        find.text(
          'A refund was approved for a lesson that already has a payout. · '
          '1 record · R 200.00',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Lessons use a backfilled rate. · 3 records'),
        findsOneWidget,
      );
    });

    testWidgets('Generate eligible payouts runs and refreshes the page', (
      tester,
    ) async {
      final service = _FakePayoutsService([
        () async => _page([], finance: _financeJson()),
      ]);
      await _pump(tester, service);

      await tester.tap(find.text('Generate eligible payouts'));
      await tester.pumpAndSettle();
      expect(service.actions, [('generate', 0)]);
      expect(find.text('2 payouts generated.'), findsOneWidget);
      expect(service.fetches, hasLength(2));
    });

    testWidgets('a refused generation shows why and still refreshes', (
      tester,
    ) async {
      final service = _FakePayoutsService(
        [() async => _page([])],
        actionError: Exception('Payouts are already being generated.'),
      );
      await _pump(tester, service);
      await tester.tap(find.text('Generate eligible payouts'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not generate payouts: Payouts are already being generated.',
        ),
        findsOneWidget,
      );
      expect(service.fetches, hasLength(2));
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
      expect(find.text('Generate eligible payouts'), findsNothing);
    });
  });

  group('PayoutFinance', () {
    test('amounts are parsed into exact cents', () {
      expect(parseCents('1445.00'), 144500);
      expect(parseCents('0.05'), 5);
      expect(parseCents('-200.00'), -20000);
      expect(parseCents('12.5'), 1250);
      expect(parseCents(12.5), isNull); // only exact text is accepted
      expect(parseCents('abc'), isNull);
      final f = PayoutFinance.fromJson(_financeJson());
      expect(f.moneyReceived, 144500);
      expect(f.platformCommission, 3750);
      expect(f.owedToTutors, 15750);
      expect(f.paidToTutors, 18000);
      expect(f.retainedCancellationRevenue, 26250);
      expect(f.reconciled, isTrue);
      expect(f.eligibleLessons, 1);
      expect(
        f.refunded +
            f.retainedCancellationRevenue +
            f.awaitingRefundDecision +
            f.heldForUpcomingLessons +
            f.awaitingPayoutGeneration +
            f.platformCommission +
            f.owedToTutors +
            f.paidToTutors,
        f.moneyReceived,
      );
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
      await service.markPaid(6, reference: ' EFT-9 ');
      expect(sent.map((r) => (r.method, r.url.path)), [
        ('POST', Uri.parse('$apiBaseUrl/admin/payouts/5/approve').path),
        ('POST', Uri.parse('$apiBaseUrl/admin/payouts/5/mark-paid').path),
        ('POST', Uri.parse('$apiBaseUrl/admin/payouts/6/mark-paid').path),
      ]);
      expect(jsonDecode(sent[1].body), isEmpty);
      expect(jsonDecode(sent[2].body), {'reference': 'EFT-9'});
    });

    test('generate posts to the generate endpoint and returns the count',
        () async {
      late http.Request sent;
      final service = AdminPayoutsService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            '{"ok":true,"generated":3,"message":"3 payouts generated."}',
            200,
          );
        }),
        tokenProvider: () async => 'token',
      );
      final result = await service.generate();
      expect(sent.method, 'POST');
      expect(
        sent.url.path,
        Uri.parse('$apiBaseUrl/admin/payouts/generate').path,
      );
      expect(result.generated, 3);
      expect(result.message, '3 payouts generated.');
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
