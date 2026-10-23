import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_access_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_access_guard.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_shell.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_students.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_unavailable.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_users.dart';
import 'package:theo_tutoring_app/main.dart';

const _sections = {
  AdminRoutes.tutors: 'Tutors',
  AdminRoutes.subjects: 'Subjects',
  AdminRoutes.reviews: 'Reviews',
  AdminRoutes.payouts: 'Payouts',
  AdminRoutes.reports: 'Reports',
};

// Below the shell's 900px sidebar breakpoint: the sidebar is opened as a
// drawer (its fixed-width header overflows with the wide Ahem test font).
void _phoneSizedView(WidgetTester tester) {
  tester.view.physicalSize = const Size(880, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<NavigatorState> _pumpApp(WidgetTester tester) async {
  _phoneSizedView(tester);
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Text('sign-in home'),
      routes: appRoutes,
      onUnknownRoute: onUnknownAppRoute,
    ),
  );
  return navigatorKey.currentState!;
}

Text _drawerLabel(WidgetTester tester, String label) => tester.widget<Text>(
  find.descendant(of: find.byType(Drawer), matching: find.text(label)),
);

void main() {
  test('existing Admin routes are preserved', () {
    for (final route in [
      AdminRoutes.dashboard,
      AdminRoutes.refunds,
      AdminRoutes.monitor,
      AdminRoutes.settings,
      AdminRoutes.applications,
      AdminRoutes.applicationReview,
    ]) {
      expect(appRoutes, contains(route));
    }
    expect(unavailableAdminSections, _sections);
  });

  testWidgets('Students opens the guarded Student Roster page', (
    tester,
  ) async {
    final navigator = await _pumpApp(tester);
    final built = appRoutes[AdminRoutes.students]!(navigator.context);

    expect(built, isA<AdminAccessGuard>());
    expect((built as AdminAccessGuard).child, isA<AdminStudentsScreen>());
    expect(
      built.requiredPermissions,
      {'admin.students.read', 'admin.students.manage'},
    );
  });

  testWidgets('Users route requires admin.users.manage', (
    tester,
  ) async {
    final navigator = await _pumpApp(tester);
    final built = appRoutes[AdminRoutes.users]!(navigator.context);

    expect(built, isA<AdminAccessGuard>());
    expect(
      (built as AdminAccessGuard).requiredPermissions,
      {'admin.users.manage'},
    );
    expect(built.child, isA<AdminUsersScreen>());
  });

  testWidgets('sidebar keeps Students and lists Users below Applications', (
    tester,
  ) async {
    _phoneSizedView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminSectionUnavailableScreen(
          currentRoute: AdminRoutes.tutors,
          title: 'Tutors',
          loadAccess: () async => const AdminAccessResult.denied(),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    double top(String label) => tester
        .getTopLeft(find.descendant(of: drawer, matching: find.text(label)))
        .dy;
    expect(top('Students'), lessThan(top('Tutors')));
    expect(top('Tutors'), lessThan(top('Applications')));
    expect(top('Applications'), lessThan(top('Users')));
    // Nothing sits between Applications and Users.
    expect(top('Users') - top('Applications'), 40);
    expect(top('Users'), lessThan(top('Subjects')));
  });

  for (final MapEntry(key: route, value: title) in _sections.entries) {
    testWidgets('$title route is registered behind the Admin guard', (
      tester,
    ) async {
      final navigator = await _pumpApp(tester);
      final built = appRoutes[route]!(navigator.context);

      expect(built, isA<AdminAccessGuard>());
      final page = (built as AdminAccessGuard).child;
      expect(page, isA<AdminSectionUnavailableScreen>());
      expect((page as AdminSectionUnavailableScreen).currentRoute, route);
      expect(page.title, title);

      // Navigating resolves the route; without a verified admin the guard
      // withholds the page instead of throwing.
      navigator.pushNamed(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text("This section isn't available yet"), findsNothing);
      expect(find.text('This page could not be found.'), findsNothing);
      expect(find.text('Return to sign in'), findsOneWidget);
    });

    testWidgets('$title page highlights its sidebar item', (tester) async {
      _phoneSizedView(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSectionUnavailableScreen(
            currentRoute: route,
            title: title,
            loadAccess: () async => const AdminAccessResult.allowed(
              'Admin Tester',
              permissions: ['admin.dashboard.read'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("This section isn't available yet"), findsOneWidget);
      expect(find.text('Admin Tester'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      final selected = _drawerLabel(tester, title);
      expect(selected.style?.fontWeight, FontWeight.w600);
      expect(selected.style?.color, AdminColors.primary);
      for (final other in [..._sections.values, 'Dashboard']) {
        if (other == title) continue;
        expect(
          _drawerLabel(tester, other).style?.fontWeight,
          FontWeight.w400,
          reason: '$other should not be highlighted on the $title page',
        );
      }
    });
  }

  testWidgets('sidebar links to every new section navigate without errors', (
    tester,
  ) async {
    _phoneSizedView(tester);
    await tester.pumpWidget(
      MaterialApp(
        routes: appRoutes,
        onUnknownRoute: onUnknownAppRoute,
        home: AdminSectionUnavailableScreen(
          currentRoute: AdminRoutes.tutors,
          title: 'Tutors',
          loadAccess: () async => const AdminAccessResult.denied(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payouts'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('This page could not be found.'), findsNothing);
    // The Payouts route opened its guard (denied here, with no signed-in admin).
    expect(find.byType(AdminAccessGuard), findsOneWidget);
  });

  for (final unknown in ['/does-not-exist', '/admin/does-not-exist']) {
    testWidgets('unknown route $unknown is handled safely', (tester) async {
      final navigator = await _pumpApp(tester);

      navigator.pushNamed(unknown);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('This page could not be found.'), findsOneWidget);
      expect(find.byType(AdminShell), findsNothing);

      await tester.tap(find.text('Return to sign in'));
      await tester.pumpAndSettle();
      expect(find.text('sign-in home'), findsOneWidget);
    });
  }
}
