import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'booking_flow_context.dart';

const Color _primaryBlue = Color(0xFF356AE6);

/// The booking pages' top bar: logo, page title and the student's photo
/// (or initials), like the dashboard and tutor search.
PreferredSizeWidget bookingTopBar({
  required String title,
  required BookingFlowContext flow,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    automaticallyImplyLeading: false,
    titleSpacing: 20,
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
              color: _primaryBlue,
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
        child: _StudentAvatar(name: flow.studentName, photo: flow.studentPhoto),
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
        ? const Icon(Icons.person_rounded, color: _primaryBlue, size: 22)
        : Text(
            initials,
            style: GoogleFonts.poppins(
              color: _primaryBlue,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          );
    final photo = this.photo;
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFFE4ECFF),
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
