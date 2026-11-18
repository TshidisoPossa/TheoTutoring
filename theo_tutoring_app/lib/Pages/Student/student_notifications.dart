import 'package:flutter/material.dart';

import '../account_suspension_page.dart';
import '../notifications_screen.dart';
import 'student_bottom_nav.dart';
import 'student_notifications_api.dart';
import 'student_rebook.dart';

/// Bottom-bar index of the Lessons tab, where the lesson links go.
const studentLessonsTab = 1;

/// The link under a student's card, or null: lesson cards go to Lessons,
/// a lesson the tutor rescheduled goes to that tutor's booking page, and
/// suspension and appeal cards go to the appeal page.
String? studentLessonLink(NotificationItem n) => switch (n.type) {
      'UpcomingSession' => 'View upcoming lesson',
      'PaymentReceived' || 'BookingCancelled' => 'View my lessons',
      'BookingRescheduled' when n.tutorId != null => 'Book a new time',
      _ => accountNoticeLink(n.type),
    };

/// The student's bell page. It pops with a bottom-bar tab index (a tab was
/// tapped, or a lesson link opens Lessons), so the dashboard can switch to
/// that tab.
class StudentNotificationsScreen extends StatelessWidget {
  const StudentNotificationsScreen({
    super.key,
    this.loadNotifications = fetchStudentNotifications,
    this.studentName,
    this.studentPhoto,
    this.rebookPage,
    this.accountPage,
  });

  /// Loads the page; tests pass their own.
  final Future<Map<String, dynamic>> Function() loadNotifications;

  /// The signed-in student, carried into the booking pages.
  final String? studentName;
  final String? studentPhoto;

  /// The page "Book a new time" opens; tests pass their own.
  final Widget Function(NotificationItem n)? rebookPage;

  /// The page suspension and appeal cards open; tests pass their own.
  final Widget Function()? accountPage;

  @override
  Widget build(BuildContext context) {
    return NotificationsScreen(
      accent: const Color(0xFF356AE6),
      loadNotifications: loadNotifications,
      markRead: markStudentNotificationRead,
      markAllRead: markAllStudentNotificationsRead,
      emptyMessage:
          "We'll let you know when a payment goes through, a lesson is about "
          'to start or changes, or there is news about a refund.',
      linkLabel: studentLessonLink,
      onLink: (context, n) async {
        if (accountNoticeLink(n.type) != null) {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => accountPage?.call() ?? const AccountSuspensionPage(),
            ),
          );
          return;
        }
        if (n.type == 'BookingRescheduled' && n.tutorId != null) {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  rebookPage?.call(n) ??
                  StudentRebookPage(
                    tutorId: n.tutorId!,
                    subjectId: n.subjectId,
                    studentName: studentName,
                    studentPhoto: studentPhoto,
                  ),
            ),
          );
          return;
        }
        Navigator.pop(context, studentLessonsTab);
      },
      // -1: no tab is highlighted on this page
      // Same as every student page: back to the dashboard on that tab
      bottomNav: (_) => StudentBottomNav(
        currentIndex: -1,
        onTap: (index) => openStudentTab(context, index),
      ),
    );
  }
}
