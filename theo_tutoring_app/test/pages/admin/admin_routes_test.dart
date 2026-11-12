import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_access_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_access_guard.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_reports.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_reviews.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_shell.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_students.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_subjects.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_tutors.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_unavailable.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_users.dart';
import 'package:theo_tutoring_app/main.dart';

const _sections = {AdminRoutes.payouts: 'Payouts'};

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

Text _drawerLabel(WidgetTester tester, String label) =>
    tester.widget<Text>(_drawerItem(label));

Finder _drawerItem(String label) =>
    find.descendant(of: find.byType(Drawer), matching: find.text(label));

const _allPermissions = {
  'admin.dashboard.read',
  'admin.students.read',
  'admin.students.manage',
  'admin.tutors.read',
  'admin.tutors.manage',
  'admin.applications.read',
  'admin.users.manage',
  'admin.reviews.read',
  'admin.refunds.read',
  'admin.reports.read',
  'admin.monitor.read',
};

Widget _withPermissions(Set<String> permissions, Widget child) =>
    AdminPermissionScope(
      access: AdminAccessResult.allowed(
        'Admin Tester',
        permissions: permissions.toList(),
      ),
      child: child,
    );

// Opens the sidebar drawer of a shell page; null permissions = no scope.
Future<void> _openDrawer(
  WidgetTester tester,
  Set<String>? permissions, [
  String route = AdminRoutes.dashboard,
]) async {
  _phoneSizedView(tester);
  final page = MaterialApp(
    home: AdminShell(currentRoute: route, child: const SizedBox()),
  );
  await tester.pumpWidget(
    permissions == null ? page : _withPermissions(permissions, page),
  );
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

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

  testWidgets('Students opens the guarded Student Roster page', (tester) async {
    final navigator = await _pumpApp(tester);
    final built = appRoutes[AdminRoutes.students]!(navigator.context);

    expect(built, isA<AdminAccessGuard>());
    expect((built as AdminAccessGuard).child, isA<AdminStudentsScreen>());
    expect(built.requiredPermissions, {
      'admin.students.read',
      'admin.students.manage',
    });
  });

  testWidgets('Tutors opens the guarded Tutor Roster page', (tester) async {
    final navigator = await _pumpApp(tester);
    final built = appRoutes[AdminRoutes.tutors]!(navigator.context);

    expect(built, isA<AdminAccessGuard>());
    expect((built as AdminAccessGuard).child, isA<AdminTutorsScreen>());
    expect(built.requiredPermissions, {
      'admin.tutors.read',
      'admin.tutors.manage',
    });
  });

  testWidgets('Reviews opens the guarded read-only Reviews page', (
    tester,
  ) async {
    final navigator = await _pumpApp(tester);
    final built = appRoutes[AdminRoutes.reviews]!(navigator.context);

    expect(built, isA<AdminAccessGuard>());
    expect((built as AdminAccessGuard).child, isA<AdminReviewsScreen>());
    expect(built.requiredPermissions, {'admin.reviews.read'});
  });

  testWidgets('Reports opens the guarded read-only Reports page', (
    tester,
  ) async {
    final navigator = await _pumpApp(tester);
    final built = appRoutes[AdminRoutes.reports]!(navigator.context);

    expect(built, isA<AdminAccessGuard>());
    expect((built as AdminAccessGuard).child, isA<AdminReportsScreen>());
    expect(built.requiredPermissions, {'admin.reports.read'});
  });
  testWidgets('Users route requires admin.users.manage', (tester) async {
    final navigator = await _pumpApp(tester);
    final built = appRoutes[AdminRoutes.users]!(navigator.context);

    expect(built, isA<AdminAccessGuard>());
    expect((built as AdminAccessGuard).requiredPermissions, {
      'admin.users.manage',
    });
    expect(built.child, isA<AdminUsersScreen>());
  });

  testWidgets('Subjects route is registered behind the Admin guard', (
    tester,
  ) async {
    final navigator = await _pumpApp(tester);
    final built = appRoutes[AdminRoutes.subjects]!(navigator.context);

    expect(built, isA<AdminAccessGuard>());
    expect((built as AdminAccessGuard).child, isA<AdminSubjectsScreen>());
    expect(built.requiredPermissions, {'admin.subjects.manage'});

    // Navigating resolves the route; without a verified admin the guard
    // withholds the page instead of throwing.
    navigator.pushNamed(AdminRoutes.subjects);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Subject Management'), findsNothing);
    expect(find.text('This page could not be found.'), findsNothing);
    expect(find.text('Return to sign in'), findsOneWidget);
  });

  testWidgets('sidebar keeps Students and lists Users below Applications', (
    tester,
  ) async {
    _phoneSizedView(tester);
    await tester.pumpWidget(
      _withPermissions(
        _allPermissions,
        MaterialApp(
          home: AdminSectionUnavailableScreen(
            currentRoute: AdminRoutes.tutors,
            title: 'Tutors',
            loadAccess: () async => const AdminAccessResult.denied(),
          ),
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
    expect(top('Users'), lessThan(top('Reviews')));
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

    testWidgets('$title page hides its placeholder sidebar item', (
      tester,
    ) async {
      _phoneSizedView(tester);
      await tester.pumpWidget(
        _withPermissions(
          _allPermissions,
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
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("This section isn't available yet"), findsOneWidget);
      expect(find.text('Admin Tester'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text(title)),
        findsNothing,
      );
    });
  }

  testWidgets('sidebar highlights the current page only', (tester) async {
    await _openDrawer(tester, _allPermissions, AdminRoutes.reviews);

    final selected = _drawerLabel(tester, 'Reviews');
    expect(selected.style?.fontWeight, FontWeight.w600);
    expect(selected.style?.color, AdminColors.primary);
    for (final other in ['Dashboard', 'Reports', 'Refunds & Issues']) {
      expect(_drawerLabel(tester, other).style?.fontWeight, FontWeight.w400);
    }
  });

  testWidgets('sidebar shows only items the permissions allow', (tester) async {
    await _openDrawer(tester, {
      'admin.dashboard.read',
      'admin.reports.read',
      'admin.refunds.read',
    });

    for (final shown in [
      'Dashboard',
      'Reports',
      'Refunds & Issues',
      'Settings',
    ]) {
      expect(_drawerItem(shown), findsOneWidget, reason: shown);
    }
    for (final hidden in [
      'Students',
      'Tutors',
      'Applications',
      'Users',
      'Reviews',
      'Monitor Platform',
      'Subjects',
      'Payouts',
    ]) {
      expect(_drawerItem(hidden), findsNothing, reason: hidden);
    }
  });

  testWidgets('items needing several permissions require all of them', (
    tester,
  ) async {
    await _openDrawer(tester, {
      'admin.students.read',
      'admin.tutors.manage',
      'admin.refunds.read',
    });

    expect(_drawerItem('Students'), findsNothing);
    expect(_drawerItem('Tutors'), findsNothing);
    expect(_drawerItem('Refunds & Issues'), findsNothing);
  });

  testWidgets('sidebar hides section headings with no visible items', (
    tester,
  ) async {
    await _openDrawer(tester, {'admin.reviews.read'});

    expect(_drawerItem('CONTENT'), findsOneWidget);
    expect(_drawerItem('Reviews'), findsOneWidget);
    for (final heading in ['OVERVIEW', 'USERS', 'FINANCIALS', 'ANALYTICS']) {
      expect(_drawerItem(heading), findsNothing, reason: heading);
    }
    expect(_drawerItem('SYSTEM'), findsOneWidget);
  });

  testWidgets('a missing permission scope exposes no restricted items', (
    tester,
  ) async {
    await _openDrawer(tester, null);

    for (final hidden in [
      'Dashboard',
      'Students',
      'Tutors',
      'Applications',
      'Users',
      'Reviews',
      'Refunds & Issues',
      'Reports',
      'Monitor Platform',
    ]) {
      expect(_drawerItem(hidden), findsNothing, reason: hidden);
    }
    expect(_drawerItem('Settings'), findsOneWidget);
  });

  testWidgets('sidebar links to every new section navigate without errors', (
    tester,
  ) async {
    _phoneSizedView(tester);
    await tester.pumpWidget(
      _withPermissions(
        _allPermissions,
        MaterialApp(
          routes: appRoutes,
          onUnknownRoute: onUnknownAppRoute,
          home: AdminSectionUnavailableScreen(
            currentRoute: AdminRoutes.tutors,
            title: 'Tutors',
            loadAccess: () async => const AdminAccessResult.denied(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('This page could not be found.'), findsNothing);
    // The Reports route opened its guard (denied here, with no signed-in admin).
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
