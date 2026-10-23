import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/settings_services.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_settings.dart';

class _FakeSettingsService extends AdminSettingsService {
  @override
  Future<Map<String, dynamic>> fetchSessionRate() async => {
    'adminName': 'Admin',
    'current': {
      'id': 1,
      'amount': '350.00',
      'effectiveFrom': '2026-10-22 10:00:00',
      'setBy': 'Admin',
    },
    'history': [],
  };

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
        home: AdminSettingsScreen(service: _FakeSettingsService()),
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
}
