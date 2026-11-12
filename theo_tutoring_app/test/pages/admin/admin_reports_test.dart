import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_reports_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_reports.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/admin_report_models.dart';

Map<String, dynamic> _report(
  int id, {
  String? category = 'Payments & Payouts',
  String status = 'Open',
  Object? reportedUser = const {
    'userId': 9,
    'name': 'Jafta Ndlovu',
    'email': 'jafta@example.com',
    'role': 'student',
  },
}) => {
  'reportId': id,
  'category': category,
  'description': 'Report description $id',
  'status': status,
  'bookingId': 40 + id,
  'createdAt': '2026-10-20T16:08:19',
  'reporter': {
    'userId': 1,
    'name': 'Thabo Mokoena',
    'email': 'thabo@example.com',
    'role': 'tutor',
  },
  'reportedUser': reportedUser,
};

class _Backend {
  final requests = <http.Request>[];
  int total = 2;
  int? failWith;
  List<Map<String, dynamic>> reports = [
    _report(1),
    _report(2, category: null, reportedUser: null, status: 'Resolved'),
  ];

  late final client = MockClient((request) async {
    requests.add(request);
    expect(request.headers['Authorization'], 'Bearer admin-token');
    if (failWith != null) {
      return http.Response(jsonEncode({'error': 'Nope'}), failWith!);
    }
    final q = request.url.queryParameters;
    return http.Response(
      jsonEncode({
        'adminName': 'Dineo Admin',
        'total': total,
        'page': int.parse(q['page']!),
        'pageSize': int.parse(q['pageSize']!),
        'reports': reports,
      }),
      200,
    );
  });

  AdminReportsService service() => AdminReportsService(
    client: client,
    tokenProvider: () async => 'admin-token',
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Backend backend, {
  int pageSize = 20,
}) async {
  tester.view.physicalSize = const Size(880, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminReportsScreen(service: backend.service(), pageSize: pageSize),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('models', () {
    test('parse null category, null reportedUser and bad persons', () {
      final page = AdminReportsPage.fromJson({
        'total': 45,
        'reports': [
          _report(1, category: null, reportedUser: null),
          {..._report(2), 'reporter': 'oops'},
        ],
      });
      expect(page.page, 1);
      expect(page.pageSize, 20);
      expect(page.pageCount, 3);
      expect(page.reports.first.category, isNull);
      expect(page.reports.first.reportedUser, isNull);
      expect(page.reports.first.reporter?.name, 'Thabo Mokoena');
      expect(page.reports.last.reporter, isNull);
    });
  });

  group('service', () {
    test(
      'sends filters, page and bearer token; omits empty category',
      () async {
        final backend = _Backend();
        await backend.service().fetchReports(
          status: 'under-review',
          page: 2,
          pageSize: 10,
        );
        final url = backend.requests.single.url;
        expect(url.path, '/admin/reports');
        expect(url.queryParameters, {
          'status': 'under-review',
          'page': '2',
          'pageSize': '10',
        });
      },
    );

    test('surfaces the backend error message', () async {
      final backend = _Backend()..failWith = 403;
      expect(
        backend.service().fetchReports(),
        throwsA(predicate((e) => e.toString().contains('Nope'))),
      );
    });

    test('fails without a token and makes no request', () async {
      final backend = _Backend();
      final service = AdminReportsService(
        client: backend.client,
        tokenProvider: () async => null,
      );
      await expectLater(service.fetchReports(), throwsException);
      expect(backend.requests, isEmpty);
    });
  });

  group('screen', () {
    testWidgets('shows reports with nullable fields handled', (tester) async {
      final backend = _Backend();
      await _pump(tester, backend);

      expect(find.text('Report description 1'), findsOneWidget);
      expect(find.text('Payments & Payouts'), findsWidgets);
      expect(find.text('Booking #41'), findsOneWidget);
      expect(find.text('Thabo Mokoena'), findsNWidgets(2));
      expect(find.text('Jafta Ndlovu'), findsOneWidget);
      expect(find.text('Uncategorised'), findsOneWidget);
      expect(find.text('No user named'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('status filter requests the status and resets to page 1', (
      tester,
    ) async {
      final backend = _Backend()..total = 5;
      await _pump(tester, backend, pageSize: 2);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(backend.requests.last.url.queryParameters['page'], '2');

      await tester.tap(find.text('Under review'));
      await tester.pumpAndSettle();
      final q = backend.requests.last.url.queryParameters;
      expect(q['status'], 'under-review');
      expect(q['page'], '1');
    });

    testWidgets('category filter sends the category', (tester) async {
      final backend = _Backend();
      await _pump(tester, backend);
      await tester.tap(find.text('All categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student issues').last);
      await tester.pumpAndSettle();
      expect(
        backend.requests.last.url.queryParameters['category'],
        'Student issues',
      );
    });

    testWidgets('pagination uses total, page and pageSize', (tester) async {
      final backend = _Backend()..total = 5;
      await _pump(tester, backend, pageSize: 2);
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Showing 1-2 of 5'), findsOneWidget);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(backend.requests.last.url.queryParameters['page'], '1');
    });

    testWidgets('authentication failure shows error and Retry recovers', (
      tester,
    ) async {
      final backend = _Backend()..failWith = 401;
      await _pump(tester, backend);
      expect(find.text('Could not load reports.'), findsOneWidget);
      expect(find.text('Nope'), findsOneWidget);

      backend.failWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Report description 1'), findsOneWidget);
    });

    testWidgets('empty state and refresh', (tester) async {
      final backend = _Backend()
        ..reports = []
        ..total = 0;
      await _pump(tester, backend);
      expect(find.text('No reports yet'), findsOneWidget);

      backend
        ..reports = [_report(7)]
        ..total = 1;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Report description 7'), findsOneWidget);
    });
  });
}
