import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// ── Models ────────────────────────────────────────────────────────────────────

class DashboardSession {
  final int bookingId;
  final String timeRange;
  final String subject;
  final String studentName;
  final String colorHex;
  final String? note;        // e.g. "Zoom Meeting" / "Topic: Functions & Loops"
  final String? platform;    // e.g. "zoom" | "code" | "document" | "video"
  final String? startsIn;    // e.g. "In 45 min" | "In 2.5 hrs"

  DashboardSession({
    required this.bookingId,
    required this.timeRange,
    required this.subject,
    required this.studentName,
    required this.colorHex,
    this.note,
    this.platform,
    this.startsIn,
  });

  factory DashboardSession.fromJson(Map<String, dynamic> j) => DashboardSession(
        bookingId: int.tryParse(j['bookingId']?.toString() ??
                j['booking_id']?.toString() ?? '0') ?? 0,
        timeRange: j['timeRange']?.toString() ??
            j['time_range']?.toString() ??
            j['time']?.toString() ?? '',
        subject: j['subject']?.toString() ?? '',
        studentName: j['studentName']?.toString() ??
            j['student_name']?.toString() ?? 'Student',
        colorHex: j['color']?.toString() ?? '#246BFE',
        note: j['note']?.toString() ?? j['topic']?.toString(),
        platform: j['platform']?.toString(),
        startsIn: j['startsIn']?.toString() ?? j['starts_in']?.toString(),
      );

  Color get color {
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF246BFE);
    }
  }
}

class DashboardData {
  final int activeStudents;
  final int upcomingToday;
  final List<DashboardSession> todaySchedule;
  final String tutorName;
  final String? tutorPhotoUrl;
  final String tutorInitials;
  final int unreadNotifications;

  DashboardData({
    required this.activeStudents,
    required this.upcomingToday,
    required this.todaySchedule,
    required this.tutorName,
    this.tutorPhotoUrl,
    required this.tutorInitials,
    required this.unreadNotifications,
  });

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final tutor = j['tutor'] as Map<String, dynamic>?;
    final name = tutor?['name']?.toString() ??
        j['tutorName']?.toString() ??
        j['tutor_name']?.toString() ?? '';
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : name.isNotEmpty ? name[0].toUpperCase() : 'T';
    return DashboardData(
      activeStudents: int.tryParse(
              (j['activeStudents'] ?? j['active_students'] ?? 0).toString()) ?? 0,
      upcomingToday: int.tryParse(
              (j['upcomingToday'] ?? j['upcoming_today'] ?? 0).toString()) ?? 0,
      todaySchedule:
          ((j['todaysSchedule'] ?? j['todaySchedule'] ?? j['today_schedule'])
                      as List<dynamic>? ??
                  [])
              .map((e) => DashboardSession.fromJson(e as Map<String, dynamic>))
              .toList(),
      tutorName: name,
      tutorPhotoUrl: tutor?['photoUrl']?.toString() ??
          j['tutorPhotoUrl']?.toString() ??
          j['tutor_photo_url']?.toString(),
      tutorInitials: initials,
      unreadNotifications: int.tryParse(
              (j['unreadNotifications'] ?? j['unread_notifications'] ?? 0)
                  .toString()) ?? 0,
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class TutorDashboardService {
  static String get _base =>
      kIsWeb ? 'http://localhost:8080' : 'http://10.0.2.2:8080';

  static Future<DashboardData> fetchDashboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    final res = await http.get(
      Uri.parse('$_base/TutorLandingpage'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load dashboard: ${res.statusCode}');
    }
    return DashboardData.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TutorDashboard extends StatefulWidget {
  const TutorDashboard({super.key});

  @override
  State<TutorDashboard> createState() => _TutorDashboardState();
}

class _TutorDashboardState extends State<TutorDashboard> {
  DashboardData? _data;
  bool _loading = true;
  String? _error;

  static const _blue = Color(0xFF246BFE);
  static const _bg   = Color(0xFFF2F4F8);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await TutorDashboardService.fetchDashboard();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
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
                : RefreshIndicator(
                    onRefresh: _load,
                    color: _blue,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTopBar(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                _buildTitle(),
                                const SizedBox(height: 20),
                                _buildStatsRow(),
                                const SizedBox(height: 24),
                                _buildTodaySchedule(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_error ?? 'Something went wrong',
                style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Retry', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TOP BAR ──────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final hasNotif = (_data?.unreadNotifications ?? 0) > 0;
    final initials = _data?.tutorInitials ?? 'AT';
    final photoUrl  = _data?.tutorPhotoUrl;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Brand name
          Expanded(
            child: Text(
              'Theo Tutoring',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ),

          // Bell icon
          Stack(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_outlined,
                    color: Color(0xFF1A1A2E), size: 24),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              if (hasNotif)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFFE53935), shape: BoxShape.circle),
                  ),
                ),
            ],
          ),

          const SizedBox(width: 4),

          // Avatar with initials / photo
          CircleAvatar(
            radius: 20,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            backgroundColor: _blue,
            child: photoUrl == null
                ? Text(initials,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700))
                : null,
          ),
        ],
      ),
    );
  }

  // ── TITLE ─────────────────────────────────────────────────────────────────────

  Widget _buildTitle() {
    return Text(
      'Dashboard',
      style: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF1A1A2E),
      ),
    );
  }

  // ── STATS ROW ─────────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    final activeStudents = _data?.activeStudents ?? 0;
    final upcomingToday  = _data?.upcomingToday  ?? 0;

    return Row(
      children: [
        // Active Students — white card
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        color: Color(0xFF9CA3AF), size: 20),
                    const SizedBox(width: 6),
                    Text('Active Students',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$activeStudents',
                  style: GoogleFonts.inter(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Upcoming Today — blue card
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            decoration: BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 6),
                    Text('Upcoming Today',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$upcomingToday',
                  style: GoogleFonts.inter(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── TODAY'S SCHEDULE ──────────────────────────────────────────────────────────

  Widget _buildTodaySchedule() {
    final sessions = _data?.todaySchedule ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Text(
              "Today's Schedule",
              style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A2E)),
            ),
            const SizedBox(width: 8),
            if (sessions.isNotEmpty)
              Text(
                '${sessions.length} session${sessions.length > 1 ? 's' : ''}',
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFF9CA3AF)),
              ),
            const Spacer(),
            // + button
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: _blue, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (sessions.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('No sessions today',
                style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 13)),
          )
        else
          ...sessions.map((s) => _scheduleCard(s)),
      ],
    );
  }

  Widget _scheduleCard(DashboardSession session) {
    // Determine platform icon
    IconData platformIcon;
    switch ((session.platform ?? '').toLowerCase()) {
      case 'zoom':
      case 'video':
      case 'meet':
        platformIcon = Icons.videocam_outlined;
        break;
      case 'code':
        platformIcon = Icons.code;
        break;
      case 'document':
      case 'doc':
        platformIcon = Icons.description_outlined;
        break;
      default:
        platformIcon = Icons.videocam_outlined;
    }

    // Parse "In X hrs/min" badge colour: orange for < 1 hr, green for >= 1 hr
    final startsIn = session.startsIn ?? '';
    Color badgeColor = const Color(0xFFF59E0B); // amber default
    if (startsIn.contains('hr') || startsIn.contains('hrs')) {
      badgeColor = const Color(0xFF10B981); // green
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coloured left border strip
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: session.color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: time (blue bold) + "In X hrs" badge
                    Row(
                      children: [
                        Text(
                          session.timeRange,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _blue,
                          ),
                        ),
                        const Spacer(),
                        if (startsIn.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              startsIn,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: badgeColor,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Row 2: subject + platform icon button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.subject,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A1A2E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'with ${session.studentName}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Platform icon in a light grey rounded square
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(platformIcon,
                              size: 18, color: const Color(0xFF6B7280)),
                        ),
                      ],
                    ),

                    // Row 3: note / topic (if present)
                    if (session.note != null && session.note!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 6, color: Color(0xFF10B981)),
                          const SizedBox(width: 5),
                          Text(
                            session.note!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: _blue,
        unselectedItemColor: const Color(0xFF9CA3AF),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (_) {},
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inbox_rounded), label: 'Schedule'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}
