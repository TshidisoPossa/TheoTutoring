import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Persistent bottom navigation shared by the student screens.
class StudentBottomNav extends StatelessWidget {
  const StudentBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  static const Color _primaryBlue = Color(0xFF356AE6);
  static const Color _textMuted = Color(0xFF7B8498);

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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFEDF0F7))),
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
                          color: selected ? _primaryBlue : _textMuted,
                          size: 22,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.label,
                          style: GoogleFonts.poppins(
                            color: selected ? _primaryBlue : _textMuted,
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
