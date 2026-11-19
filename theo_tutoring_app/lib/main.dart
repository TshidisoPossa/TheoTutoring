import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'Pages/Admin/admin_subjects.dart';

import 'Pages/auth_gate.dart';
import 'Pages/splash_screen.dart';
import 'Pages/Admin/admin_appeals.dart';
import 'Pages/Admin/admin_chat_moderation.dart';
import 'services/app_navigator.dart';
import 'Pages/Admin/admin_shell.dart';
import 'Pages/Admin/admin_refunds.dart';
import 'Pages/Admin/admin_monitor.dart';
import 'Pages/Admin/admin_payouts.dart';
import 'Pages/Admin/admin_settings.dart';
import 'Pages/Admin/admin_access_guard.dart';
import 'Pages/Admin/admin_dashboard.dart';
import 'Pages/Admin/admin_students.dart';
import 'Pages/Admin/admin_tutors.dart';
import 'Pages/Admin/admin_unavailable.dart';
import 'Pages/Admin/admin_users.dart';
import 'Pages/Admin/application_screen.dart';
import 'Pages/Admin/admin_reports.dart';
import 'Pages/Admin/admin_reviews.dart';
import 'Pages/Admin/application_review_screen.dart';
import 'Pages/Admin/models/Tutapplication.dart';
import 'Pages/Tutor/tutor_theme.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/google_meet_connect.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  startGoogleSignIn(); // Connect Google Meet; not awaited
  await TutorTheme.load();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.authService});

  /// Tests pass a fake; the app uses the real Firebase sign-in.
  final AuthService? authService;

  @override
  Widget build(BuildContext context) {
    // Dark only while a tutor who chose dark mode is signed in
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: TutorTheme.mode,
      builder: (context, themeMode, _) => MaterialApp(
        // In-app notification banners show over any page through this
        navigatorKey: appNavigatorKey,
        title: 'TheoTutoring',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246BFE)),
          useMaterial3: true,
        ),
        darkTheme: TutorTheme.darkTheme,
        themeMode: themeMode,
        // The animated introduction first, then the usual entry: signed in,
        // their dashboard; signed out, the Log In / Register screen.
        home: SplashScreen(next: (_) => AuthGate(service: authService)),
        routes: appRoutes,
        onUnknownRoute: onUnknownAppRoute,
      ),
    );
  }
}

/// Admin sidebar sections that have no page yet. Each opens a guarded
/// "not available yet" page that keeps the sidebar item highlighted.
const unavailableAdminSections = <String, String>{};

final Map<String, WidgetBuilder> appRoutes = {
  AdminRoutes.dashboard: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.dashboard.read'},
    child: AdminDashboardScreen(),
  ),
  AdminRoutes.refunds: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.refunds.read', 'admin.reports.read'},
    child: AdminRefundsIssuesScreen(),
  ),
  AdminRoutes.payouts: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.finance.read'},
    child: AdminPayoutsScreen(),
  ),
  AdminRoutes.monitor: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.monitor.read'},
    child: AdminMonitorPlatformScreen(),
  ),
  AdminRoutes.settings: (_) =>
      const AdminAccessGuard(child: AdminSettingsScreen()),
  AdminRoutes.applications: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.applications.read'},
    child: AdminApplicationsScreen(),
  ),
  AdminRoutes.applicationReview: (context) {
    final argument = ModalRoute.of(context)?.settings.arguments;
    return AdminAccessGuard(
      requiredPermissions: {'admin.applications.review'},
      child: AdminApplicationReviewScreen(
        application: argument is TutorApplication ? argument : null,
      ),
    );
  },
  AdminRoutes.students: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.students.read', 'admin.students.manage'},
    child: AdminStudentsScreen(),
  ),
  AdminRoutes.appeals: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.students.manage', 'admin.tutors.manage'},
    child: AdminAppealsScreen(),
  ),
  AdminRoutes.subjects: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.subjects.manage'},
    child: AdminSubjectsScreen(),
  ),
  AdminRoutes.tutors: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.tutors.read', 'admin.tutors.manage'},
    child: AdminTutorsScreen(),
  ),
  AdminRoutes.reviews: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.reviews.read'},
    child: AdminReviewsScreen(),
  ),
  AdminRoutes.reports: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.reports.read'},
    child: AdminReportsScreen(),
  ),
  AdminRoutes.chatModeration: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.reports.read'},
    child: AdminChatModerationScreen(),
  ),
  AdminRoutes.users: (_) => const AdminAccessGuard(
    requiredPermissions: {'admin.users.manage'},
    child: AdminUsersScreen(),
  ),
  for (final section in unavailableAdminSections.entries)
    section.key: (_) => AdminAccessGuard(
      child: AdminSectionUnavailableScreen(
        currentRoute: section.key,
        title: section.value,
      ),
    ),
};

/// Any other unknown route shows a neutral page instead of throwing. It does
/// not reveal Admin content and leads back to sign-in.
Route<void> onUnknownAppRoute(RouteSettings settings) => MaterialPageRoute(
  settings: settings,
  builder: (context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'This page could not be found.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (_) => false),
              child: const Text('Return to sign in'),
            ),
          ],
        ),
      ),
    ),
  ),
);
