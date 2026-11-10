import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/tutor.dart';
import '../../services/tutor_search_api.dart';
import '../Booking/booking_flow_context.dart';
import '../Booking/booking_select_lesson.dart';
import '../Tutor/tutor_theme.dart';
import 'student_tutor_profile.dart';

/// Opened by "Book a new time" on a "Session rescheduled" notification:
/// loads the tutor, then replaces itself with the booking page for the same
/// tutor and subject, so the student can pick a different date and time.
/// If the tutor no longer teaches that subject, it opens their profile
/// instead, where the student can choose another one.
class StudentRebookPage extends StatefulWidget {
  const StudentRebookPage({
    required this.tutorId,
    this.subjectId,
    this.studentName,
    this.studentPhoto,
    this.loadTutor,
    this.bookingPage,
    super.key,
  });

  final int tutorId;
  final int? subjectId;

  /// The signed-in student, carried into the booking pages.
  final String? studentName;
  final String? studentPhoto;

  /// Loads the tutor (GET /tutors/{id}); tests pass their own.
  final Future<Tutor> Function(int tutorId)? loadTutor;

  /// Builds the booking page; tests pass their own.
  final Widget Function(BookingFlowContext flow)? bookingPage;

  @override
  State<StudentRebookPage> createState() => _StudentRebookPageState();
}

class _StudentRebookPageState extends State<StudentRebookPage> {
  String? _error;

  // Light colours, or the dark ones while dark mode is on
  bool get _dk => context.tutorDark;
  Color get _bg => _dk ? TutorDark.background : const Color(0xFFF1F4F9);
  Color get _text => _dk ? TutorDark.text : const Color(0xFF17233D);
  Color get _muted => _dk ? TutorDark.textMuted : const Color(0xFF6B7385);
  static const _blue = Color(0xFF356AE6);

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<Tutor> _fetchTutor(int tutorId) async {
    final api = TutorSearchApi();
    try {
      return (await api.profile(tutorId)).tutor;
    } finally {
      api.close();
    }
  }

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      final tutor = await (widget.loadTutor ?? _fetchTutor)(widget.tutorId);
      if (!mounted) return;

      final matches = tutor.subjects.where(
        (s) => s.subjectId == widget.subjectId,
      );
      final Widget next;
      if (matches.isNotEmpty) {
        final flow = BookingFlowContext(
          tutor: tutor,
          subject: matches.first,
          studentName: widget.studentName,
          studentPhoto: widget.studentPhoto,
        );
        next = widget.bookingPage?.call(flow) ??
            BookingSelectLessonPage(flow: flow);
      } else {
        next = StudentTutorProfilePage(
          tutor: tutor,
          studentName: widget.studentName,
          studentPhoto: widget.studentPhoto,
        );
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => next),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is TutorSearchException
            ? e.message
            : 'Could not open the booking page. Check your connection.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _text,
        elevation: 0,
        title: Text(
          'Book a new time',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _text,
          ),
        ),
      ),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator(color: _blue)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 48, color: _muted),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 13, color: _muted),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _open,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
