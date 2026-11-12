import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_access_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_access_guard.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_dashboard.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_shell.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/monitor_models.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/refund_models.dart';

const _fullAdminPermissions = [
  'admin.applications.read',
  'admin.applications.review',
  'admin.dashboard.read',
  'admin.monitor.read',
  'admin.refunds.read',
  'admin.reports.read',
];

AdminAccessResult _access(List<String> permissions) =>
    AdminAccessResult.allowed(
      'Admin Tester',
      adminId: 1,
      roleKey: 'admin',
      permissions: permissions,
    );

final _snapshot = MonitorSnapshot.fromJson({
  'adminName': 'Admin Tester',
  'operationalMetrics': {
    'activeUsers': 1234,
    'activeTutors': 56,
    'pendingApplications': 7,
  },
});

final _refunds = RefundCasesResult.fromJson({
  'adminName': 'Admin Tester',
  'summary': {'pendingRefunds': 3, 'pendingRefundAmount': 450.5},
  'cases': <Object>[],
});

final _activity = AuditLogPage.fromJson({
  'entries': [
    {
      'id': '1',
      'actorName': 'Admin Tester',
      'actorType': 'admin',
      'category': 'config',
      'action': 'Session rate updated',
      'detail': 'R300.00 to R320.00',
      'createdAt': DateTime.now().toIso8601String(),
    },
  ],
});

Future<void> _pump(
  WidgetTester tester, {
  required AdminAccessResult access,
  Future<MonitorSnapshot> Function()? loadMonitor,
  Future<AuditLogPage> Function()? loadActivity,
  Future<RefundCasesResult> Function()? loadRefunds,
  // Below the shell's 900px sidebar breakpoint: the fixed 240px sidebar header
  // overflows with the wide Ahem test font, which real fonts do not.
  Size size = const Size(880, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AdminPermissionScope(
        access: access,
        child: AdminDashboardScreen(
          loadAccess: () async => access,
          loadMonitor: loadMonitor ?? () async => _snapshot,
          loadActivity: loadActivity ?? () async => _activity,
          loadRefunds: loadRefunds ?? () async => _refunds,
        ),
      ),
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => Scaffold(body: Text('route:${settings.name}')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows live figures and activity inside the shared Admin shell', (
    tester,
  ) async {
    await _pump(tester, access: _access(_fullAdminPermissions));

    // Shared shell: the signed-in admin in the top bar.
    expect(find.byType(AdminShell), findsOneWidget);
    expect(find.text('Admin Tester'), findsOneWidget);

    expect(find.text('System Overview'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('R 450.50 awaiting a decision'), findsOneWidget);

    expect(find.text('7 pending applications'), findsOneWidget);
    expect(find.text('3 pending refunds'), findsOneWidget);

    expect(find.text('Recent Activity'), findsOneWidget);
    expect(find.text('Session rate updated'), findsOneWidget);
    expect(find.text('CONFIG'), findsOneWidget);

    // Shared sidebar, opened from the top bar's menu button.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Theo Admin'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('only loads sections the admin role is permitted to see', (
    tester,
  ) async {
    var monitorCalls = 0;
    var refundCalls = 0;
    await _pump(
      tester,
      access: _access(const [
        'admin.dashboard.read',
        'admin.applications.read',
        'admin.applications.review',
      ]),
      loadMonitor: () async {
        monitorCalls++;
        return _snapshot;
      },
      loadRefunds: () async {
        refundCalls++;
        return _refunds;
      },
    );

    expect(monitorCalls, 0);
    expect(refundCalls, 0);
    expect(find.text('ACTIVE USERS'), findsNothing);
    expect(find.text('Recent Activity'), findsNothing);
    expect(find.text('Review Applications'), findsOneWidget);
    expect(find.text('Approve or reject tutor applications'), findsOneWidget);
    expect(find.text('Decide refunds and resolve reports'), findsNothing);
    expect(find.text('Session rate and account settings'), findsOneWidget);
  });

  testWidgets('shows empty and error states instead of sample data', (
    tester,
  ) async {
    await _pump(
      tester,
      access: _access(_fullAdminPermissions),
      loadMonitor: () async => throw Exception('Monitor offline'),
      loadActivity: () async => AuditLogPage.fromJson(const {'entries': []}),
    );

    expect(find.text('No recent activity.'), findsOneWidget);
    expect(find.text('Some figures could not be loaded.'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('quick actions open the existing Admin pages', (tester) async {
    await _pump(tester, access: _access(_fullAdminPermissions));

    await tester.tap(find.text('Review Applications'));
    await tester.pumpAndSettle();

    expect(find.text('route:${AdminRoutes.applications}'), findsOneWidget);
  });

  testWidgets('reuses the scope access without a second access request', (
    tester,
  ) async {
    var accessCalls = 0;
    var monitorCalls = 0;
    tester.view.physicalSize = const Size(880, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminPermissionScope(
          access: _access(_fullAdminPermissions),
          child: AdminDashboardScreen(
            loadAccess: () async {
              accessCalls++;
              return _access(const []);
            },
            loadMonitor: () async {
              monitorCalls++;
              return _snapshot;
            },
            loadActivity: () async => _activity,
            loadRefunds: () async => _refunds,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(accessCalls, 0);
    expect(monitorCalls, 1);
    expect(find.text('Admin Tester'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
  });

  testWidgets('without a scope or loader it fails closed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminDashboardScreen()));
    await tester.pumpAndSettle();

    expect(
      find.text('Administrator access could not be verified.'),
      findsOneWidget,
    );
    expect(find.text('Quick Actions'), findsNothing);
    expect(find.text('ACTIVE USERS'), findsNothing);
  });

  testWidgets('removing the scope fails closed and drops stale access', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(880, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hasScope = ValueNotifier(true);
    var accessCalls = 0;
    final dashboardKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: hasScope,
          builder: (_, value, _) {
            final dashboard = AdminDashboardScreen(
              key: dashboardKey,
              loadAccess: () async {
                accessCalls++;
                return _access(_fullAdminPermissions);
              },
              loadMonitor: () async => _snapshot,
              loadActivity: () async => _activity,
              loadRefunds: () async => _refunds,
            );
            return value
                ? AdminPermissionScope(
                    access: _access(_fullAdminPermissions),
                    child: dashboard,
                  )
                : dashboard;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quick Actions'), findsOneWidget);

    hasScope.value = false;
    await tester.pumpAndSettle();

    expect(accessCalls, 0);
    expect(
      find.text('Administrator access could not be verified.'),
      findsOneWidget,
    );
    expect(find.text('Quick Actions'), findsNothing);
    expect(find.text('ACTIVE USERS'), findsNothing);
  });

  testWidgets('an older monitor response cannot overwrite a newer one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(880, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final access = ValueNotifier(_access(_fullAdminPermissions));
    final older = Completer<MonitorSnapshot>();
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<AdminAccessResult>(
          valueListenable: access,
          builder: (_, value, _) => AdminPermissionScope(
            access: value,
            child: AdminDashboardScreen(
              loadMonitor: () => ++calls == 1
                  ? older.future
                  : Future.value(
                      MonitorSnapshot.fromJson({
                        'adminName': 'Admin Tester',
                        'operationalMetrics': {
                          'activeUsers': 4321,
                          'activeTutors': 1,
                          'pendingApplications': 1,
                        },
                      }),
                    ),
              loadActivity: () async => _activity,
              loadRefunds: () async => _refunds,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    access.value = _access(_fullAdminPermissions);
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.text('4,321'), findsOneWidget);

    older.complete(_snapshot);
    await tester.pumpAndSettle();

    expect(find.text('4,321'), findsOneWidget);
    expect(find.text('1,234'), findsNothing);
  });

  testWidgets('revoking monitor access discards a pending response', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(880, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final access = ValueNotifier(_access(_fullAdminPermissions));
    final pending = Completer<MonitorSnapshot>();

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<AdminAccessResult>(
          valueListenable: access,
          builder: (_, value, _) => AdminPermissionScope(
            access: value,
            child: AdminDashboardScreen(
              loadMonitor: () => pending.future,
              loadActivity: () async => _activity,
              loadRefunds: () async => _refunds,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    access.value = _access(const [
      'admin.dashboard.read',
      'admin.refunds.read',
      'admin.reports.read',
    ]);
    await tester.pump();
    pending.complete(_snapshot);
    await tester.pumpAndSettle();

    expect(find.text('1,234'), findsNothing);
    expect(find.text('ACTIVE USERS'), findsNothing);
    expect(find.text('Recent Activity'), findsNothing);
    expect(find.text('3 pending refunds'), findsOneWidget);
  });

  testWidgets('lays out without overflow on a phone-sized screen', (
    tester,
  ) async {
    await _pump(
      tester,
      access: _access(_fullAdminPermissions),
      size: const Size(390, 844),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('System Overview'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
  });
}
