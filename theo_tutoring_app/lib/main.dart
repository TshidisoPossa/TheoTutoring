import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'Pages/splash_screen.dart';
import 'Pages/Admin/admin_dashboardscreen.dart';
import 'Pages/Admin/application_screen.dart';
<<<<<<< HEAD
import 'Pages/Admin/FinancialScreen.dart';
import 'Pages/Admin/subject_screen.dart';
=======
import 'Pages/Admin/admin_shell.dart';
>>>>>>> 709d101800f3647c20d0673e74b1bdfb552ae0a9

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
      },
    );
  }
}