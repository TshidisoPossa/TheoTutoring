import '../../services/chat_unread.dart';
import '../../services/in_app_notifications.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../tutor_registration.dart';
import 'tutor_api.dart';
import 'tutor_booking_detail.dart';
import 'tutor_format.dart';
import 'tutor_nav.dart';
import 'tutor_notifications.dart';
import 'tutor_theme.dart';

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
    final minutes = int.tryParse(j['MinutesUntilStart']?.toString() ?? '');
    return DashboardSession(
      bookingId: int.tryParse(j['Booking_id']?.toString() ?? '') ?? 0,
      subjectId: int.tryParse(j['SubjectID']?.toString() ?? '') ?? 0,
      // "15:00:00" -> "3:00 PM – 4:00 PM", like the dashboard design
      timeRange: '${clock12(j['StartTime']?.toString())} – '
          '${clock12(j['EndTime']?.toString())}',
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

class DashboardReview {
  final String studentName;
  final int rating; // 1 to 5
  final String? comment;
  final String? createdAt; // "2026-10-21 14:03:00"

  DashboardReview({
    required this.studentName,
    required this.rating,
    this.comment,
    this.createdAt,
  });

  // One row of latestReviews from GET /TutorLandingpage/LandingPageScreen
  factory DashboardReview.fromJson(Map<String, dynamic> j) => DashboardReview(
        studentName: j['StudentName']?.toString() ?? 'Student',
        rating: (int.tryParse(j['Rating']?.toString() ?? '') ?? 0).clamp(0, 5),
        comment: j['Comment']?.toString(),
        createdAt: j['Created_At']?.toString(),
      );
}

class DashboardData {
  final String accountStatus; // 'Active' or 'Pending'
  final Map<String, dynamic>? application; // Pending tutors only
  final int activeStudents;
  final int upcomingToday;
  final double averageRating; // 0 when the tutor has no reviews yet
  final List<DashboardSession> todaySchedule;
  final List<DashboardReview> latestReviews;
  final String tutorName;
  final String? tutorPhotoUrl;
  final String tutorInitials;

  DashboardData({
    required this.accountStatus,
    this.application,
    required this.activeStudents,
    required this.upcomingToday,
    required this.averageRating,
    required this.todaySchedule,
    required this.latestReviews,
    required this.tutorName,
    this.tutorPhotoUrl,
    required this.tutorInitials,
  });

  bool get isPending => accountStatus != 'Active';

  String get firstName {
    final parts = tutorName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'there' : parts.first;
  }

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final tutor = j['tutor'] as Map<String, dynamic>?;
    final name = tutor?['name']?.toString() ?? '';
    return DashboardData(
      accountStatus: j['accountStatus']?.toString() ?? 'Active',
      application: j['application'] as Map<String, dynamic>?,
      activeStudents:
          int.tryParse(j['activeStudents']?.toString() ?? '') ?? 0,
      upcomingToday: int.tryParse(j['upcomingToday']?.toString() ?? '') ?? 0,
      averageRating:
          double.tryParse(j['averageRating']?.toString() ?? '') ?? 0,
      todaySchedule: (j['todaysSchedule'] as List<dynamic>? ?? [])
          .map((e) => DashboardSession.fromJson(e as Map<String, dynamic>))
          .toList(),
      latestReviews: (j['latestReviews'] as List<dynamic>? ?? [])
          .map((e) => DashboardReview.fromJson(e as Map<String, dynamic>))
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
  int _unread = 0; // the number on the bell

  static const _blue  = Color(0xFF246BFE);
  static const _amber = Color(0xFFF59E0B);
  static const _green = Color(0xFF10B981);
  static const _red   = Color(0xFFE53935);

  // Light colours, or the dark ones when the tutor turned on Dark Mode
  bool get _dk => context.tutorDark;
  Color get _bg => _dk ? TutorDark.background : const Color(0xFFF2F4F8);
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _dark => _dk ? TutorDark.text : const Color(0xFF1A1A2E);
  Color get _grey => _dk ? TutorDark.textMuted : const Color(0xFF6B7280);
  Color get _muted => _dk ? TutorDark.textFaint : const Color(0xFF9CA3AF);
  Color get _line => _dk ? TutorDark.border : const Color(0xFFE5E7EB);
  Color get _divider => _dk ? TutorDark.border : const Color(0xFFF0F1F4);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialData;
    if (initial != null) {
      _data = DashboardData.fromJson(initial);
      tutorAccountIsActive = !_data!.isPending;
      _loading = false;
      _loadUnread();
    } else {
      _load();
    }
    // The bell follows the in-app notification checks (new ones pop up)
    InAppNotifications.instance.unreadCount.addListener(_onLiveUnread);
  }

  void _onLiveUnread() {
    if (mounted) {
      setState(() => _unread = InAppNotifications.instance.unreadCount.value);
    }
  }

  @override
  void dispose() {
    InAppNotifications.instance.unreadCount.removeListener(_onLiveUnread);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    _loadUnread();
    try {
      final data = DashboardData.fromJson(await fetchTutorDashboard());
      tutorAccountIsActive = !data.isPending;
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // The bell badge is extra: if it cannot load, the bell just shows no number.
  Future<void> _loadUnread() async {
    try {
      final unread = await fetchTutorUnreadCount();
      if (mounted) setState(() => _unread = unread);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    final tab = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const TutorNotificationsScreen()),
    );
    if (!mounted) return;
    _loadUnread();
    if (tab != null) _openTab(tab); // a bottom-bar tab was tapped there
  }

  Future<void> _openBooking(DashboardSession session) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TutorBookingDetailScreen(bookingId: session.bookingId),
      ),
    );
    if (changed == true) _load(); // cancelled or rescheduled
  }

  // Bottom bar and shortcuts. Tutors who are not Active may open the
  // dashboard and profile only; openTutorTab blocks Schedule and Chats.
  void _openTab(int index) => openTutorTab(context, index, current: 0);

  Future<void> _resubmitRejectedApplication() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in again to update your application.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TutorRegistration(
          fullName: _data?.tutorName ?? user.displayName ?? '',
          email: user.email ?? '',
          password: '',
          phoneNumber: user.phoneNumber ?? '',
          existingFirebaseUser: user,
        ),
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
                                const SizedBox(height: 18),
                                _buildGreeting(),
                                const SizedBox(height: 20),
                                if (_data!.isPending) ...[
                                  _buildApplicationStatus(),
                                  const SizedBox(height: 16),
                                  _buildWhileYouWait(),
                                ] else ...[
                                  _buildStatsRow(),
                                  const SizedBox(height: 12),
                                  _buildRatingCard(),
                                  const SizedBox(height: 24),
                                  _buildTodaySchedule(),
                                  const SizedBox(height: 24),
                                  _buildLatestReviews(),
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
                style: GoogleFonts.inter(color: _grey, fontSize: 14),
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
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Theo Tutoring',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _dark,
              ),
            ),
          ),

          // Bell icon: opens Notifications, red badge = unread count
          IconButton(
            onPressed: _openNotifications,
            tooltip: 'Notifications',
            icon: Badge(
              isLabelVisible: _unread > 0,
              backgroundColor: _red,
              label: Text(_unread > 99 ? '99+' : '$_unread'),
              child: Icon(Icons.notifications_outlined,
                  color: _dark, size: 24),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),

          const SizedBox(width: 4),

          // Avatar with initials / photo: opens the Profile tab
          GestureDetector(
            onTap: () => _openTab(3),
            child: CircleAvatar(
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
          ),
        ],
      ),
    );
  }

  // ── GREETING ──────────────────────────────────────────────────────────────────

  Widget _buildGreeting() {
    final now = DateTime.now();
    final partOfDay = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
      'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}'
              .toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: _muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$partOfDay, ${_data?.firstName ?? 'there'}',
          style: GoogleFonts.inter(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: _dark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _data?.isPending ?? false
              ? 'Here is where your tutor application stands.'
              : 'Here is your teaching overview for today.',
          style: GoogleFonts.inter(fontSize: 13, color: _grey),
        ),
      ],
    );
  }

  // ── APPLICATION STATUS (Pending tutors) ───────────────────────────────────────

  Widget _buildApplicationStatus() {
    final app = _data?.application;
    final status = app?['status']?.toString() ?? 'Pending';
    final feedback = app?['adminFeedback']?.toString();
    final submitted = app?['submittedAt']?.toString();
    final reviewed = app?['reviewedAt']?.toString();

    final (IconData icon, Color color, String title, String message) =
        switch (status) {
      'Rejected' => (
          Icons.cancel_outlined,
          _red,
          'Application not approved',
          'An administrator reviewed your application and did not approve it.',
        ),
      'Approved' => (
          Icons.check_circle_outline,
          _green,
          'Application approved',
          'Your account will be activated shortly. Pull down to refresh.',
        ),
      _ => (
          Icons.hourglass_top_rounded,
          _amber,
          'Application under review',
          'An administrator is reviewing your application. You will be '
              'notified once a decision has been made.',
        ),
    };

    // The three steps of the tracker
    final steps = [
      (
        'Application submitted',
        _shortDate(submitted) ?? 'Done',
        _StepState.done,
      ),
      (
        'Admin review',
        status == 'Pending' ? 'In progress' : (_shortDate(reviewed) ?? 'Done'),
        status == 'Pending' ? _StepState.current : _StepState.done,
      ),
      (
        status == 'Rejected' ? 'Not approved' : 'Account approved',
        status == 'Pending' ? 'Waiting' : (_shortDate(reviewed) ?? ''),
        switch (status) {
          'Approved' => _StepState.done,
          'Rejected' => _StepState.failed,
          _ => _StepState.upcoming,
        },
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _dark)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(message,
              style: GoogleFonts.inter(fontSize: 13, color: _grey, height: 1.5)),
          const SizedBox(height: 18),
          for (var i = 0; i < steps.length; i++)
            _buildStep(
              title: steps[i].$1,
              subtitle: steps[i].$2,
              state: steps[i].$3,
              isLast: i == steps.length - 1,
            ),
          if (feedback != null && feedback.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Feedback from the administrator',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _dark)),
                  const SizedBox(height: 4),
                  Text(feedback,
                      style: GoogleFonts.inter(fontSize: 13, color: _grey)),
                ],
              ),
            ),
          ],
          if (status == 'Rejected') ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _resubmitRejectedApplication,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Correct and resubmit'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep({
    required String title,
    required String subtitle,
    required _StepState state,
    required bool isLast,
  }) {
    final (Color color, IconData? icon) = switch (state) {
      _StepState.done => (_green, Icons.check_rounded),
      _StepState.current => (_amber, null),
      _StepState.failed => (_red, Icons.close_rounded),
      _StepState.upcoming => (_line, null),
    };
    final filled = state != _StepState.upcoming;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dot and the line down to the next step
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: filled ? color : _surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: icon != null
                      ? Icon(icon, size: 14, color: Colors.white)
                      : state == _StepState.current
                          ? const Center(
                              child: CircleAvatar(
                                  radius: 3, backgroundColor: Colors.white))
                          : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: state == _StepState.done
                          ? _green
                          : _line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: state == _StepState.upcoming ? _muted : _dark)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.inter(fontSize: 12, color: _muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Things a Pending tutor can already do (business rule 5)
  Widget _buildWhileYouWait() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('While you wait'),
        const SizedBox(height: 12),
        _actionTile(
          icon: Icons.person_outline_rounded,
          color: _blue,
          title: 'Complete your profile',
          subtitle: 'Add a photo and check your subjects and qualifications.',
          onTap: () => _openTab(3),
        ),
        const SizedBox(height: 10),
        _actionTile(
          icon: Icons.event_available_outlined,
          color: _green,
          title: 'Check your availability',
          subtitle: 'Students can only book the times you mark as available.',
          onTap: () => _openTab(3),
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _dark)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.inter(fontSize: 12, color: _grey)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
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
              color: _surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        color: _muted, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Active Students',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _muted,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$activeStudents',
                  style: GoogleFonts.inter(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: _dark,
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
                    Flexible(
                      child: Text('Upcoming Today',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500)),
                    ),
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

  // ── RATING CARD ───────────────────────────────────────────────────────────────

  Widget _buildRatingCard() {
    final rating = _data?.averageRating ?? 0;
    final hasRating = rating > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.star_rounded, color: _amber, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Average Rating',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _muted,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  hasRating ? 'From your students\' reviews' : 'No ratings yet',
                  style: GoogleFonts.inter(fontSize: 12, color: _grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasRating ? rating.toStringAsFixed(1) : '–',
                style: GoogleFonts.inter(
                    fontSize: 26, fontWeight: FontWeight.bold, color: _dark),
              ),
              _stars(rating, size: 14),
            ],
          ),
        ],
      ),
    );
  }

  // 4.5 -> four full stars and a half star
  Widget _stars(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : rating >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            color: rating >= i - 0.5 ? _amber : _line,
            size: size,
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
        // Header row: "Today's Schedule  4 sessions  View All"
        Row(
          children: [
            // On a very narrow screen the title wraps rather than the row
            // overflowing past "View All"
            Expanded(
              child: Row(
                children: [
                  Flexible(child: _sectionTitle("Today's Schedule")),
                  const SizedBox(width: 8),
                  Text(
                    '${sessions.length} session${sessions.length == 1 ? '' : 's'}',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: _muted, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            // Opens the full Schedule page
            TextButton(
              onPressed: () => _openTab(1),
              style: TextButton.styleFrom(
                foregroundColor: _blue,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'View All',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (sessions.isEmpty)
          _emptyCard(
            icon: Icons.event_available_outlined,
            title: 'No sessions today',
            message: 'Booked sessions for today will show up here.',
          )
        else
          ...sessions.map((s) => GestureDetector(
                onTap: () => _openBooking(s),
                child: _scheduleCard(s),
              )),
      ],
    );
  }

  // One session, as in the dashboard design: coloured strip, time pill and
  // "In 45 min" badge in the subject's colour, subject and student, the
  // meeting type, then a footer with the student's note or the meeting.
  Widget _scheduleCard(DashboardSession session) {
    final color = session.color;
    final startsIn = session.startsIn ?? '';
    final note = session.note?.trim() ?? '';
    final hasLink = session.platform != 'none';
    final platformIcon = switch (session.platform) {
      'zoom' || 'meet' || 'teams' => Icons.videocam_outlined,
      'online' => Icons.link_rounded,
      _ => Icons.link_off_rounded, // no meeting link yet
    };

    Widget pill(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coloured left strip
            Container(width: 4, color: color),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: time pill + "In 45 min" badge
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: pill(session.timeRange),
                          ),
                        ),
                        if (startsIn.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          pill(startsIn),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Row 2: subject, "with Name", meeting icon
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
                                  color: _dark,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text.rich(
                                TextSpan(
                                  text: 'with ',
                                  style: GoogleFonts.inter(
                                      fontSize: 12.5, color: _muted),
                                  children: [
                                    TextSpan(
                                      text: session.studentName,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        color: _grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: meetingLabel(session.platform),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: _line),
                            ),
                            child: Icon(platformIcon,
                                size: 18, color: hasLink ? color : _muted),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    Divider(height: 1, color: _divider),
                    const SizedBox(height: 10),

                    // Row 3: the student's note, or where the session is
                    Row(
                      children: [
                        if (note.isEmpty && hasLink) ...[
                          const Icon(Icons.circle, size: 7, color: _green),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            note.isEmpty
                                ? meetingLabel(session.platform)
                                : note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: _muted),
                          ),
                        ),
                        if (note.isNotEmpty && hasLink) ...[
                          const SizedBox(width: 8),
                          Text(
                            meetingLabel(session.platform),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _dark,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── LATEST REVIEWS ────────────────────────────────────────────────────────────

  Widget _buildLatestReviews() {
    final reviews = _data?.latestReviews ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Latest Reviews'),
        const SizedBox(height: 12),
        if (reviews.isEmpty)
          _emptyCard(
            icon: Icons.rate_review_outlined,
            title: 'No reviews yet',
            message: 'Students can review you after a completed session.',
          )
        else
          ...reviews.map(_reviewCard),
      ],
    );
  }

  Widget _reviewCard(DashboardReview review) {
    final date = _shortDate(review.createdAt);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _blue.withValues(alpha: 0.12),
                child: Text(initialsOf(review.studentName),
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _blue)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.studentName,
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _dark)),
                    if (date != null)
                      Text(date,
                          style: GoogleFonts.inter(fontSize: 11, color: _muted)),
                  ],
                ),
              ),
              _stars(review.rating.toDouble(), size: 14),
            ],
          ),
          if (review.comment != null && review.comment!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '"${review.comment!.trim()}"',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: _grey,
                  fontStyle: FontStyle.italic,
                  height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  // ── SHARED PIECES ─────────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.bold, color: _dark),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2)),
      ],
    );
  }

  Widget _emptyCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _blue, size: 26),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _dark)),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: _muted)),
        ],
      ),
    );
  }

  // "2026-10-22 10:18:09" -> "Thu, 22 Oct 2026"
  String? _shortDate(String? dateTime) {
    if (dateTime == null || dateTime.length < 10) return null;
    return formatLongDate(dateTime.substring(0, 10));
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: _blue,
        unselectedItemColor: _muted,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: _openTab,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inbox_rounded), label: 'Schedule'),
          BottomNavigationBarItem(
              icon: ChatNavIcon(), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

// Where a step of the application tracker is
enum _StepState { done, current, upcoming, failed }
