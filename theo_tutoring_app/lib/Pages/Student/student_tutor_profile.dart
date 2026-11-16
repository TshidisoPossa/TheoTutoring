import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/tutor.dart';
import '../../models/tutor_profile_details.dart';
import '../../services/student_chat_models.dart';
import '../../services/student_chat_service.dart';
import '../../services/tutor_search_api.dart';
import '../Booking/booking_flow_context.dart';
import '../Booking/booking_select_lesson.dart';
import '../Tutor/tutor_theme.dart';
import 'student_bottom_nav.dart';
import 'student_chats.dart';
import 'student_lesson.dart';
import 'student_reports_api.dart';

/// Route name used by the tutor search page so "Home" can unwind to it.
const String tutorSearchRouteName = 'student/tutor-search';

/// Student-facing view of a tutor (View Profile), shown before booking.
/// Opens with the search result's details straight away, then loads
/// qualifications, availability, reviews and "Available Now" from
/// GET /tutors/{id}.
class StudentTutorProfilePage extends StatefulWidget {
  const StudentTutorProfilePage({
    required this.tutor,
    this.studentName,
    this.studentPhoto,
    this.api,
    this.reportsApi,
    this.chatService,
    super.key,
  });

  final Tutor tutor;

  /// The signed-in student, carried into the booking flow.
  final String? studentName;
  final String? studentPhoto;

  /// Injected by tests; the page creates (and closes) its own otherwise.
  final TutorSearchApi? api;
  final StudentReportsApi? reportsApi;

  /// Passed to the chat screen; it creates its own when null.
  final StudentChatService? chatService;

  @override
  State<StudentTutorProfilePage> createState() =>
      _StudentTutorProfilePageState();
}

class _StudentTutorProfilePageState extends State<StudentTutorProfilePage> {
  static const Color _primaryBlue = Color(0xFF3B7BF2); // fills: buttons, dots
  static const Color _darkBlue = Color(0xFF173B8F);
  static const Color _star = Color(0xFFF5B301);

  // Light colours, or the dark ones while dark mode is on
  bool get _dk => context.tutorDark;
  Color get _background => _dk ? TutorDark.background : const Color(0xFFF1F4F9);
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _border => _dk ? TutorDark.border : const Color(0xFFE5E9F2);
  Color get _textDark => _dk ? TutorDark.text : const Color(0xFF17233D);
  Color get _textMuted => _dk ? TutorDark.textMuted : const Color(0xFF6B7385);
  Color get _chipFill => _dk ? TutorDark.blueTint : const Color(0xFFEAF1FE);
  Color get _greenFill => _dk ? TutorDark.greenTint : const Color(0xFFDDF7E6);
  Color get _greenText => _dk ? TutorDark.greenText : const Color(0xFF15803D);
  Color get _dotOff => _dk ? TutorDark.border : const Color(0xFFDCE1EA);
  Color get _accent => _dk ? TutorDark.blueText : _primaryBlue; // blue text

  static const _weekdays = [
    ('Monday', 'Mon'),
    ('Tuesday', 'Tue'),
    ('Wednesday', 'Wed'),
    ('Thursday', 'Thu'),
    ('Friday', 'Fri'),
    ('Saturday', 'Sat'),
    ('Sunday', 'Sun'),
  ];

  late final TutorSearchApi _api = widget.api ?? TutorSearchApi();
  late final StudentReportsApi _reportsApi =
      widget.reportsApi ?? StudentReportsApi();
  final _reviewsKey = GlobalKey();

  TutorProfileDetails? _details;
  bool _loading = true;
  String? _error;
  bool _showAllReviews = false;
  String? _selectedDay;

  /// The freshest details: the profile once loaded, the search card before.
  Tutor get _tutor => _details?.tutor ?? widget.tutor;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    if (widget.reportsApi == null) _reportsApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await _api.profile(widget.tutor.tutorId);
      if (mounted) setState(() => _details = details);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is TutorSearchException
              ? error.message
              : 'Could not load this profile. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _initials => _tutor.name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();

  String get _firstName => _tutor.name.trim().split(RegExp(r'\s+')).first;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.poppins(fontSize: 12)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _textDark,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _book() async {
    final tutor = _tutor;
    TutorSubject? subject;
    if (tutor.subjects.length == 1) {
      subject = tutor.subjects.first;
    } else {
      subject = await showModalBottomSheet<TutorSubject>(
        context: context,
        backgroundColor: _surface,
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
    if (subject == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingSelectLessonPage(
          flow: BookingFlowContext(
            tutor: tutor,
            subject: subject!,
            studentName: widget.studentName,
            studentPhoto: widget.studentPhoto,
          ),
        ),
      ),
    );
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Report ${_tutor.name}?',
        message:
            'Your report goes to the TheoTutoring administrator, who will '
            'look into it.',
        label: 'What went wrong?',
        dismissLabel: 'Close',
        submitLabel: 'Send report',
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await _reportsApi.reportTutor(_tutor.tutorId, reason);
      _showMessage('Report sent. An administrator will review it.');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  /// Opens the existing student chat with this tutor; the first message sent
  /// creates the conversation.
  void _openChat() {
    final tutor = _tutor;
    final userId = tutor.userId;
    if (userId == null) {
      // Never guess with tutorId: the chat routes take the User ID.
      _showMessage('Messaging is not available for this tutor right now.');
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            contact: StudentChatContact(
              userId: userId,
              name: tutor.name,
              initials: _initials.isEmpty ? '?' : _initials,
              lastMessage: '',
              time: '',
              profilePhotoUrl: tutor.profilePhoto,
              unreadCount: 0,
            ),
            service: widget.chatService,
          ),
        ),
      ),
    );
  }

  // Every tab returns to the dashboard (closing tutor search too, if this
  // page was opened from it) and shows that tab there.
  void _navTapped(int index) => openStudentTab(context, index);

  void _scrollToReviews() {
    final target = _reviewsKey.currentContext;
    if (target != null) {
      unawaited(
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 350),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _surface,
        surfaceTintColor: _surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: _textDark),
        title: Text(
          'Tutor Profile',
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            icon: Icon(Icons.more_vert_rounded, color: _textDark),
            color: _surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (_) => _report(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      size: 20,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Report tutor',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      _buildAbout(),
                      const SizedBox(height: 16),
                      ..._buildDetails(),
                      const SizedBox(height: 24),
                      _buildActions(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: StudentBottomNav(currentIndex: 0, onTap: _navTapped),
    );
  }

  // ── HEADER ──────────────────────────────────────────────

  Widget _buildHeader() {
    final tutor = _tutor;
    final rating = tutor.averageRating;
    final initialsText = Text(
      _initials,
      style: GoogleFonts.poppins(
        color: _dk ? TutorDark.blueText : _darkBlue,
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
    );
    return _card(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      child: Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: _chipFill,
            child: tutor.profilePhoto == null
                ? initialsText
                : ClipOval(
                    child: Image.network(
                      tutor.profilePhoto!,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => initialsText,
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            tutor.name,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (tutor.qualification != null)
            Text(
              tutor.qualification!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _textMuted, fontSize: 13),
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                rating == null ? Icons.star_border_rounded : Icons.star_rounded,
                color: _star,
                size: 20,
              ),
              const SizedBox(width: 4),
              if (rating == null)
                Text(
                  'No reviews yet',
                  style: GoogleFonts.poppins(color: _textMuted, fontSize: 13),
                )
              else ...[
                Text(
                  rating.toStringAsFixed(1),
                  style: GoogleFonts.poppins(
                    color: _textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _scrollToReviews,
                  child: Text(
                    '(${tutor.reviewCount} '
                    '${tutor.reviewCount == 1 ? 'review' : 'reviews'})',
                    style: GoogleFonts.poppins(
                      color: _accent,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      decorationColor: _accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_details != null) ...[
            const SizedBox(height: 10),
            _availabilityBadge(_details!.availableNow),
          ],
        ],
      ),
    );
  }

  Widget _availabilityBadge(bool availableNow) {
    final color = availableNow ? _greenText : _textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: availableNow
            ? _greenFill
            : (_dk ? TutorDark.cardAlt : const Color(0xFFEDF0F5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            availableNow ? 'Available Now' : 'Offline',
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── ABOUT ───────────────────────────────────────────────

  Widget _buildAbout() {
    final tutor = _tutor;
    return _section(
      'About',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tutor.bio ?? '$_firstName has not written a bio yet.',
            style: GoogleFonts.poppins(
              color: _textDark.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 14),
          if (tutor.subjects.isEmpty)
            Text(
              'No subjects listed.',
              style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final subject in tutor.subjects)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _chipFill,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      subject.subjectName,
                      style: GoogleFonts.poppins(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          if (tutor.experience != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.work_history_outlined,
                  size: 16,
                  color: _textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Experience: ${experienceLabel(tutor.experience!)}',
                  style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ],
          if (tutor.hourlyRate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 16, color: _accent),
                const SizedBox(width: 6),
                Text(
                  'R${tutor.hourlyRate!.toStringAsFixed(2)} per session',
                  style: GoogleFonts.poppins(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── QUALIFICATIONS / AVAILABILITY / REVIEWS ─────────────

  List<Widget> _buildDetails() {
    final details = _details;
    if (details == null) {
      return [
        _card(
          child: Center(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  )
                : Column(
                    children: [
                      Text(
                        _error ?? 'Could not load this profile.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: _textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
          ),
        ),
      ];
    }
    return [
      _buildQualifications(details.qualifications),
      const SizedBox(height: 16),
      _buildAvailability(details.availability),
      const SizedBox(height: 24),
      _buildReviews(details.reviews),
    ];
  }

  Widget _buildQualifications(List<TutorQualification> qualifications) {
    return _section(
      'Qualifications',
      qualifications.isEmpty
          ? Text(
              'No qualifications listed.',
              style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
            )
          : Column(
              children: [
                for (var i = 0; i < qualifications.length; i++) ...[
                  if (i > 0) Divider(height: 24, color: _border),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _chipFill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.school_outlined,
                          color: _accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              qualifications[i].degree,
                              style: GoogleFonts.poppins(
                                color: _textDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              qualifications[i].institution,
                              style: GoogleFonts.poppins(
                                color: _textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildAvailability(List<TutorAvailabilitySlot> slots) {
    final availableDays = {for (final slot in slots) slot.day};
    final selected = _selectedDay;
    final selectedSlots = [
      for (final slot in slots)
        if (slot.day == selected) slot,
    ];
    return _section(
      'Availability',
      Column(
        children: [
          Row(
            children: [
              for (final (day, short) in _weekdays)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(
                      () => _selectedDay = _selectedDay == day ? null : day,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected == day ? _chipFill : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            short,
                            style: GoogleFonts.poppins(
                              color: availableDays.contains(day)
                                  ? _textDark
                                  : _textMuted,
                              fontSize: 12,
                              fontWeight: availableDays.contains(day)
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: availableDays.contains(day)
                                  ? _primaryBlue
                                  : _dotOff,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legendDot(_primaryBlue, 'Available'),
              const SizedBox(width: 18),
              _legendDot(_dotOff, 'Unavailable'),
            ],
          ),
          const SizedBox(height: 12),
          if (slots.isEmpty)
            Text(
              '$_firstName has not set their availability yet.',
              style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
            )
          else if (selected == null)
            Text(
              'Tap a day to see time slots',
              style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
            )
          else if (selectedSlots.isEmpty)
            Text(
              'Not available on $selected.',
              style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final slot in selectedSlots)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: _accent),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$selected ${slot.startTime} – ${slot.endTime}',
                      style: GoogleFonts.poppins(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: GoogleFonts.poppins(color: _textMuted, fontSize: 11)),
    ],
  );

  Widget _buildReviews(List<TutorReview> reviews) {
    final rating = _tutor.averageRating;
    final shown = _showAllReviews ? reviews : reviews.take(2).toList();
    return Column(
      key: _reviewsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Reviews',
              style: GoogleFonts.poppins(
                color: _textDark,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (rating != null) ...[
              const Icon(Icons.star_rounded, color: _star, size: 18),
              const SizedBox(width: 4),
              Text(
                '${rating.toStringAsFixed(1)} avg',
                style: GoogleFonts.poppins(color: _textMuted, fontSize: 13),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (reviews.isEmpty)
          _card(
            child: Text(
              'No reviews yet. Reviews appear after completed sessions.',
              style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
            ),
          )
        else
          for (final review in shown) ...[
            _buildReview(review),
            const SizedBox(height: 12),
          ],
        if (reviews.length > 2)
          Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => _showAllReviews = !_showAllReviews),
              child: Text(
                _showAllReviews
                    ? 'Show fewer reviews'
                    : 'See all ${reviews.length} reviews',
                style: GoogleFonts.poppins(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  decorationColor: _accent,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReview(TutorReview review) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _chipFill,
                child: Text(
                  review.studentName.isEmpty
                      ? '?'
                      : review.studentName[0].toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.studentName,
                      style: GoogleFonts.poppins(
                        color: _textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      timeAgo(review.createdAt),
                      style: GoogleFonts.poppins(
                        color: _textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= review.rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: _star,
                  size: 15,
                ),
              const SizedBox(width: 6),
              Text(
                review.rating.toStringAsFixed(1),
                style: GoogleFonts.poppins(
                  color: _textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (review.comment != null) ...[
            const SizedBox(height: 10),
            Text(
              review.comment!,
              style: GoogleFonts.poppins(
                color: _textDark.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── BOOK / MESSAGE ──────────────────────────────────────

  Widget _buildActions() {
    final canBook = _tutor.subjects.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: canBook
              ? 'Choose a subject and time with $_firstName'
              : '$_firstName has not added any subjects yet',
          child: FilledButton.icon(
            onPressed: canBook ? _book : null,
            icon: const Icon(Icons.calendar_month_outlined, size: 20),
            label: const Text('Book a Session'),
            style: FilledButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openChat,
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
          label: const Text('Message Tutor'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: BorderSide(color: _accent, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 15),
            textStyle: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  // ── HELPERS ─────────────────────────────────────────────

  Widget _section(String title, Widget child) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }
}

/// TutorProfile.Experience as tutor registration words it ("1-2" ->
/// "1–2 years").
String experienceLabel(String code) => switch (code) {
  '0-1' => 'Less than 1 year',
  '1-2' => '1–2 years',
  '3-5' => '3–5 years',
  '5+' => '5+ years',
  _ => code,
};

/// "2 weeks ago", "1 month ago" for review dates.
String timeAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final elapsed = (now ?? DateTime.now()).difference(at);
  String unit(int n, String name) => '$n $name${n == 1 ? '' : 's'} ago';
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return unit(elapsed.inMinutes, 'minute');
  if (elapsed.inDays < 1) return unit(elapsed.inHours, 'hour');
  if (elapsed.inDays < 7) return unit(elapsed.inDays, 'day');
  if (elapsed.inDays < 30) return unit(elapsed.inDays ~/ 7, 'week');
  if (elapsed.inDays < 365) return unit(elapsed.inDays ~/ 30, 'month');
  return unit(elapsed.inDays ~/ 365, 'year');
}
