import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_access_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_access_guard.dart';

void main() {
  test(
    'accepts the active administrator identity returned by the backend',
    () async {
      late http.Request seen;
      final service = AdminAccessService(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'adminId': 5,
              'adminName': 'Admin Tester',
              'adminRole': 'application_reviewer',
              'permissions': [
                'admin.dashboard.read',
                'admin.applications.read',
                'admin.applications.review',
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.checkToken('firebase-token');

      expect(result.status, AdminAccessStatus.allowed);
      expect(result.adminName, 'Admin Tester');
      expect(result.adminId, 5);
      expect(result.roleKey, 'application_reviewer');
      expect(result.permissions, contains('admin.applications.review'));
      expect(seen.method, 'GET');
      expect(seen.url.path, '/admin/me');
      expect(seen.headers['Authorization'], 'Bearer firebase-token');
    },
  );

  test('denies missing sessions and non-admin accounts', () async {
    for (final statusCode in [401, 403]) {
      final service = AdminAccessService(
        client: MockClient((_) async => http.Response('{}', statusCode)),
      );

      expect(
        (await service.checkToken('user-token')).status,
        AdminAccessStatus.denied,
      );
    }
  });

  testWidgets('route guard withholds Admin pages when access is denied', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccessGuard(
          accessCheck: () async => const AdminAccessResult.denied(),
          child: const Text('Protected Admin page'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Protected Admin page'), findsNothing);
    expect(
      find.text('An active administrator account is required.'),
      findsOneWidget,
    );
  });

  testWidgets('route guard displays Admin pages after access is allowed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccessGuard(
          accessCheck: () async => const AdminAccessResult.allowed('Admin'),
          child: const Text('Protected Admin page'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Protected Admin page'), findsOneWidget);
  });

  testWidgets('route guard denies Admin pages without required permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccessGuard(
          requiredPermissions: const {'admin.monitor.read'},
          accessCheck: () async => const AdminAccessResult.allowed(
            'Reviewer',
            permissions: ['admin.applications.read'],
          ),
          child: const Text('Protected Monitoring page'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Protected Monitoring page'), findsNothing);
    expect(
      find.text('Your administrator role does not have access to this page.'),
      findsOneWidget,
    );
  });
}
