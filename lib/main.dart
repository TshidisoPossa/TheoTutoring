import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/student/student_dashboard.dart';

void main() {
  runApp(const TheoTutoringApp());
}

class TheoTutoringApp extends StatelessWidget {
  const TheoTutoringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TheoTutoring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
        ),
        textTheme: GoogleFonts.interTextTheme(),
        useMaterial3: true,
      ),
      home: const StudentDashboard(),
    );
  }
}