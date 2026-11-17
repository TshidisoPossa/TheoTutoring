import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Student/student_bottom_nav.dart' show openStudentTab;
import '../Tutor/tutor_theme.dart';
import 'booking_flow_context.dart';

const Color _primaryBlue = Color(0xFF356AE6);

/// Blue text and icons: lighter while dark mode is on.
Color _blueText(BuildContext context) =>
    context.tutorDark ? TutorDark.blueText : _primaryBlue;

/// The booking pages' top bar: logo, page title and the student's photo
/// (or initials), like the dashboard and tutor search. With [onBack], a back
/// arrow sits before the logo.
PreferredSizeWidget bookingTopBar({
  required String title,
  required BookingFlowContext flow,
  VoidCallback? onBack,
}) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(kToolbarHeight),
    child: Builder(
      builder: (context) => _topBar(context, title, flow, onBack),
    ),
  );
}

AppBar _topBar(
  BuildContext context,
  String title,
  BookingFlowContext flow,
  VoidCallback? onBack,
) {
  final surface = context.tutorDark ? TutorDark.card : Colors.white;
  return AppBar(
    backgroundColor: surface,
    surfaceTintColor: surface,
    elevation: 0,
    scrolledUnderElevation: 0,
    automaticallyImplyLeading: false,
    // The same arrow as the payment page's
    leading: onBack == null
        ? null
        : IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: context.tutorDark
                  ? TutorDark.text
                  : const Color(0xFF17233D),
            ),
          ),
    titleSpacing: onBack == null ? 20 : 4,
    title: Row(
      children: [
        Image.asset(
          'assets/logo.png',
          height: 40,
          width: 40,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: _primaryBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: _blueText(context),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 18),
        // The student's photo opens the Profile tab on the dashboard
        child: Tooltip(
          message: 'Profile',
          child: GestureDetector(
            onTap: () => openStudentTab(context, 3),
            child: _StudentAvatar(
              name: flow.studentName,
              photo: flow.studentPhoto,
            ),
          ),
        ),
      ),
    ],
  );
}

class _StudentAvatar extends StatelessWidget {
  const _StudentAvatar({required this.name, required this.photo});

  final String? name;
  final String? photo;

  String get _initials => (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final initials = _initials;
    final fallback = initials.isEmpty
        ? Icon(Icons.person_rounded, color: _blueText(context), size: 22)
        : Text(
            initials,
            style: GoogleFonts.poppins(
              color: _blueText(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          );
    final photo = this.photo;
    return CircleAvatar(
      radius: 20,
      backgroundColor: context.tutorDark
          ? TutorDark.blueTint
          : const Color(0xFFE4ECFF),
      child: photo == null || photo.isEmpty
          ? fallback
          : ClipOval(
              child: Image.network(
                photo,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(child: fallback),
              ),
            ),
    );
  }
}
