import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_access_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/settings_services.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_access_guard.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_settings.dart';

AdminAccessResult _access(List<String> permissions) =>
    AdminAccessResult.allowed('Admin', permissions: permissions);

class _FakeSettingsService extends AdminSettingsService {
  int fetches = 0;
  final List<Completer<Map<String, dynamic>>> pending = [];
  bool controlled = false;

  static Map<String, dynamic> rate(String amount) => {
    'adminName': 'Admin',
    'current': {
      'id': 1,
      'amount': amount,
      'effectiveFrom': '2026-10-22 10:00:00',
      'setBy': 'Admin',
    },
    'history': [],
  };

  @override
  Future<Map<String, dynamic>> fetchSessionRate() async {
    fetches++;
    if (controlled) {
      final completer = Completer<Map<String, dynamic>>();
      pending.add(completer);
      return completer.future;
    }
    return rate('350.00');
  }

  @override
  Future<Map<String, dynamic>> updateSessionRate(String amount) async => {
    'adminName': 'Admin',
    'current': {
      'id': 1,
      'amount': amount,
      'effectiveFrom': '2026-10-22 10:00:00',
      'setBy': 'Admin',
    },
    'history': [],
  };
}

void main() {
  testWidgets('Settings loads the current rate and submits an update', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.8)),
          child: child!,
        ),
        home: AdminPermissionScope(
          access: _access(const [
            'admin.settings.rate.read',
            'admin.settings.rate.write',
          ]),
          child: AdminSettingsScreen(service: _FakeSettingsService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Current rate: R 350.00'), findsOneWidget);
    final rateField = find.ancestor(
      of: find.text('New session rate (R)'),
      matching: find.byType(TextField),
    );
    await tester.enterText(rateField, '375.50');
    await tester.tap(find.text('Update session rate'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Current rate: R 375.50'), findsOneWidget);
    expect(find.text('Session rate updated.'), findsOneWidget);
  });

  group('session rate permissions', () {
    Future<_FakeSettingsService> pump(
      WidgetTester tester,
      List<String>? permissions,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _FakeSettingsService();
      final screen = AdminSettingsScreen(service: service);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(0.8)),
            child: child!,
          ),
          home: permissions == null
              ? screen
              : AdminPermissionScope(
                  access: _access(permissions),
                  child: screen,
                ),
        ),
      );
      await tester.pumpAndSettle();
      return service;
    }

    void expectRestricted(WidgetTester tester, _FakeSettingsService service) {
      expect(service.fetches, 0);
      expect(find.textContaining('Access restricted'), findsOneWidget);
      expect(find.textContaining('Current rate'), findsNothing);
      expect(find.text('New session rate (R)'), findsNothing);
      expect(find.text('Update session rate'), findsNothing);
    }

    testWidgets('no scope is denied without a request', (tester) async {
      expectRestricted(tester, await pump(tester, null));
    });

    testWidgets('missing read permission is denied without a request', (
      tester,
    ) async {
      expectRestricted(
        tester,
        await pump(tester, const ['admin.settings.rate.write']),
      );
    });

    testWidgets('read-only access shows the rate without editing controls', (
      tester,
    ) async {
      final service = await pump(tester, const ['admin.settings.rate.read']);

      expect(service.fetches, 1);
      expect(find.textContaining('Current rate: R 350.00'), findsOneWidget);
      expect(find.text('New session rate (R)'), findsNothing);
      expect(find.text('Update session rate'), findsNothing);
    });

    group('stale fetches', () {
      const read = ['admin.settings.rate.read'];
      late ValueNotifier<List<String>> permissions;
      late _FakeSettingsService service;

      Future<void> pumpPending(WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        permissions = ValueNotifier(read);
        service = _FakeSettingsService()..controlled = true;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(0.8)),
              child: child!,
            ),
            home: ValueListenableBuilder<List<String>>(
              valueListenable: permissions,
              builder: (_, value, _) => AdminPermissionScope(
                access: _access(value),
                child: AdminSettingsScreen(service: service),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      testWidgets('response after read revocation is ignored', (tester) async {
        await pumpPending(tester);
        expect(service.pending, hasLength(1));

        permissions.value = const [];
        await tester.pump();
        service.pending[0].complete(_FakeSettingsService.rate('350.00'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Access restricted'), findsOneWidget);
        expect(find.textContaining('Current rate'), findsNothing);
      });

      testWidgets('older fetch does not overwrite a newer one', (tester) async {
        await pumpPending(tester);

        permissions.value = const [];
        await tester.pump();
        permissions.value = read;
        await tester.pump();
        expect(service.pending, hasLength(2));

        service.pending[1].complete(_FakeSettingsService.rate('400.00'));
        await tester.pumpAndSettle();
        service.pending[0].complete(_FakeSettingsService.rate('350.00'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Current rate: R 400.00'), findsOneWidget);
      });
    });
  });
}
