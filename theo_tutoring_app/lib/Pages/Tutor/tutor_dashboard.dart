import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../login_page.dart';
import 'tutor_api.dart';
import 'tutor_chats.dart';
import 'tutor_profile.dart';
import 'tutor_requests.dart';
import 'tutor_schedule.dart';
import 'tutor_settings.dart';

// Tutor landing page. Owns the side drawer (Home, Messages, Settings) and
// the bottom bar (Dashboard, Requests, Schedule, Profile). The Dashboard tab
// shows data from GET /TutorLandingpage/LandingPageScreen.
class TutorDashboard extends StatefulWidget {
  const TutorDashboard({super.key, this.initialData});

  /// Dashboard JSON already loaded by the login page (skips the first fetch).
  final Map<String, dynamic>? initialData;

  @override
  State<TutorDashboard> createState() => _TutorDashboardState();
}

class _TutorDashboardState extends State<TutorDashboard> {
  // Bottom bar tabs
  static const _dashboardTab = 0;
  static const _requestsTab = 1;
  static const _scheduleTab = 2;

  // Colour strip for each schedule card, repeated in order
  static const _scheduleColors = [
    Color(0xFFFF6B35),
    Color(0xFF1A73E8),
    Color(0xFF34A853),
    Color(0xFF9C27B0),
  ];

  int _currentIndex = _dashboardTab;
  Map<String, dynamic>? _data; // response from the backend
  String? _error; // shown when the first load fails

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    if (_data == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await fetchTutorDashboard();
      if (!mounted) return;
      setState(() => _data = data);
    } on TutorApiException catch (e) {
      if (!mounted) return;
      if (_data == null) {
        setState(() => _error = e.message);
      } else {
        // Keep showing the old data and just report the failed refresh
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  // ── DATA HELPERS ─────────────────────────────────────
  Map<String, dynamic> get _tutor =>
      (_data?['tutor'] as Map?)?.cast<String, dynamic>() ?? const {};

  bool get _isActive =>
      _text(_data?['accountStatus']).toLowerCase() == 'active';

  int _count(String key) => (_data?[key] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> _rows(String key) =>
      ((_data?[key] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();

  static String _text(Object? value) => value?.toString().trim() ?? '';

  // '13:00:00' -> '1:00 PM'
  static String _formatTime(Object? value) {
    final parts = _text(value).split(':');
    final hour = int.tryParse(parts.first);
    if (hour == null || parts.length < 2) return _text(value);
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:${parts[1]} $suffix';
  }

  // '2026-10-15' -> 'Thu, 15 Oct'
  static String _formatDate(Object? value) {
    final date = DateTime.tryParse(_text(value));
    if (date == null) return _text(value);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }

  // ── NAVIGATION ───────────────────────────────────────
  void _onTabTapped(int index) {
    // Pending tutors can only see their application status
    if (index != _dashboardTab && _data != null && !_isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Available once your application is approved.'),
        ),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  void _onDrawerItemTapped(int index) {
    Navigator.of(context).pop(); // close the drawer
    switch (index) {
      case 0: // Home
        _onTabTapped(_dashboardTab);
      case 1: // Messages
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TutorChatListScreen()));
      case 2: // Settings
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const TutorSettings()));
    }
  }

  Future<void> _logout() async {
    Navigator.of(context).pop(); // close the drawer
    try {
      await FirebaseAuth.instance.signOut();
    } on Exception {
      // Leave the dashboard anyway; the next login replaces the session
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: _buildSideDrawer(),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHome(),
          const TutorRequestsScreen(),
          const TutorScheduleScreen(),
          TutorProfileScreen(onBack: () => _onTabTapped(_dashboardTab)),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── DASHBOARD TAB ────────────────────────────────────
  Widget _buildHome() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(),
              const SizedBox(height: 20),
              ..._buildHomeContent(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildHomeContent() {
    if (_data == null) {
      if (_error != null) return [_buildError(_error!)];
      return const [
        Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (!_isActive) {
      return [_buildApplicationStatus(_data!['application'] as Map?)];
    }

    final newRequests = _count('newRequests');
    return [
      _buildStatsRow(),
      const SizedBox(height: 16),
      if (newRequests > 0) ...[
        _buildNewRequestsBanner(newRequests),
        const SizedBox(height: 20),
      ],
      _buildRecentRequests(),
      const SizedBox(height: 20),
      _buildTodaySchedule(),
      const SizedBox(height: 20),
      _buildRatingCard(),
    ];
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.cloud_off, color: Colors.grey[400], size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                elevation: 0,
              ),
              child: Text(
                'Try Again',
                style: GoogleFonts.inter(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Photo from the backend, or a person icon when there is none
  Widget _avatar(
    Object? photoUrl, {
    double radius = 20,
    Color backgroundColor = const Color(0xFF1A73E8),
    Color iconColor = Colors.white,
  }) {
    final url = _text(photoUrl);
    final hasPhoto = url.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: hasPhoto ? NetworkImage(url) : null,
      onBackgroundImageError: hasPhoto ? (_, _) {} : null,
      child: hasPhoto ? null : Icon(Icons.person, color: iconColor, size: 22),
    );
  }

  // ── TOP BAR ──────────────────────────────────────────
  Widget _buildTopBar() {
    final firstName = _text(_tutor['name']).split(' ').first;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Hamburger
        Builder(
          builder: (context) => GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.menu, color: Color(0xFF1A1A2E), size: 22),
            ),
          ),
        ),

        // Title
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              firstName.isEmpty ? 'Theo Tutoring' : 'Hi, $firstName',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
            ),
            Text(
              'Dashboard',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),

        // Bell + Avatar
        Row(
          children: [
            GestureDetector(
              onTap: () => _onTabTapped(_requestsTab),
              child: Stack(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: Color(0xFF1A1A2E),
                      size: 22,
                    ),
                  ),
                  if (_count('newRequests') > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _avatar(_tutor['profilePhotoUrl']),
          ],
        ),
      ],
    );
  }

  // ── APPLICATION STATUS (Pending tutors) ──────────────
  Widget _buildApplicationStatus(Map? application) {
    final status = _text(application?['status']);
    final feedback = _text(application?['adminFeedback']);
    final submitted = _formatDate(application?['submittedAt']);
    final color = switch (status.toLowerCase()) {
      'approved' => const Color(0xFF34A853),
      'rejected' => const Color(0xFFE53935),
      _ => const Color(0xFFF9A825),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            'Your application is under review',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            application == null
                ? 'We have not received your application yet.'
                : 'Bookings, requests and your schedule will appear here '
                      'once an administrator approves your account.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          if (application != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status.isEmpty ? 'Pending' : status,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (submitted.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Submitted $submitted',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
            if (feedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Feedback: $feedback',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── STATS ROW ────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            value: '${_count('activeStudents')}',
            label: 'Active Students',
            icon: Icons.people,
            iconColor: const Color(0xFF1A73E8),
            bgColor: const Color(0xFFE8F0FE),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            value: '${_count('upcomingToday')}',
            label: 'Upcoming Today',
            icon: Icons.calendar_today,
            iconColor: const Color(0xFF1A73E8),
            bgColor: const Color(0xFF1A73E8),
            isDark: true,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required String value,
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    bool isDark = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isDark ? Colors.white70 : iconColor, size: 28),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ── NEW REQUESTS BANNER ──────────────────────────────
  Widget _buildNewRequestsBanner(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inbox, color: Color(0xFFF9A825), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count New ${count == 1 ? 'Request' : 'Requests'}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'Review pending bookings',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _onTabTapped(_requestsTab),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text(
              'View All',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── RECENT REQUESTS ───────────────────────────────────
  Widget _buildRecentRequests() {
    final requests = _rows('recentRequests');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Requests',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            GestureDetector(
              onTap: () => _onTabTapped(_requestsTab),
              child: Text(
                'See all →',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF1A73E8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (requests.isEmpty)
          _emptyCard('No pending requests right now.')
        else
          ...requests.map(_requestCard),
      ],
    );
  }

  Widget _requestCard(Map<String, dynamic> req) {
    final note = _text(req['Note']);
    final when =
        '${_formatDate(req['Date'])} · '
        '${_formatTime(req['StartTime'])} - ${_formatTime(req['EndTime'])}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(
                req['StudentPhoto'],
                backgroundColor: const Color(0xFFE8F0FE),
                iconColor: const Color(0xFF1A73E8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(req['StudentName']),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      '${_text(req['Subject'])} · $when',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note.isEmpty ? 'No note added.' : note,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  // Accepting happens on the Requests tab
                  onPressed: () => _onTabTapped(_requestsTab),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                  ),
                  child: Text(
                    'Accept',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _onTabTapped(_requestsTab),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1A73E8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    'View Details',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A73E8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── TODAY'S SCHEDULE ──────────────────────────────────
  Widget _buildTodaySchedule() {
    final sessions = _rows('todaysSchedule');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Today's Schedule",
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            GestureDetector(
              onTap: () => _onTabTapped(_scheduleTab),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A73E8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          _emptyCard('No sessions booked for today.')
        else
          for (var i = 0; i < sessions.length; i++)
            _scheduleCard(
              sessions[i],
              _scheduleColors[i % _scheduleColors.length],
            ),
      ],
    );
  }

  Widget _scheduleCard(Map<String, dynamic> session, Color color) {
    return GestureDetector(
      onTap: () => _onTabTapped(_scheduleTab),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Colour strip
            Container(
              width: 4,
              height: 50,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatTime(session['StartTime'])} - '
                    '${_formatTime(session['EndTime'])}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _text(session['Subject']),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    'with ${_text(session['StudentName'])}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ── RATING & REVIEWS ─────────────────────────────────
  Widget _buildRatingCard() {
    final rating = (_data?['averageRating'] as num?)?.toDouble() ?? 0;
    final reviews = _rows('latestReviews');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your Rating',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),
              const Icon(Icons.star, color: Color(0xFFFFC107), size: 22),
              const SizedBox(width: 4),
              Text(
                rating.toStringAsFixed(1),
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (reviews.isEmpty)
            Text(
              'No reviews yet.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
            )
          else
            ...reviews.map(_reviewTile),
        ],
      ),
    );
  }

  Widget _reviewTile(Map<String, dynamic> review) {
    final stars = double.tryParse(_text(review['Rating']))?.round() ?? 0;
    final comment = _text(review['Comment']);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text(review['StudentName']),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
              ),
              for (var i = 0; i < 5; i++)
                Icon(
                  i < stars ? Icons.star : Icons.star_border,
                  color: const Color(0xFFFFC107),
                  size: 14,
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              comment,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
      ),
    );
  }

  // ── SIDE DRAWER (same design as student dashboard) ────
  Widget _buildSideDrawer() {
    final items = [
      {'icon': Icons.home_outlined, 'activeIcon': Icons.home, 'label': 'Home'},
      {
        'icon': Icons.chat_bubble_outline,
        'activeIcon': Icons.chat_bubble,
        'label': 'Messages',
      },
      {
        'icon': Icons.settings_outlined,
        'activeIcon': Icons.settings,
        'label': 'Settings',
      },
    ];

    return Drawer(
      width: 280,
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A73E8).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.school,
                          color: Color(0xFF1A73E8),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Theo Tutoring',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Color(0xFF666666),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Nav items. Messages and Settings open as their own pages,
            // so Home is the selected item whenever the drawer is open.
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = index == 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: GestureDetector(
                      onTap: () => _onDrawerItemTapped(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1A73E8)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? item['activeIcon'] as IconData
                                  : item['icon'] as IconData,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF555555),
                              size: 22,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              item['label'] as String,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF555555),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: GestureDetector(
                onTap: _logout,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.logout,
                        color: Color(0xFFE53935),
                        size: 22,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Log Out',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      {
        'icon': Icons.dashboard_outlined,
        'activeIcon': Icons.dashboard,
        'label': 'Dashboard',
      },
      {
        'icon': Icons.inbox_outlined,
        'activeIcon': Icons.inbox,
        'label': 'Requests',
      },
      {
        'icon': Icons.calendar_today_outlined,
        'activeIcon': Icons.calendar_today,
        'label': 'Schedule',
      },
      {
        'icon': Icons.person_outline,
        'activeIcon': Icons.person,
        'label': 'Profile',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isActive = index == _currentIndex;
              return GestureDetector(
                onTap: () => _onTabTapped(index),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive
                          ? item['activeIcon'] as IconData
                          : item['icon'] as IconData,
                      color: isActive ? const Color(0xFF1A73E8) : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item['label'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: isActive ? const Color(0xFF1A73E8) : Colors.grey,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
