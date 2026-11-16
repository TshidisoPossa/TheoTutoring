import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Tutor/tutor_theme.dart';

/// The tab (0 Home, 1 Lessons, 2 Chat, 3 Profile) a page opened on top of
/// the student dashboard asked it to show. The dashboard listens, switches
/// to that tab and clears the request.
final ValueNotifier<int?> studentTabRequest = ValueNotifier<int?>(null);

/// Opens a student bottom-nav tab from any page opened on top of the
/// dashboard: returns to the dashboard (the root of the student stack, so
/// no duplicate copies pile up) and shows [index] there.
void openStudentTab(BuildContext context, int index) {
  if (index < 0 || index >= StudentBottomNav.items.length) return;
  studentTabRequest.value = index;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Persistent bottom navigation shared by the student screens.
class StudentBottomNav extends StatelessWidget {
  const StudentBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });


  static const List<({IconData icon, String label})> items = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.menu_book_rounded, label: 'Lessons'),
    (icon: Icons.chat_bubble_outline_rounded, label: 'Chat'),
    (icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    // Light colours, or the dark ones while dark mode is on
    final dark = context.tutorDark;
    final selectedColor = dark ? TutorDark.blueText : const Color(0xFF356AE6);
    final muted = dark ? TutorDark.textMuted : const Color(0xFF7B8498);
    return Container(
      decoration: BoxDecoration(
        color: dark ? TutorDark.card : Colors.white,
        border: Border(
          top: BorderSide(
            color: dark ? TutorDark.border : const Color(0xFFEDF0F7),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23365D).withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = currentIndex == index;

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(index),
                  borderRadius: BorderRadius.circular(13),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          color: selected ? selectedColor : muted,
                          size: 22,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.label,
                          style: GoogleFonts.poppins(
                            color: selected ? selectedColor : muted,
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
