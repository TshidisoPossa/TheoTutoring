import 'package:flutter/material.dart';

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
  final List<String> nextSessions;
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
      studentYear: s['year']?.toString(),
      studentMajor: s['course']?.toString(),
      studentVerified: s['verified'] == true,
      isRecurring: r != null,
      recurringPattern: r == null
          ? null
          : 'Every ${r['weekday']} (${r['frequency'] ?? 'Weekly'})',
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

  // Declining does not cancel the session: the tutor picks a new date and
  // start time (same length as before) and the student must confirm it.
  Future<void> _decline() async {
    final b = _booking!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Booking',
            style: TextStyle(color: _text1)),
        content: const Text(
            'Declining moves this session to a new time. The student will be '
            'asked to confirm the new time.',
            style: TextStyle(color: _text3)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _text3)),
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
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _blue))
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
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

  Widget _buildContent() {
    final b = _booking!;
    return Column(
      children: [
        _buildHeader(b),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildRequestBadge(b),
              const SizedBox(height: 12),
              _buildSessionInfo(b),
              const SizedBox(height: 12),
              if (b.studentNote != null && b.studentNote!.isNotEmpty) ...[
                _buildStudentNote(b.studentNote!),
                const SizedBox(height: 12),
              ],
              _buildStudentCard(b),
              if (b.isRecurring) ...[
                const SizedBox(height: 12),
                _buildRecurringSection(b),
              ],
              if (b.canPostpone) ...[
                const SizedBox(height: 20),
                _buildDeclineButton(),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BookingDetail b) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: _text1, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Schedule',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _text1)),
          ),
          const Icon(Icons.notifications_outlined,
              color: _text3, size: 22),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 18,
            backgroundColor: _blue,
            backgroundImage: b.tutorPhotoUrl != null
                ? NetworkImage(b.tutorPhotoUrl!)
                : null,
            child: b.tutorPhotoUrl != null
                ? null
                : b.tutorName != null
                    ? Text(initialsOf(b.tutorName!),
                        style: const TextStyle(
                            color: _white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))
                    : const Icon(Icons.person, color: _white, size: 18),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {},
            child: const Icon(Icons.more_vert, color: _text3, size: 20),
          ),
        ],
      ),
    );
  }

  // ── Request Badge ─────────────────────────────────────────────────────────

  Widget _buildRequestBadge(BookingDetail b) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _blueBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'ID #${b.requestId}',
              style: const TextStyle(
                  color: _blue, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          if (b.receivedAgo.isNotEmpty)
            Text(
              'Received ${b.receivedAgo}',
              style: const TextStyle(color: _text4, fontSize: 12),
            ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      ),
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

  // ── Session Info ──────────────────────────────────────────────────────────

  Widget _buildSessionInfo(BookingDetail b) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _blueBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(b.subject.toUpperCase(),
                style: const TextStyle(
                    color: _blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ),
          const SizedBox(height: 10),
          // Date bold large
          Text(b.date,
              style: const TextStyle(
                  color: _text1,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          // Time + duration badge
          Row(
            children: [
              const Icon(Icons.access_time_outlined,
                  size: 15, color: _text4),
              const SizedBox(width: 6),
              Text('${b.startTime} – ${b.endTime}',
                  style: const TextStyle(
                      color: _text2,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _blueBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(b.durationLabel,
                    style: const TextStyle(
                        color: _blue, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Student Note ──────────────────────────────────────────────────────────

  Widget _buildStudentNote(String note) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('STUDENT NOTE',
              style: TextStyle(
                  color: _text4,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.format_quote, color: _blue, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(note,
                    style: const TextStyle(
                        color: _text3,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        height: 1.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Student Card ──────────────────────────────────────────────────────────

  Widget _buildStudentCard(BookingDetail b) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage: b.studentPhotoUrl != null
                    ? NetworkImage(b.studentPhotoUrl!)
                    : null,
                backgroundColor: _blueBg,
                child: b.studentPhotoUrl == null
                    ? const Icon(Icons.person, color: _blue, size: 26)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(b.studentName,
                              style: const TextStyle(
                                  color: _text1,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (b.studentVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded,
                              color: _blue, size: 16),
                        ],
                      ],
                    ),
                    if (b.studentYear != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        b.studentYear!,
                        style: const TextStyle(
                            color: _text3, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (b.studentMajor != null) ...[
            const SizedBox(height: 14),
            const Divider(color: _border, height: 1),
            const SizedBox(height: 12),
            const Text('MAJOR & FOCUS',
                style: TextStyle(
                    color: _text4,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            _detailRow(Icons.school_outlined, b.studentMajor!),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _text4),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: _text2,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  // ── Recurring Section ─────────────────────────────────────────────────────

  Widget _buildRecurringSection(BookingDetail b) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.repeat_rounded, color: _blue, size: 16),
              const SizedBox(width: 6),
              const Text('Recurring Booking',
                  style: TextStyle(
                      color: _text1,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (b.recurringPattern != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: _blueBg,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(b.recurringPattern!,
                      style: const TextStyle(
                          color: _blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (b.recurringPattern != null) ...[
            _recurringRow('Pattern', b.recurringPattern!),
            const SizedBox(height: 10),
          ],
          // Next sessions list
          if (b.nextSessions.isNotEmpty) ...[
            Text('Next ${b.nextSessions.length.clamp(0, 4)} sessions',
                style: TextStyle(
                    color: _text4,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...b.nextSessions.take(4).map((session) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 13, color: _text4),
                      const SizedBox(width: 8),
                      Text(session,
                          style: const TextStyle(
                              color: _text2, fontSize: 13)),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
          ],
          const Divider(color: _border, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Scheduled',
                  style: TextStyle(color: _text3, fontSize: 13)),
              Text(
                b.totalHours != null
                    ? '${b.totalSessions} Sessions · ${b.totalHours}'
                    : '${b.totalSessions} Sessions',
                style: const TextStyle(
                    color: _text1,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recurringRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(color: _text4, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: _text2,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  // ── Decline Button ────────────────────────────────────────────────────────

  Widget _buildDeclineButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _declining ? null : _decline,
        style: OutlinedButton.styleFrom(
          foregroundColor: _red,
          backgroundColor: _redBg,
          side: const BorderSide(color: Color(0xFFFECACA)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _declining
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    color: _red, strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.close, size: 16, color: _red),
                  SizedBox(width: 8),
                  Text('Decline',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _red)),
                ],
              ),
      ),
    );
  }
}
