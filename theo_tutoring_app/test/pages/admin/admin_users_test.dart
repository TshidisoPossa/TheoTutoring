import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_users_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_users.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/admin_user_models.dart';

const _roles = [
  'super_admin',
  'admin',
  'application_reviewer',
  'finance_admin',
  'support_admin',
  'monitor_admin',
];

// Copied from the backend's adminRolePermissions (lib/admin_refunds.dart).
const _rolePermissions = {
  'super_admin': [
    'admin.applications.read',
    'admin.applications.review',
    'admin.dashboard.read',
    'admin.finance.read',
    'admin.monitor.read',
    'admin.payouts.manage',
    'admin.refunds.decide',
    'admin.refunds.read',
    'admin.reports.read',
    'admin.reports.resolve',
    'admin.roles.manage',
    'admin.settings.rate.read',
    'admin.settings.rate.write',
    'admin.users.manage',
  ],
  'admin': [
    'admin.applications.read',
    'admin.applications.review',
    'admin.dashboard.read',
    'admin.finance.read',
    'admin.monitor.read',
    'admin.payouts.manage',
    'admin.refunds.decide',
    'admin.refunds.read',
    'admin.reports.read',
    'admin.reports.resolve',
    'admin.settings.rate.read',
    'admin.settings.rate.write',
  ],
  'application_reviewer': [
    'admin.applications.read',
    'admin.applications.review',
    'admin.dashboard.read',
  ],
  'finance_admin': [
    'admin.dashboard.read',
    'admin.finance.read',
    'admin.payouts.manage',
    'admin.refunds.decide',
    'admin.refunds.read',
    'admin.reports.read',
    'admin.settings.rate.read',
    'admin.settings.rate.write',
  ],
  'support_admin': [
    'admin.dashboard.read',
    'admin.refunds.read',
    'admin.reports.read',
    'admin.reports.resolve',
  ],
  'monitor_admin': ['admin.dashboard.read', 'admin.monitor.read'],
};

Map<String, dynamic> _admin(int id, String name, String email, String role) =>
    {
      'adminId': id,
      'name': name,
      'email': email,
      'role': role,
      'accountStatus': 'Active',
      'createdAt': '2026-10-20 10:00:00',
    };

/// Simulates GET/POST /admin/users with an in-memory admin list.
class _Backend {
  final admins = [_admin(1, 'Admin Tester', 'admin@example.com', 'super_admin')];
  final posts = <Map<String, dynamic>>[];
  http.Response? nextPostResponse;
  bool failGet = false;

  late final client = MockClient((request) async {
    expect(request.url.path, '/admin/users');
    expect(request.headers['Authorization'], 'Bearer admin-token');
    if (request.method == 'GET') {
      if (failGet) {
        return http.Response(jsonEncode({'error': 'Database offline'}), 500);
      }
      return http.Response(
        jsonEncode({
          'adminName': 'Admin Tester',
          'roles': _roles,
          'rolePermissions': _rolePermissions,
          'admins': admins,
        }),
        200,
      );
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    posts.add(body);
    final override = nextPostResponse;
    if (override != null) return override;
    final created = _admin(
      admins.length + 1,
      body['name'] as String,
      body['email'] as String,
      body['role'] as String,
    );
    admins.add(created);
    return http.Response(jsonEncode(created), 201);
  });

  AdminUsersService service() => AdminUsersService(
    client: client,
    tokenProvider: () async => 'admin-token',
  );
}

Future<void> _pump(WidgetTester tester, _Backend backend) async {
  // Below the shell's 900px sidebar breakpoint (its fixed-width header
  // overflows with the wide Ahem test font, which real fonts do not).
  tester.view.physicalSize = const Size(880, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AdminUsersScreen(service: backend.service())),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillForm(
  WidgetTester tester, {
  String name = 'New Admin',
  String email = 'new.admin@example.com',
  String password = 'initial-pass-123',
}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), name);
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Initial password'),
    password,
  );
}

void main() {
  test('role labels come from the backend role keys', () {
    expect(adminRoleLabel('super_admin'), 'Super Admin');
    expect(adminRoleLabel('application_reviewer'), 'Application Reviewer');
  });

  test('role notes are built only from the backend permissions', () {
    expect(
      adminRoleAccessNote('monitor_admin', _rolePermissions),
      'Can view the dashboard, monitor the platform.',
    );
    expect(
      adminRoleAccessNote('application_reviewer', _rolePermissions),
      'Can view the dashboard, view tutor applications, '
      'approve or reject applications.',
    );
    expect(
      adminRoleAccessNote('super_admin', _rolePermissions),
      startsWith('Full access to every Admin area'),
    );
    // The standard admin role lacks account and role management.
    final admin = adminRoleAccessNote('admin', _rolePermissions)!;
    expect(admin, isNot(contains('administrator accounts')));
    expect(admin, isNot(contains('administrator roles')));
    // No note when the backend did not describe the role.
    expect(adminRoleAccessNote('admin', const {}), isNull);
  });

  testWidgets('the role note follows the selected role', (tester) async {
    await _pump(tester, _Backend());
    await tester.tap(find.text('Add Administrator'));
    await tester.pumpAndSettle();

    String note() =>
        tester.widget<Text>(find.byKey(const Key('role-access-note'))).data!;

    // Default role: the standard admin.
    expect(note(), contains('approve or reject applications'));
    expect(note(), isNot(contains('administrator accounts')));

    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support Admin').last);
    await tester.pumpAndSettle();
    expect(
      note(),
      'Can view the dashboard, view refunds, view user reports, '
      'resolve user reports.',
    );

    await tester.tap(find.text('Support Admin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Super Admin').last);
    await tester.pumpAndSettle();
    expect(note(), startsWith('Full access to every Admin area'));
  });

  test('service refuses to call the API without a Firebase token', () async {
    var calls = 0;
    final service = AdminUsersService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
      tokenProvider: () async => null,
    );
    await expectLater(service.fetchAdmins(), throwsException);
    expect(calls, 0);
  });

  testWidgets('lists admin accounts with their roles', (tester) async {
    await _pump(tester, _Backend());

    expect(find.text('Users'), findsWidgets);
    expect(find.text('Admin Tester'), findsWidgets);
    expect(find.text('admin@example.com'), findsOneWidget);
    expect(find.text('Super Admin'), findsOneWidget);
    expect(find.text('1 administrator'), findsOneWidget);
  });

  testWidgets('creates an admin with email, initial password and role', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(find.text('Add Administrator'));
    await tester.pumpAndSettle();
    await _fillForm(tester);
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finance Admin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create administrator'));
    await tester.pumpAndSettle();

    expect(backend.posts.single, {
      'name': 'New Admin',
      'email': 'new.admin@example.com',
      'password': 'initial-pass-123',
      'role': 'finance_admin',
    });
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('new.admin@example.com'), findsOneWidget);
    expect(find.text('Finance Admin'), findsOneWidget);
    expect(find.text('2 administrators'), findsOneWidget);
    expect(find.textContaining('was added as Finance Admin'), findsOneWidget);
  });

  testWidgets('validates the form before sending anything', (tester) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(find.text('Add Administrator'));
    await tester.pumpAndSettle();
    await _fillForm(tester, email: 'not-an-email', password: 'short');
    await tester.tap(find.text('Create administrator'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Use 8 to 128 characters.'), findsOneWidget);
    expect(backend.posts, isEmpty);
  });

  testWidgets('shows backend errors inside the dialog', (tester) async {
    final backend = _Backend()
      ..nextPostResponse = http.Response(
        jsonEncode({'error': 'An account with this email already exists.'}),
        409,
      );
    await _pump(tester, backend);

    await tester.tap(find.text('Add Administrator'));
    await tester.pumpAndSettle();
    await _fillForm(tester, email: 'admin@example.com');
    await tester.tap(find.text('Create administrator'));
    await tester.pumpAndSettle();

    expect(
      find.text('An account with this email already exists.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('1 administrator'), findsOneWidget);
  });

  testWidgets('shows a retryable error when the list cannot load', (
    tester,
  ) async {
    final backend = _Backend()..failGet = true;
    await _pump(tester, backend);

    expect(find.text('Could not load administrators.'), findsOneWidget);
    expect(find.text('Database offline'), findsOneWidget);

    backend.failGet = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('admin@example.com'), findsOneWidget);
  });
}
