import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tutor_api.dart';
import 'tutor_format.dart';
import 'tutor_format.dart' as fmt; // the durationLabel field hides the function

// ── Model ──────────────────────────────────────────────────────────────────

class BookingDetail {
  final int bookingId;
  final String requestId;
  final String receivedAgo;
  final String subject;
  final String rawDate; // "2026-10-24", used by the postpone date picker
  final String date;
  final String startTime;
  final String endTime;
  final int durationMinutes;
  final String durationLabel;
  final String status;
  final String? studentNote;
  final String? sessionLink;
  final bool canPostpone; // shows the Decline button

  final String studentName;
  final String? studentPhotoUrl;
  final String? studentYear;
  final String? studentMajor;
  final bool studentVerified;

  final bool isRecurring;
  final String? recurringPattern;
  final List<String> nextSessions; // "23 Oct", "30 Oct", ...
  final String? recurringTime; // "10:00 – 11:00"
  final int totalSessions;
  final String? totalHours;

  final String? tutorName;
  final String? tutorPhotoUrl;

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
    required this.canPostpone,
    required this.studentName,
    this.studentPhotoUrl,
    this.studentYear,
    this.studentMajor,
    required this.studentVerified,
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
      canPostpone: b['canPostpone'] == true,
      studentName: s['name']?.toString() ?? '',
      studentPhotoUrl: s['profilePhotoUrl']?.toString(),
      studentYear: _yearLabel(s['year']?.toString()),
      studentMajor: s['course']?.toString(),
      studentVerified: s['verified'] == true,
      isRecurring: r != null,
      recurringPattern: r == null
          ? null
          : 'Every ${r['weekday']} (${r['frequency'] ?? 'Weekly'})',
      recurringTime: r == null ? null : '${r['startTime']} – ${r['endTime']}',
      nextSessions: [
        for (final session in r?['sessions'] as List<dynamic>? ?? [])
          _dayMonth((session as Map<String, dynamic>)['date']?.toString()),
      ],
      totalSessions: r?['totalSessions'] as int? ?? 0,
      totalHours:
          totalMinutes == null ? null : fmt.durationLabel(totalMinutes),
      tutorName: t?['name']?.toString(),
      tutorPhotoUrl: t?['profilePhotoUrl']?.toString(),
    );
  }
}

const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdaysLong = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

// "2026-10-30" -> "30 Oct"
String _dayMonth(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  return d == null ? (iso ?? '') : '${d.day} ${_monthsShort[d.month - 1]}';
}

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
  const TutorBookingDetailScreen({super.key, required this.bookingId});

  @override
  State<TutorBookingDetailScreen> createState() =>
      _TutorBookingDetailScreenState();
}

class _TutorBookingDetailScreenState extends State<TutorBookingDetailScreen> {
  BookingDetail? _booking;
  bool _loading = true;
  String? _error;
  bool _declining = false;

  // Light palette matching screenshot
  static const _bg     = Color(0xFFF5F7FA);
  static const _white  = Colors.white;
  static const _blue   = Color(0xFF246BFE);
  static const _blueBg = Color(0xFFEEF2FF);
  static const _text1  = Color(0xFF111827);
  static const _text2  = Color(0xFF374151);
  static const _text3  = Color(0xFF6B7280);
  static const _text4  = Color(0xFF9CA3AF);
  static const _border = Color(0xFFE5E7EB);
  static const _red    = Color(0xFFDC2626);
  static const _redBg  = Color(0xFFFEF2F2);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final b = BookingDetail.fromJson(
          await fetchTutorBooking(widget.bookingId));
      if (mounted) setState(() { _booking = b; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // The Cancel button. The backend does not delete the session (that would
  // need the refund rules in documentation 4.6): it moves it. The tutor
  // picks a new date and start time (same length as before) and the student
  // must confirm it.
  Future<void> _decline() async {
    final b = _booking!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this session time?',
            style: TextStyle(color: _text1)),
        content: const Text(
            'The session will be moved to a new time that you choose. The '
            'student will be asked to confirm it.',
            style: TextStyle(color: _text3)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep session', style: TextStyle(color: _text3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pick a new time',
                style: TextStyle(color: _red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = DateTime.tryParse(b.rawDate);
    final day = await showDatePicker(
      context: context,
      initialDate:
          current == null || current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      helpText: 'New session date',
    );
    if (day == null || !mounted) return;

    final parts = b.startTime.split(':');
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
      helpText: 'New start time',
    );
    if (start == null || !mounted) return;

    final length = b.durationMinutes > 0 ? b.durationMinutes : 60;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = startMinutes + length;
    if (endMinutes >= 24 * 60) {
      _showMessage('The session must end before midnight.', error: true);
      return;
    }

    String two(int n) => n.toString().padLeft(2, '0');
    String clock(int m) => '${two(m ~/ 60)}:${two(m % 60)}';
    final date = '${day.year}-${two(day.month)}-${two(day.day)}';

    setState(() => _declining = true);
    try {
      await postponeTutorBooking(
        b.bookingId,
        date: date,
        startTime: clock(startMinutes),
        endTime: clock(endMinutes),
      );
      if (!mounted) return;
      _showMessage(
          'Session moved to ${formatLongDate(date)}, ${clock(startMinutes)}. '
          'The student has been asked to confirm.');
      Navigator.pop(context, true); // the Schedule page reloads
    } catch (e) {
      if (!mounted) return;
      setState(() => _declining = false);
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
      // the Cancel button stays at the bottom of the screen
      bottomNavigationBar:
          b != null && b.canPostpone && !_loading && _error == null
              ? _buildCancelBar()
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
            const Icon(Icons.wifi_off_rounded, color: _text4, size: 40),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _text3, fontSize: 13)),
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
        if (b.isRecurring) ...[
          const SizedBox(height: 14),
          _buildRecurringCard(b),
        ],
      ],
    );
  }

  // ── Header: back, "THEO TUTORING / Schedule", tutor photo ─────────────────

  Widget _buildHeader() {
    final b = _booking;
    return Container(
      color: _white,
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: _text1),
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
            color: const Color(0xFFE8EBF0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: _text3, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('ID #${b.requestId}',
                  style: const TextStyle(
                      color: _text2,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (b.receivedAgo.isNotEmpty)
          Text('Received ${b.receivedAgo}',
              style: const TextStyle(color: _text3, fontSize: 12)),
        const Spacer(),
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
      case 'accepted':  return const Color(0xFF16A34A);
      case 'pending':
      case 'postponed': return const Color(0xFFD97706);
      case 'declined':
      case 'cancelled': return _red;
      default:          return _text3;
    }
  }

  Color _statusBg(String s) {
    switch (s.toLowerCase()) {
      case 'confirmed':
      case 'accepted':  return const Color(0xFFF0FDF4);
      case 'pending':
      case 'postponed': return const Color(0xFFFFFBEB);
      case 'declined':
      case 'cancelled': return _redBg;
      default:          return const Color(0xFFF3F4F6);
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
              color: const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(b.subject.toUpperCase(),
                style: const TextStyle(
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
                  style: const TextStyle(
                      color: _text1,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              if (b.durationLabel.isNotEmpty)
                Text('  (${b.durationLabel})',
                    style: const TextStyle(color: _text3, fontSize: 14)),
            ],
          ),
          if (b.studentNote != null && b.studentNote!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEEF0F3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
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
                  Text('"${b.studentNote!}"',
                      style: const TextStyle(
                          color: _text2,
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
                          border: Border.all(color: _white, width: 2),
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
                              const TextStyle(color: _text3, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (b.studentMajor != null) ...[
            const SizedBox(height: 14),
            const Divider(color: _border, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.school_outlined,
                      size: 16, color: _text3),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MAJOR & FOCUS',
                          style: TextStyle(
                              color: _text4,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Text(b.studentMajor!,
                          style: const TextStyle(
                              color: _text1,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
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
              const Expanded(
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
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Weekly',
                    style: TextStyle(
                        color: Color(0xFF0369A1),
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
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEEF0F3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (b.recurringPattern != null)
                  Row(
                    children: [
                      const Text('Pattern:',
                          style: TextStyle(color: _text3, fontSize: 13)),
                      const Spacer(),
                      Text(b.recurringPattern!,
                          style: const TextStyle(
                              color: _text1,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                if (next.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Next ${next.length} sessions: ${next.join(', ')}'
                    '${b.recurringTime != null ? ' (${b.recurringTime})' : ''}',
                    style: const TextStyle(
                        color: _text2, fontSize: 13, height: 1.5),
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(color: _border, height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Total Scheduled:',
                        style: TextStyle(color: _text3, fontSize: 13)),
                    const Spacer(),
                    Text(
                      b.totalHours != null
                          ? '${b.totalSessions} Sessions • ${b.totalHours}'
                          : '${b.totalSessions} Sessions',
                      style: const TextStyle(
                          color: _text1,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
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

  // ── Cancel button, pinned to the bottom ──────────────────────────────────

  Widget _buildCancelBar() {
    return Container(
      color: _white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _declining ? null : _decline,
            style: OutlinedButton.styleFrom(
              foregroundColor: _red,
              backgroundColor: _redBg,
              side: const BorderSide(color: Color(0xFFFECACA)),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _declining
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child:
                        CircularProgressIndicator(color: _red, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.close_rounded, size: 18, color: _red),
                      SizedBox(width: 8),
                      Text('Cancel',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _red)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
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
