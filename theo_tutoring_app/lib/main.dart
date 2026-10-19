import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'Pages/splash_screen.dart';
import 'Pages/Admin/admin_dashboardscreen.dart';
import 'Pages/Admin/application_screen.dart';
import 'Pages/Admin/FinancialScreen.dart';
import 'Pages/Admin/subject_screen.dart';
import 'Pages/Admin/admin_shell.dart';
import 'Pages/Admin/admin_monitor.dart';
import 'Pages/Admin/admin_refunds.dart';
import 'Pages/Admin/admin_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TheoTutoring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF246BFE),
        ),
        useMaterial3: true,
      ),
      home: const  SplashScreen(),
      routes: {
        AdminRoutes.dashboard: (_) => const AdminDashboardPage(),
        AdminRoutes.applications: (_) => const AdminApplicationsScreen(),
        AdminRoutes.subjects: (_) => const AdminSubjectsScreen(),
        AdminRoutes.payouts: (_) => const AdminFinancialScreen(),
        AdminRoutes.refunds: (_) => const AdminRefundsIssuesScreen(),
        AdminRoutes.monitor: (_) => const AdminMonitorPlatformScreen(),
        AdminRoutes.settings: (_) => const AdminSettingsScreen(),
      },
    );
  }
}