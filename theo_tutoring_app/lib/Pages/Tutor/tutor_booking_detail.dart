import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tutor_api.dart';
import 'tutor_format.dart';
import 'tutor_theme.dart';
import 'tutor_format.dart' as fmt; // the durationLabel field hides the function

// ── Model ──────────────────────────────────────────────────────────────────

class BookingDetail {
  final int bookingId;
  final String requestId;
  final String receivedAgo;
  final String subject;
  final String rawDate; // "2026-10-24"
  final String date;
  final String startTime;
  final String endTime;
  final int durationMinutes;
  final String durationLabel;
  final String status;
  final String? studentNote;
  final String? sessionLink;
  final bool canCancel; // shows the Cancel and Reschedule buttons

  final String studentName;
  final String? studentPhotoUrl;
  final String? studentYear;
  final String? studentMajor;
  final bool studentVerified;
  final String? studentUniversity; // null if they never gave one
  final double? studentRating; // their average rating of this tutor
  final int studentReviewCount; // how many reviews that average is from

  final bool isRecurring;
  final String? recurringPattern;
  final List<String> nextSessions; // "23 Oct", "30 Oct", ...
  final String? recurringTime; // "10:00 – 11:00"
  final int totalSessions;
  final String? totalHours;

  final String? tutorName;
  final String? tutorPhotoUrl;

  /// Same rule as the Schedule page: the tutor's Meet room opens in one tap
  /// for a lesson that is going ahead.
  bool get canJoin =>
      sessionLink != null &&
      sessionLink!.isNotEmpty &&
      (status == 'Confirmed' || status == 'Postponed');

  const BookingDetail({
    required this.bookingId,
    required this.requestId,
    required this.receivedAgo,
    required this.subject,
    required this.rawDate,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.durationLabel,
    required this.status,
    this.studentNote,
    this.sessionLink,
    required this.canCancel,
    required this.studentName,
    this.studentPhotoUrl,
    this.studentYear,
    this.studentMajor,
    required this.studentVerified,
    this.studentUniversity,
    this.studentRating,
    this.studentReviewCount = 0,
    required this.isRecurring,
    this.recurringPattern,
    this.nextSessions = const [],
    this.recurringTime,
    required this.totalSessions,
    this.totalHours,
    this.tutorName,
    this.tutorPhotoUrl,
  });

  // GET /TutorLandingpage/bookings/<id> sends
  // { tutor, booking, student, recurring (null for a one-off session) }
  factory BookingDetail.fromJson(Map<String, dynamic> j) {
    final b = j['booking'] as Map<String, dynamic>? ?? const {};
    final s = j['student'] as Map<String, dynamic>? ?? const {};
    final r = j['recurring'] as Map<String, dynamic>?;
    final t = j['tutor'] as Map<String, dynamic>?;
    final received = b['receivedMinutesAgo'] as int?;
    final minutes = b['durationMinutes'] as int? ?? 0;
    final totalMinutes = r?['totalMinutes'] as int?;
    final rawDate = b['date']?.toString() ?? '';

    return BookingDetail(
      bookingId: b['bookingId'] as int? ?? 0,
      requestId: b['reference']?.toString() ?? '',
      receivedAgo: received == null ? '' : timeAgo(received),
      subject: b['subject']?.toString() ?? '',
      rawDate: rawDate,
      date: formatLongDate(rawDate),
      startTime: b['startTime']?.toString() ?? '',
      endTime: b['endTime']?.toString() ?? '',
      durationMinutes: minutes,
      durationLabel: fmt.durationLabel(minutes),
      status: b['status']?.toString() ?? '',
      studentNote: b['note']?.toString(),
      sessionLink: b['link']?.toString(),
      canCancel: b['canCancel'] == true,
      studentName: s['name']?.toString() ?? '',
      studentPhotoUrl: s['profilePhotoUrl']?.toString(),
      studentYear: _yearLabel(s['year']?.toString()),
      studentMajor: s['course']?.toString(),
      studentVerified: s['verified'] == true,
      studentUniversity: (s['university']?.toString().trim().isEmpty ?? true)
          ? null
          : s['university'].toString().trim(),
      studentRating: (s['rating'] as num?)?.toDouble(),
      studentReviewCount: (s['reviewCount'] as num?)?.toInt() ?? 0,
      isRecurring: r != null,
      recurringPattern: r == null
          ? null
          : 'Every ${r['weekday']} (${r['frequency'] ?? 'Weekly'})',
      recurringTime: r == null ? null : '${r['startTime']} – ${r['endTime']}',
      nextSessions: [
        for (final session in r?['sessions'] as List<dynamic>? ?? [])
          formatLongDate((session as Map<String, dynamic>)['date']?.toString()),
      ],
      totalSessions: r?['totalSessions'] as int? ?? 0,
      totalHours:
          totalMinutes == null ? null : fmt.durationLabel(totalMinutes),
      tutorName: t?['name']?.toString(),
      tutorPhotoUrl: t?['profilePhotoUrl']?.toString(),
    );
  }
}

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdaysLong = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

// "2026-10-23" -> "Friday, 23 October 2026"
String _fullDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_weekdaysLong[d.weekday - 1]}, ${d.day} '
      '${_monthsLong[d.month - 1]} ${d.year}';
}

// The year of study as saved at registration: "3" -> "Year 3",
// "Sophomore" stays as it is.
String? _yearLabel(String? year) {
  final y = year?.trim();
  if (y == null || y.isEmpty) return null;
  return int.tryParse(y) != null ? 'Year $y' : y;
}

// ── Screen ────────────────────────────────────────────────────────────────

class TutorBookingDetailScreen extends StatefulWidget {
  final int bookingId;

  /// Loads the booking; tests pass their own.
  final Future<Map<String, dynamic>> Function(int bookingId) loadBooking;

  /// The Cancel and Reschedule buttons' requests; tests pass their own.
  final Future<Map<String, dynamic>> Function(int bookingId) cancelBooking;
  final Future<Map<String, dynamic>> Function(int bookingId) rescheduleBooking;

  const TutorBookingDetailScreen({
    super.key,
    required this.bookingId,
    this.loadBooking = fetchTutorBooking,
    this.cancelBooking = cancelTutorBooking,
    this.rescheduleBooking = rescheduleTutorBooking,
  });

  @override
  State<TutorBookingDetailScreen> createState() =>
      _TutorBookingDetailScreenState();
}

class _TutorBookingDetailScreenState extends State<TutorBookingDetailScreen> {
  BookingDetail? _booking;
  bool _loading = true;
  String? _error;
  bool _sending = false; // a Cancel or Reschedule request is on its way

  // Light palette matching screenshot
  static const _white  = Colors.white; // text and icons on blue
  static const _blue   = Color(0xFF246BFE);
  static const _red    = Color(0xFFDC2626);

  // Light colours, or the dark ones when the tutor turned on Dark Mode
  bool get _dk => context.tutorDark;
  Color get _bg => _dk ? TutorDark.background : const Color(0xFFF5F7FA);
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _fill => _dk ? TutorDark.cardAlt : const Color(0xFFF1F3F6);
  Color get _blueBg => _dk ? TutorDark.blueTint : const Color(0xFFEEF2FF);
  Color get _text1 => _dk ? TutorDark.text : const Color(0xFF111827);
  Color get _text2 => _dk ? TutorDark.textSecondary : const Color(0xFF374151);
  Color get _text3 => _dk ? TutorDark.textMuted : const Color(0xFF6B7280);
  Color get _text4 => _dk ? TutorDark.textFaint : const Color(0xFF9CA3AF);
  Color get _border => _dk ? TutorDark.border : const Color(0xFFE5E7EB);
  Color get _redText => _dk ? TutorDark.redText : _red;
  Color get _redBg => _dk ? TutorDark.redTint : const Color(0xFFFEF2F2);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final b = BookingDetail.fromJson(
          await widget.loadBooking(widget.bookingId));
      if (mounted) setState(() { _booking = b; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // The Cancel button: "Are you sure?", then the session is cancelled and
  // the student gets a "Session cancelled" notification.
  Future<void> _cancel() => _confirmAndSend(
        title: 'Cancel this session?',
        message: 'Are you sure you want to cancel the meeting with '
            '${_booking!.studentName}? The student will be notified.',
        noLabel: 'No, keep it',
        yesLabel: 'Yes, cancel',
        yesColor: _red,
        send: widget.cancelBooking,
        done: 'Session cancelled. The student has been notified.',
      );

  // The Reschedule button: the session is cancelled and the student is
  // asked to book a new time with this tutor.
  Future<void> _reschedule() => _confirmAndSend(
        title: 'Reschedule this session?',
        message: 'Pressing this button will allow the student to book '
            'another session.',
        noLabel: 'Not now',
        yesLabel: 'Reschedule',
        yesColor: _blue,
        send: widget.rescheduleBooking,
        done: 'The student has been asked to book a new time.',
      );

  Future<void> _confirmAndSend({
    required String title,
    required String message,
    required String noLabel,
    required String yesLabel,
    required Color yesColor,
    required Future<Map<String, dynamic>> Function(int bookingId) send,
    required String done,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text(title, style: TextStyle(color: _text1)),
        content: Text(message, style: TextStyle(color: _text3, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(noLabel, style: TextStyle(color: _text3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yesLabel,
                style: TextStyle(
                    color: _dk && yesColor == _red ? _redText : yesColor,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _sending = true);
    try {
      await send(_booking!.bookingId);
      if (!mounted) return;
      _showMessage(done);
      Navigator.pop(context, true); // the Schedule page reloads
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _showMessage(e.toString(), error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? _red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _blue))
                  : _error != null
                      ? _buildError()
                      : _buildContent(b!),
            ),
          ],
        ),
      ),
      // Reschedule and Cancel stay at the bottom of the screen
      bottomNavigationBar:
          b != null && b.canCancel && !_loading && _error == null
              ? _buildActionBar()
              : null,
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: _text4, size: 40),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: _text3, fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue, foregroundColor: _white),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BookingDetail b) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        _buildMetaRow(b),
        const SizedBox(height: 12),
        _buildSessionCard(b),
        const SizedBox(height: 14),
        _buildStudentCard(b),
        const SizedBox(height: 14),
        b.isRecurring ? _buildRecurringCard(b) : _buildNoRecurringCard(),
      ],
    );
  }

  // ── Header: back, "THEO TUTORING / Schedule", tutor photo ─────────────────

  Widget _buildHeader() {
    final b = _booking;
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_rounded, color: _text1),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('THEO TUTORING',
                    style: TextStyle(
                        color: _blue,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
                Text('Schedule',
                    style: GoogleFonts.libreBaskerville(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _text1)),
              ],
            ),
          ),
          CircleAvatar(
            radius: 20,
            backgroundColor: _blue,
            backgroundImage: b?.tutorPhotoUrl != null
                ? NetworkImage(b!.tutorPhotoUrl!)
                : null,
            child: b?.tutorPhotoUrl != null
                ? null
                : b?.tutorName != null
                    ? Text(initialsOf(b!.tutorName!),
                        style: const TextStyle(
                            color: _white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700))
                    : const Icon(Icons.person, color: _white, size: 20),
          ),
        ],
      ),
    );
  }

  // ── "• ID #REQ-41   Received 3h ago" ··· status ──────────────────────────

  Widget _buildMetaRow(BookingDetail b) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    color: _text3, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('ID #${b.requestId}',
                  style: TextStyle(
                      color: _text2,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: b.receivedAgo.isEmpty
              ? const SizedBox.shrink()
              : Text('Received ${b.receivedAgo}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _text3, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _statusBg(b.status),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(b.status,
              style: TextStyle(
                  color: _statusColor(b.status),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'confirmed':
      case 'accepted':
        return _dk ? TutorDark.greenText : const Color(0xFF16A34A);
      case 'pending':
      case 'postponed':
        return _dk ? TutorDark.amberText : const Color(0xFFD97706);
      case 'declined':
      case 'cancelled': return _redText;
      default:          return _text3;
    }
  }

  Color _statusBg(String s) {
    switch (s.toLowerCase()) {
      case 'confirmed':
      case 'accepted':
        return _dk ? TutorDark.greenTint : const Color(0xFFF0FDF4);
      case 'pending':
      case 'postponed':
        return _dk ? TutorDark.amberTint : const Color(0xFFFFFBEB);
      case 'declined':
      case 'cancelled': return _redBg;
      default:          return _dk ? TutorDark.cardAlt : const Color(0xFFF3F4F6);
    }
  }

  // ── Session: subject, date, time, and the student's note inside ──────────

  Widget _buildSessionCard(BookingDetail b) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(b.subject.toUpperCase(),
                style: TextStyle(
                    color: _text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
          ),
          const SizedBox(height: 12),
          Text(_fullDate(b.rawDate),
              style: GoogleFonts.libreBaskerville(
                  color: _text1, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 17, color: _blue),
              const SizedBox(width: 8),
              Text('${b.startTime} – ${b.endTime}',
                  style: TextStyle(
                      color: _text1,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              if (b.durationLabel.isNotEmpty)
                Text('  (${b.durationLabel})',
                    style: TextStyle(color: _text3, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          _buildJoinButton(b),
          // The note the student wrote when booking, as on the Schedule page
          ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _fill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.format_quote_rounded,
                          color: _text4, size: 18),
                      SizedBox(width: 4),
                      Text('STUDENT NOTE',
                          style: TextStyle(
                              color: _text3,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (b.studentNote != null && b.studentNote!.trim().isNotEmpty)
                    Text('"${b.studentNote!.trim()}"',
                        style: TextStyle(
                            color: _text2,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            height: 1.55))
                  else
                    Text('No note from the student.',
                        style: TextStyle(
                            color: _text4,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            height: 1.55)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Join session: opens the tutor's own Google Meet room ─────────────────

  Widget _buildJoinButton(BookingDetail b) {
    final hasLink = b.sessionLink != null && b.sessionLink!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: b.canJoin ? () => _joinSession(b.sessionLink!) : null,
            icon: const Icon(Icons.videocam_outlined, size: 18),
            label: const Text('Join session',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: _white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        if (!hasLink) ...[
          const SizedBox(height: 6),
          Text('Session link not added yet',
              style: TextStyle(color: _text3, fontSize: 12)),
        ],
      ],
    );
  }

  Future<void> _joinSession(String link) async {
    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Meet could not be opened.')),
      );
    }
  }

  // ── Student: photo with a verified tick, name, year, major & focus ───────

  Widget _buildStudentCard(BookingDetail b) {
    final photo = b.studentPhotoUrl;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: _blueBg,
                    backgroundImage:
                        photo != null ? NetworkImage(photo) : null,
                    child: photo == null
                        ? Text(initialsOf(b.studentName),
                            style: const TextStyle(
                                color: _blue,
                                fontSize: 15,
                                fontWeight: FontWeight.w700))
                        : null,
                  ),
                  if (b.studentVerified)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: _blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: _surface, width: 2),
                        ),
                        child: const Icon(Icons.check_rounded,
                            size: 10, color: _white),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.studentName,
                        style: GoogleFonts.libreBaskerville(
                            color: _text1,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    if (b.studentYear != null) ...[
                      const SizedBox(height: 3),
                      Text(b.studentYear!,
                          style:
                              TextStyle(color: _text3, fontSize: 13)),
                    ],
                    const SizedBox(height: 6),
                    _buildStudentRating(b),
                  ],
                ),
              ),
            ],
          ),
          // The student's university
          const SizedBox(height: 14),
          Divider(color: _border, height: 1),
          const SizedBox(height: 14),
          _infoRow(
            icon: Icons.account_balance_outlined,
            label: 'UNIVERSITY',
            value: b.studentUniversity ?? 'Not provided',
            muted: b.studentUniversity == null,
          ),
          if (b.studentMajor != null) ...[
            const SizedBox(height: 12),
            _infoRow(
              icon: Icons.school_outlined,
              label: 'MAJOR & FOCUS',
              value: b.studentMajor!,
            ),
          ],
        ],
      ),
    );
  }

  // "★ 4.5  from 2 reviews of you", or "No rating from this student yet"
  Widget _buildStudentRating(BookingDetail b) {
    final rating = b.studentRating;
    if (rating == null || b.studentReviewCount == 0) {
      return Text('No rating from this student yet',
          style: TextStyle(color: _text4, fontSize: 12));
    }
    final count = b.studentReviewCount;
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
        const SizedBox(width: 3),
        Text(rating.toStringAsFixed(1),
            style: TextStyle(
                color: _text1, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Flexible(
          child: Text('from $count review${count == 1 ? '' : 's'} of you',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _text3, fontSize: 12)),
        ),
      ],
    );
  }

  // One labelled line in the student card, e.g. UNIVERSITY / Wits
  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    bool muted = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _text3),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: _text4,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      color: muted ? _text4 : _text1,
                      fontSize: 13,
                      fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
                      fontStyle: muted ? FontStyle.italic : FontStyle.normal)),
            ],
          ),
        ),
      ],
    );
  }

  // ── No recurring booking: says so in the same small section ─────────────

  Widget _buildNoRecurringCard() {
    return _card(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.sync_disabled_rounded,
                color: _text3, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recurring Booking',
                    style: TextStyle(
                        color: _text1,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('There are no recurring bookings currently.',
                    style: TextStyle(color: _text3, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Recurring Booking: pattern, next sessions, total ─────────────────────

  Widget _buildRecurringCard(BookingDetail b) {
    final next = b.nextSessions.take(4).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _blueBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.sync_rounded, color: _blue, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Recurring Booking',
                    style: TextStyle(
                        color: _text1,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _dk ? TutorDark.blueTint : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Weekly',
                    style: TextStyle(
                        color: _dk ? TutorDark.blueText : const Color(0xFF0369A1),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _fill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (b.recurringPattern != null)
                  Row(
                    children: [
                      Text('Pattern:',
                          style: TextStyle(color: _text3, fontSize: 13)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(b.recurringPattern!,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: _text1,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                if (next.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Next ${next.length} sessions: ${next.join(', ')}'
                    '${b.recurringTime != null ? ' (${b.recurringTime})' : ''}',
                    style: TextStyle(
                        color: _text2, fontSize: 13, height: 1.5),
                  ),
                ],
                const SizedBox(height: 10),
                Divider(color: _border, height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Total Scheduled:',
                        style: TextStyle(color: _text3, fontSize: 13)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        b.totalHours != null
                            ? '${b.totalSessions} Sessions • ${b.totalHours}'
                            : '${b.totalSessions} Sessions',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: _text1,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Reschedule and Cancel buttons, pinned to the bottom ───────────────

  Widget _buildActionBar() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: _sending
            ? const SizedBox(
                height: 50,
                child: Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        color: _blue, strokeWidth: 2.5),
                  ),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      key: const Key('booking-reschedule'),
                      label: 'Reschedule',
                      icon: Icons.event_repeat_rounded,
                      color: _dk ? TutorDark.blueText : _blue,
                      background: _blueBg,
                      border: _dk ? TutorDark.border : const Color(0xFFC7D7FE),
                      onPressed: _reschedule,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _actionButton(
                      key: const Key('booking-cancel'),
                      label: 'Cancel',
                      icon: Icons.close_rounded,
                      color: _redText,
                      background: _redBg,
                      border: _dk ? TutorDark.border : const Color(0xFFFECACA),
                      onPressed: _cancel,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _actionButton({
    required Key key,
    required String label,
    required IconData icon,
    required Color color,
    required Color background,
    required Color border,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: color)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: background,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}
