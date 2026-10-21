import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

// ── Model ──────────────────────────────────────────────────────────────────

class BookingDetail {
  final int bookingId;
  final String requestId;
  final String receivedAgo;
  final String subject;
  final String date;
  final String startTime;
  final String endTime;
  final String durationLabel;
  final String status;
  final String? studentNote;
  final String platform;
  final String? sessionLink;

  final String studentName;
  final String? studentPhotoUrl;
  final String? studentUniversity;
  final String? studentYear;
  final double studentRating;
  final String? studentMajor;
  final String? studentFocus;

  final bool isRecurring;
  final String? recurringPattern;
  final List<String> nextSessions;
  final int totalSessions;
  final String? totalHours;

  const BookingDetail({
    required this.bookingId,
    required this.requestId,
    required this.receivedAgo,
    required this.subject,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.durationLabel,
    required this.status,
    this.studentNote,
    required this.platform,
    this.sessionLink,
    required this.studentName,
    this.studentPhotoUrl,
    this.studentUniversity,
    this.studentYear,
    required this.studentRating,
    this.studentMajor,
    this.studentFocus,
    required this.isRecurring,
    this.recurringPattern,
    this.nextSessions = const [],
    required this.totalSessions,
    this.totalHours,
  });

  factory BookingDetail.fromJson(Map<String, dynamic> j) => BookingDetail(
        bookingId: int.tryParse(j['bookingId']?.toString() ?? '') ?? 0,
        requestId: j['requestId']?.toString() ?? '',
        receivedAgo: j['receivedAgo']?.toString() ?? '',
        subject: j['subject']?.toString() ?? '',
        date: j['date']?.toString() ?? '',
        startTime: j['startTime']?.toString() ?? '',
        endTime: j['endTime']?.toString() ?? '',
        durationLabel: j['durationLabel']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        studentNote: j['studentNote']?.toString(),
        platform: j['platform']?.toString() ?? 'online',
        sessionLink: j['sessionLink']?.toString(),
        studentName: j['studentName']?.toString() ?? '',
        studentPhotoUrl: j['studentPhotoUrl']?.toString(),
        studentUniversity: j['studentUniversity']?.toString(),
        studentYear: j['studentYear']?.toString(),
        studentRating:
            double.tryParse(j['studentRating']?.toString() ?? '') ?? 0.0,
        studentMajor: j['studentMajor']?.toString(),
        studentFocus: j['studentFocus']?.toString(),
        isRecurring: j['isRecurring'] == true,
        recurringPattern: j['recurringPattern']?.toString(),
        nextSessions: (j['nextSessions'] as List?)
                ?.map((s) => s.toString())
                .toList() ??
            [],
        totalSessions:
            int.tryParse(j['totalSessions']?.toString() ?? '') ?? 0,
        totalHours: j['totalHours']?.toString(),
      );
}

// ── Service ────────────────────────────────────────────────────────────────

class TutorBookingService {
  static String get _base =>
      kIsWeb ? 'http://localhost:8080' : 'http://10.0.2.2:8080';

  static Future<BookingDetail> fetchBooking(int bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    final res = await http.get(
      Uri.parse('$_base/tutor/bookings/$bookingId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load booking (${res.statusCode})');
    }
    return BookingDetail.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<void> declineBooking(int bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    final res = await http.patch(
      Uri.parse('$_base/tutor/bookings/$bookingId/decline'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to decline booking (${res.statusCode})');
    }
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
      final b = await TutorBookingService.fetchBooking(widget.bookingId);
      if (mounted) setState(() { _booking = b; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _decline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Booking',
            style: TextStyle(color: _text1)),
        content: const Text(
            'Are you sure you want to decline this booking request?',
            style: TextStyle(color: _text3)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _text3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline',
                style: TextStyle(color: _red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _declining = true);
    try {
      await TutorBookingService.declineBooking(widget.bookingId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _declining = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline: $e'),
            backgroundColor: _red,
          ),
        );
      }
    }
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
              const SizedBox(height: 20),
              _buildDeclineButton(),
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
            child: const Icon(Icons.person, color: _white, size: 18),
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
      case 'pending':   return const Color(0xFFD97706);
      case 'declined':  return _red;
      default:          return _text3;
    }
  }

  Color _statusBg(String s) {
    switch (s.toLowerCase()) {
      case 'confirmed':
      case 'accepted':  return const Color(0xFFF0FDF4);
      case 'pending':   return const Color(0xFFFFFBEB);
      case 'declined':  return _redBg;
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
                    Text(b.studentName,
                        style: const TextStyle(
                            color: _text1,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    if (b.studentUniversity != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${b.studentUniversity}${b.studentYear != null ? ' · ${b.studentYear}' : ''}',
                        style: const TextStyle(
                            color: _text3, fontSize: 12),
                      ),
                    ],
                    if (b.studentRating > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFF59E0B), size: 14),
                          const SizedBox(width: 3),
                          Text(b.studentRating.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: _text1,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (b.studentMajor != null || b.studentFocus != null) ...[
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
            if (b.studentMajor != null)
              _detailRow(Icons.school_outlined, b.studentMajor!),
            if (b.studentFocus != null) ...[
              const SizedBox(height: 6),
              _detailRow(Icons.lightbulb_outline, b.studentFocus!),
            ],
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
            const Text('Next 4 sessions',
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
                  Text('Cancel',
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
