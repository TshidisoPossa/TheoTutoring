import 'package:flutter/material.dart';

import '../account_suspension_page.dart';
import '../notifications_screen.dart';
import 'tutor_api.dart';
import 'tutor_booking_detail.dart';
import 'tutor_theme.dart';

/// The link under a tutor's card, or null: lesson cards open the lesson,
/// suspension and appeal cards open the appeal page.
String? tutorLessonLink(NotificationItem n) {
  final account = accountNoticeLink(n.type);
  if (account != null) return account;
  if (n.bookingId == null) return null;
  return switch (n.type) {
    'UpcomingSession' => 'View scheduled lesson',
    'BookingConfirmed' => 'View booked lesson',
    _ => null,
  };
}

/// The tutor's bell page. Tapping a bottom-bar tab pops it with that tab's
/// index, so the dashboard underneath can open the tab.
class TutorNotificationsScreen extends StatelessWidget {
  const TutorNotificationsScreen({
    super.key,
    this.loadNotifications = fetchTutorNotifications,
    this.accountPage,
  });

  /// Loads the page; tests pass their own.
  final Future<Map<String, dynamic>> Function() loadNotifications;

  /// The page suspension and appeal cards open; tests pass their own.
  final Widget Function()? accountPage;

  static const _blue  = Color(0xFF246BFE);
  static const _muted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    return NotificationsScreen(
      roleLabel: 'Tutor',
      accent: _blue,
      loadNotifications: loadNotifications,
      markRead: markTutorNotificationRead,
      markAllRead: markAllTutorNotificationsRead,
      emptyMessage:
          "We'll let you know when a student books or cancels a lesson, "
          'leaves you a review, or a lesson is about to start.',
      linkLabel: tutorLessonLink,
      onLink: (context, n) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => accountNoticeLink(n.type) != null
              ? accountPage?.call() ?? const AccountSuspensionPage()
              : TutorBookingDetailScreen(bookingId: n.bookingId!),
        ),
      ),
      bottomNav: _bottomNav,
    );
  }

  // The tutor bottom bar with no tab highlighted.
  static Widget _bottomNav(ValueChanged<int> goToTab) {
    return Builder(
      builder: (context) => _bottomBar(context, goToTab),
    );
  }

  static Widget _bottomBar(BuildContext context, ValueChanged<int> goToTab) {
    return Container(
      decoration: BoxDecoration(
        color: context.tutorDark ? TutorDark.card : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: _muted,
        unselectedItemColor: _muted,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: goToTab,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inbox_rounded), label: 'Schedule'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}
