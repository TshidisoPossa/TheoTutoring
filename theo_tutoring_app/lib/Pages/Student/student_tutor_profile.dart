import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/tutor.dart';
import '../Booking/booking_flow_context.dart';
import '../Booking/booking_select_lesson.dart';
import 'student_bottom_nav.dart';

/// Route name used by the tutor search page so "Home" can unwind to it.
const String tutorSearchRouteName = 'student/tutor-search';

/// Student-facing view of a tutor, shown before starting a booking.
class StudentTutorProfilePage extends StatelessWidget {
  const StudentTutorProfilePage({required this.tutor, super.key});

  final Tutor tutor;

  static const Color _primaryBlue = Color(0xFF356AE6);
  static const Color _darkBlue = Color(0xFF173B8F);
  static const Color _background = Color(0xFFF7F9FE);
  static const Color _textDark = Color(0xFF17233D);
  static const Color _textMuted = Color(0xFF7B8498);

  String get _initials => tutor.name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();

  Future<void> _book(BuildContext context) async {
    TutorSubject? subject;
    if (tutor.subjects.length == 1) {
      subject = tutor.subjects.first;
    } else {
      subject = await showModalBottomSheet<TutorSubject>(
        context: context,
        backgroundColor: Colors.white,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Choose a subject',
                style: GoogleFonts.poppins(
                  color: _textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              ...tutor.subjects.map(
                (item) => ListTile(
                  title: Text(item.subjectName),
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (subject == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingSelectLessonPage(
          flow: BookingFlowContext(tutor: tutor, subject: subject!),
        ),
      ),
    );
  }

  void _navTapped(BuildContext context, int index) {
    if (index == 0) {
      final navigator = Navigator.of(context);
      var foundSearch = false;
      navigator.popUntil((route) {
        if (route.settings.name == tutorSearchRouteName) {
          foundSearch = true;
          return true;
        }
        return route.isFirst;
      });
      if (foundSearch) navigator.pop();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${StudentBottomNav.items[index].label} will be connected soon.',
            style: GoogleFonts.poppins(fontSize: 12),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _textDark,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          'Tutor Profile',
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _section(
                      'About',
                      Text(
                        tutor.bio ?? 'Biography not provided.',
                        style: GoogleFonts.poppins(
                          color: _textDark,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section('Subjects', _buildSubjects()),
                    const SizedBox(height: 16),
                    _section(
                      'Experience',
                      Text(
                        tutor.experience ?? 'Experience not provided',
                        style: GoogleFonts.poppins(
                          color: _textDark,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      'Hourly rate',
                      Text(
                        tutor.hourlyRate == null
                            ? 'Hourly rate unavailable'
                            : tutor.hourlyRate!.toStringAsFixed(2),
                        style: GoogleFonts.poppins(
                          color: _textDark,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: _background,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: tutor.subjects.isEmpty
                        ? null
                        : () => _book(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Book Session',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          StudentBottomNav(
            currentIndex: 0,
            onTap: (index) => _navTapped(context, index),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final rating = tutor.averageRating;
    return _card(
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFFE4ECFF),
            child: tutor.profilePhoto == null
                ? Text(
                    _initials,
                    style: GoogleFonts.poppins(
                      color: _darkBlue,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : ClipOval(
                    child: Image.network(
                      tutor.profilePhoto!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Text(
                        _initials,
                        style: GoogleFonts.poppins(
                          color: _darkBlue,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            tutor.name,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (rating != null) ...[
                const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFFFB547),
                  size: 18,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                rating == null
                    ? 'No reviews yet'
                    : '${rating.toStringAsFixed(1)} '
                          '(${tutor.reviewCount} reviews)',
                style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubjects() {
    if (tutor.subjects.isEmpty) {
      return Text(
        'No subjects listed.',
        style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final subject in tutor.subjects)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF3FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              subject.subjectName,
              style: GoogleFonts.poppins(
                color: _darkBlue,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDF6)),
        boxShadow: [
          BoxShadow(
            color: _darkBlue.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
