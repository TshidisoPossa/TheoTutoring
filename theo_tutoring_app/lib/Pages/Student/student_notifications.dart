import 'package:flutter/material.dart';

import '../notifications_screen.dart';
import 'student_bottom_nav.dart';
import 'student_notifications_api.dart';

/// Bottom-bar index of the Lessons tab, where the lesson links go.
const studentLessonsTab = 1;

/// The link under a student's card, or null: lesson cards go to Lessons.
String? studentLessonLink(NotificationItem n) => switch (n.type) {
      'UpcomingSession' => 'View upcoming lesson',
      'PaymentReceived' => 'View my lessons',
      _ => null,
    };

/// The student's bell page. It pops with a bottom-bar tab index (a tab was
/// tapped, or a lesson link opens Lessons), so the dashboard can switch to
/// that tab.
class StudentNotificationsScreen extends StatelessWidget {
  const StudentNotificationsScreen({
    super.key,
    this.loadNotifications = fetchStudentNotifications,
  });

  /// Loads the page; tests pass their own.
  final Future<Map<String, dynamic>> Function() loadNotifications;

  @override
  Widget build(BuildContext context) {
    return NotificationsScreen(
      roleLabel: 'Student',
      accent: const Color(0xFF356AE6),
      loadNotifications: loadNotifications,
      markRead: markStudentNotificationRead,
      markAllRead: markAllStudentNotificationsRead,
      emptyMessage:
          "We'll let you know when a payment goes through, a lesson is about "
          'to start, or there is news about a refund.',
      linkLabel: studentLessonLink,
      onLink: (context, n) async =>
          Navigator.pop(context, studentLessonsTab),
      // -1: no tab is highlighted on this page
      bottomNav: (goToTab) =>
          StudentBottomNav(currentIndex: -1, onTap: goToTab),
    );
  }
}
