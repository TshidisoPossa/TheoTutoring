import 'package:flutter/material.dart';

import 'tutor_chats.dart';
import 'tutor_dashboard.dart';
import 'tutor_profile.dart';
import 'tutor_schedule.dart';

/// The tutor bottom bar: 0 Dashboard, 1 Schedule, 2 Chats, 3 Profile.
/// Dashboard, Schedule and Profile replace each other so the back button
/// does not walk through every tab; Chats opens on top because it closes
/// itself with its own back arrow.
void openTutorTab(BuildContext context, int index, {required int current}) {
  if (index == current) return;
  if (index == 2) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TutorChatListScreen()),
    );
    return;
  }
  final Widget page = switch (index) {
    0 => const TutorDashboard(),
    1 => const TutorScheduleScreen(),
    _ => const TutorProfileScreen(),
  };
  Navigator.pushReplacement(
    context,
    PageRouteBuilder(
      pageBuilder: (_, _, _) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}
