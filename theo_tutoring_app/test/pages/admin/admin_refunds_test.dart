import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/refund_services.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_refunds.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/refund_models.dart';

RefundCasesResult _empty() => RefundCasesResult.fromJson(const {
  'adminName': 'Admin Tester',
  'summary': {
    'openDisputes': 0,
    'pendingRefunds': 0,
    'pendingRefundAmount': 0,
    'resolvedLast7Days': 0,
    'needsAction': 0,
  },
  'cases': <Object>[],
});

/// Answers fetchCases from a queue so each test controls every load.
class _FakeRefundsService extends AdminRefundsService {
  _FakeRefundsService(this.responses);

  final List<Future<RefundCasesResult> Function()> responses;
  final calls = <(CaseType?, String)>[];

  @override
  Future<RefundCasesResult> fetchCases({
    CaseType? type,
    String status = 'all',
  }) {
    calls.add((type, status));
    final next = responses.length > 1 ? responses.removeAt(0) : responses.first;
    return next();
  }
}

Future<void> _pump(WidgetTester tester, _FakeRefundsService service) async {
  // Below the shell's 900px sidebar breakpoint (its fixed-width header
  // overflows with the wide Ahem test font, which real fonts do not).
  tester.view.physicalSize = const Size(880, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: AdminRefundsIssuesScreen(service: service)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a clear empty state when there are no cases at all', (
    tester,
  ) async {
    final service = _FakeRefundsService([() async => _empty()]);
    await _pump(tester, service);

    expect(find.text('No refund cases or reports yet'), findsOneWidget);
    expect(find.text('0 cases'), findsOneWidget);
    expect(find.text('R 0.00 awaiting a decision'), findsOneWidget);
    expect(find.text('Could not load refunds and issues.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the backend error with a working retry', (tester) async {
    const backendMessage =
        'Refunds & Issues is not set up on this server yet: required '
        'database tables are missing. Apply the pending database '
        'migrations, then try again.';
    final service = _FakeRefundsService([
      () async => throw Exception(backendMessage),
      () async => _empty(),
    ]);
    await _pump(tester, service);

    expect(find.text('Refunds & Issues'), findsWidgets);
    expect(find.text('Could not load refunds and issues.'), findsOneWidget);
    expect(find.text(backendMessage), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(service.calls, hasLength(2));
    expect(find.text('Could not load refunds and issues.'), findsNothing);
    expect(find.text('No refund cases or reports yet'), findsOneWidget);
  });

  testWidgets('distinguishes filtered results and can clear the filters', (
    tester,
  ) async {
    final service = _FakeRefundsService([() async => _empty()]);
    await _pump(tester, service);

    await tester.tap(find.text('Cancellations'));
    await tester.pumpAndSettle();

    expect(service.calls.last, (CaseType.cancellation, 'all'));
    expect(find.text('No cases match these filters'), findsOneWidget);
    expect(find.text('No refund cases or reports yet'), findsNothing);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(service.calls.last, (null, 'all'));
    expect(find.text('No refund cases or reports yet'), findsOneWidget);
  });

  testWidgets('reports a failed refresh instead of silently keeping old data', (
    tester,
  ) async {
    final service = _FakeRefundsService([
      () async => _empty(),
      () async => throw Exception('Request failed (500)'),
    ]);
    await _pump(tester, service);

    await tester.tap(find.text('User Reports'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not refresh cases: Request failed (500)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });
}
