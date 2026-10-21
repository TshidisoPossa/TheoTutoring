import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tutor_api.dart';
import 'tutor_booking_detail.dart';
import 'tutor_format.dart';
import 'tutor_nav.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class DashboardSession {
  final int bookingId;
  final int subjectId;
  final String timeRange;
  final String subject;
  final String studentName;
  final String? note;        // the student's message, e.g. "Topic: Functions"
  final String platform;     // from the session link: zoom | meet | teams | online | none
  final String? startsIn;    // e.g. "In 45 min" | "In 2.5 hrs" | "Now"

  DashboardSession({
    required this.bookingId,
    required this.subjectId,
    required this.timeRange,
    required this.subject,
    required this.studentName,
    this.note,
    required this.platform,
    this.startsIn,
  });

  // One row of todaysSchedule from GET /TutorLandingpage/LandingPageScreen.
  // MySQL sends every value back as text, so numbers are parsed here.
  factory DashboardSession.fromJson(Map<String, dynamic> j) {
    String clock(Object? v) {
      final s = v?.toString() ?? '';
      return s.length >= 5 ? s.substring(0, 5) : s; // "15:00:00" -> "15:00"
    }

    final minutes = int.tryParse(j['MinutesUntilStart']?.toString() ?? '');
    return DashboardSession(
      bookingId: int.tryParse(j['Booking_id']?.toString() ?? '') ?? 0,
      subjectId: int.tryParse(j['SubjectID']?.toString() ?? '') ?? 0,
      timeRange: '${clock(j['StartTime'])} – ${clock(j['EndTime'])}',
      subject: j['Subject']?.toString() ?? '',
      studentName: j['StudentName']?.toString() ?? 'Student',
      note: j['Note']?.toString(),
      platform: platformOf(j['Link']?.toString()),
      startsIn: minutes == null ? null : startsInLabel(minutes),
    );
  }

  // Each subject keeps the same colour strip on every card
  static const _palette = [
    Color(0xFF246BFE),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
  ];

  Color get color => _palette[subjectId % _palette.length];
}

class DashboardData {
  final String accountStatus; // 'Active' or 'Pending'
  final Map<String, dynamic>? application; // Pending tutors only
  final int activeStudents;
  final int upcomingToday;
  final List<DashboardSession> todaySchedule;
  final String tutorName;
  final String? tutorPhotoUrl;
  final String tutorInitials;

  DashboardData({
    required this.accountStatus,
    this.application,
    required this.activeStudents,
    required this.upcomingToday,
    required this.todaySchedule,
    required this.tutorName,
    this.tutorPhotoUrl,
    required this.tutorInitials,
  });

  bool get isPending => accountStatus != 'Active';

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final tutor = j['tutor'] as Map<String, dynamic>?;
    final name = tutor?['name']?.toString() ?? '';
    return DashboardData(
      accountStatus: j['accountStatus']?.toString() ?? 'Active',
      application: j['application'] as Map<String, dynamic>?,
      activeStudents:
          int.tryParse(j['activeStudents']?.toString() ?? '') ?? 0,
      upcomingToday: int.tryParse(j['upcomingToday']?.toString() ?? '') ?? 0,
      todaySchedule: (j['todaysSchedule'] as List<dynamic>? ?? [])
          .map((e) => DashboardSession.fromJson(e as Map<String, dynamic>))
          .toList(),
      tutorName: name,
      tutorPhotoUrl: tutor?['profilePhotoUrl']?.toString(),
      tutorInitials: name.isEmpty ? 'T' : initialsOf(name),
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TutorDashboard extends StatefulWidget {
  /// [initialData] is the dashboard JSON when it was already loaded
  /// (the login page fetches it to check the account is a tutor).
  const TutorDashboard({super.key, this.initialData});

  final Map<String, dynamic>? initialData;

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
    final initial = widget.initialData;
    if (initial != null) {
      _data = DashboardData.fromJson(initial);
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = DashboardData.fromJson(await fetchTutorDashboard());
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _openBooking(DashboardSession session) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TutorBookingDetailScreen(bookingId: session.bookingId),
      ),
    );
    if (changed == true) _load(); // postponed: it may have left today
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
                                if (_data!.isPending)
                                  _buildApplicationStatus()
                                else ...[
                                  _buildStatsRow(),
                                  const SizedBox(height: 24),
                                  _buildTodaySchedule(),
                                ],
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
    final initials = _data?.tutorInitials ?? 'T';
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
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_outlined,
                color: Color(0xFF1A1A2E), size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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

  // ── APPLICATION STATUS (Pending tutors) ───────────────────────────────────────

  Widget _buildApplicationStatus() {
    final app = _data?.application;
    final status = app?['status']?.toString() ?? 'Pending';
    final feedback = app?['adminFeedback']?.toString();
    final submitted = app?['submittedAt']?.toString();

    final (IconData icon, Color color, String message) = switch (status) {
      'Rejected' => (
          Icons.cancel_outlined,
          const Color(0xFFE53935),
          'Your application was not approved.',
        ),
      'Approved' => (
          Icons.check_circle_outline,
          const Color(0xFF10B981),
          'Your application was approved. Your account will be activated shortly.',
        ),
      _ => (
          Icons.hourglass_top_rounded,
          const Color(0xFFF59E0B),
          'Your application is under review. You will be notified once an '
              'administrator approves your account.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text('Application $status',
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E))),
            ],
          ),
          const SizedBox(height: 10),
          Text(message,
              style: GoogleFonts.inter(
                  fontSize: 13, color: const Color(0xFF6B7280), height: 1.5)),
          if (submitted != null && submitted.length >= 10) ...[
            const SizedBox(height: 8),
            Text('Submitted ${formatLongDate(submitted.substring(0, 10))}',
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF9CA3AF))),
          ],
          if (feedback != null && feedback.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Feedback from the administrator',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            Text(feedback,
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFF6B7280))),
          ],
        ],
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
          ...sessions.map((s) => GestureDetector(
                onTap: () => _openBooking(s),
                child: _scheduleCard(s),
              )),
      ],
    );
  }

  Widget _scheduleCard(DashboardSession session) {
    // Determine platform icon
    IconData platformIcon;
    switch (session.platform) {
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
        onTap: (i) => openTutorTab(context, i, current: 0),
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
