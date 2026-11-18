import 'package:flutter/material.dart';

import '../notifications_screen.dart';
import 'Services/admin_notifications_api.dart';
import 'admin_shell.dart';

/// The page an admin notification card links to, or null.
String? adminRouteFor(NotificationItem n) => switch (n.type) {
  'ApplicationSubmitted' => AdminRoutes.applications,
  'ReportSubmitted' => AdminRoutes.reports,
  'RefundRequested' => AdminRoutes.refunds,
  'ChatFlagged' => AdminRoutes.chatModeration,
  _ => null,
};

/// The link under an admin card, e.g. "Review application".
String? adminNotificationLink(NotificationItem n) => switch (n.type) {
  'ApplicationSubmitted' => 'Review application',
  'ReportSubmitted' => 'Review report',
  'RefundRequested' => 'Review refund',
  'ChatFlagged' => 'Review chat message',
  _ => null,
};

/// The admin's bell page: the same list and layout students and tutors
/// have (no bottom bar), with admin events such as new applications,
/// reports and refunds to review.
class AdminNotificationsScreen extends StatelessWidget {
  const AdminNotificationsScreen({
    super.key,
    this.loadNotifications = fetchAdminNotifications,
    this.markRead = markAdminNotificationRead,
    this.markAllRead = markAllAdminNotificationsRead,
  });

  /// The API calls; tests pass their own.
  final Future<Map<String, dynamic>> Function() loadNotifications;
  final Future<int> Function(String id) markRead;
  final Future<int> Function() markAllRead;

  @override
  Widget build(BuildContext context) => NotificationsScreen(
    roleLabel: 'Admin',
    accent: AdminColors.accent,
    loadNotifications: loadNotifications,
    markRead: markRead,
    markAllRead: markAllRead,
    emptyMessage:
        "We'll let you know when a tutor applies, someone files a report, "
        'or a refund needs your review.',
    linkLabel: adminNotificationLink,
    onLink: (context, n) async {
      final route = adminRouteFor(n);
      if (route != null) await Navigator.pushNamed(context, route);
    },
  );
}
