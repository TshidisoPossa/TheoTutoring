import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'search_tutor.dart';
import 'student_dashboard_api.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key, this.studentName});

  final String? studentName;

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  int _currentIndex = 0;
  int _selectedDrawerIndex = 0;

  DateTime _selectedDate = DateTime.now();
  DateTime _displayedMonth = DateTime.now();
  final StudentDashboardApi _dashboardApi = StudentDashboardApi();
  Map<String, dynamic>? _dashboard;
  bool _loadingDashboard = true;
  String? _dashboardError;

  List<Map<String, dynamic>> get _upcomingSessions =>
      (_dashboard?['upcomingSessions'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  List<Map<String, dynamic>> get _topTutors =>
      (_dashboard?['tutors'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  @override
  void dispose() {
    _dashboardApi.close();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loadingDashboard = true;
      _dashboardError = null;
    });
    try {
      final data = await _dashboardApi.fetch();
      if (mounted) setState(() => _dashboard = data);
    } catch (error) {
      if (mounted) {
        setState(() => _dashboardError = error.toString());
      }
    } finally {
      if (mounted) setState(() => _loadingDashboard = false);
    }
  }

  Widget _buildDashboardError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42, color: _textMuted),
          const SizedBox(height: 12),
          Text(
            _dashboardError ?? 'Dashboard could not be loaded.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: _textMuted),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _loadDashboard, child: const Text('Retry')),
        ],
      ),
    ),
  );

  bool _hasSessionOn(DateTime date) => _upcomingSessions.any((session) {
    final sessionDate = DateTime.tryParse('${session['date']}');
    return sessionDate != null &&
        sessionDate.year == date.year &&
        sessionDate.month == date.month &&
        sessionDate.day == date.day;
  });

  final List<String> _drawerItems = [
    'Home',
    'Subjects',
    'Schedule',
    'Messages',
    'Session History',
    'Settings',
  ];

  final List<IconData> _drawerIcons = [
    Icons.home_rounded,
    Icons.menu_book_rounded,
    Icons.calendar_month_rounded,
    Icons.chat_bubble_outline_rounded,
    Icons.history_rounded,
    Icons.settings_outlined,
  ];

  static const Color _primaryBlue = Color(0xFF356AE6);
  static const Color _darkBlue = Color(0xFF173B8F);
  static const Color _background = Color(0xFFF7F9FE);
  static const Color _textDark = Color(0xFF17233D);
  static const Color _textMuted = Color(0xFF7B8498);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      drawer: _buildSideDrawer(),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: _buildTopBar(),
      ),
      body: SafeArea(
        top: false,
        child: _loadingDashboard && _dashboard == null
            ? const Center(child: CircularProgressIndicator())
            : _dashboardError != null && _dashboard == null
            ? _buildDashboardError()
            : RefreshIndicator(
                onRefresh: _loadDashboard,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 850),
                              child: _buildWelcomeSection(),
                            ),
                          ),
                          const SizedBox(height: 26),
                          const _OrganisationLogoCarousel(),
                          const SizedBox(height: 26),
                          _buildUpNextCard(),
                          const SizedBox(height: 30),
                          _buildCalendar(),
                          const SizedBox(height: 32),
                          _buildTopTutors(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── TOP BAR ─────────────────────────────────────────────

  Widget _buildTopBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
              color: _textDark,
              tooltip: 'Open menu',
            ),
          ),
          const SizedBox(width: 4),
          Image.asset(
            'assets/logo.png',
            height: 42,
            width: 42,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: _primaryBlue,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'TheoTutoring',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: _textDark,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () {
            _showMessage('Notifications will be available soon.');
          },
          icon: const Icon(Icons.notifications_none_rounded),
          color: _textDark,
          tooltip: 'Notifications',
        ),
        Padding(
          padding: const EdgeInsets.only(right: 18, left: 4),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE4ECFF),
            child: const Icon(
              Icons.person_rounded,
              color: _primaryBlue,
              size: 25,
            ),
          ),
        ),
      ],
    );
  }

  // ── SIDE DRAWER ─────────────────────────────────────────

  Widget _buildSideDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryBlue, _darkBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 54,
                    width: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 31,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'TheoTutoring',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your learning journey starts here',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'MENU',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _textMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _drawerItems.length,
                itemBuilder: (context, index) {
                  final selected = _selectedDrawerIndex == index;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      selected: selected,
                      selectedTileColor: const Color(0xFFEDF2FF),
                      leading: Icon(
                        _drawerIcons[index],
                        color: selected ? _primaryBlue : _textMuted,
                      ),
                      title: Text(
                        _drawerItems[index],
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected ? _primaryBlue : _textDark,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.circle,
                              size: 7,
                              color: _primaryBlue,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedDrawerIndex = index;
                        });
                        Navigator.pop(context);

                        if (index != 0) {
                          _showMessage(
                            '${_drawerItems[index]} will be connected soon.',
                          );
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              leading: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFE05252),
              ),
              title: Text(
                'Log out',
                style: GoogleFonts.poppins(
                  color: const Color(0xFFE05252),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showMessage('Logout will be connected to authentication.');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── WELCOME SECTION ─────────────────────────────────────

  Widget _buildWelcomeSection() {
    final name =
        (_dashboard?['studentName'] as String?)?.trim() ??
        widget.studentName?.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final headlineSize = constraints.maxWidth < 440
            ? 28.0
            : constraints.maxWidth < 700
            ? 36.0
            : 46.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              name == null || name.isEmpty
                  ? 'Welcome back!'
                  : 'Welcome back, $name! 👋',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: _primaryBlue,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 17),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Get the help you need,\n',
                    style: TextStyle(color: _textDark),
                  ),
                  TextSpan(
                    text: 'pass with confidence.',
                    style: TextStyle(color: _primaryBlue),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: headlineSize,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Find the right tutor. Learn at your pace.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: _textMuted,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _openTutorSearch,
              icon: const Icon(Icons.search_rounded),
              label: Text(
                'Find a tutor',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 25,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── UPCOMING SESSION ────────────────────────────────────

  Widget _buildUpNextCard() {
    final session = _upcomingSessions.isEmpty ? null : _upcomingSessions.first;
    final sessionDate = session == null
        ? null
        : DateTime.tryParse('${session['date']}');
    final today = DateTime.now();
    final dateLabel = sessionDate == null
        ? ''
        : sessionDate.year == today.year &&
              sessionDate.month == today.month &&
              sessionDate.day == today.day
        ? 'TODAY'
        : '${sessionDate.day} ${_monthName(sessionDate.month).toUpperCase()}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primaryBlue, _darkBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: _primaryBlue.withValues(alpha: 0.19),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: session == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UP NEXT',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'No confirmed upcoming sessions',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your next confirmed lesson will appear here.',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: _openTutorSearch,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Find a tutor'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'UP NEXT',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.event_available_rounded,
                      color: Colors.white70,
                      size: 21,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '${session['subject'] ?? 'Tutoring session'}'.toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Confirmed session',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 23,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${session['tutorName'] ?? 'Tutor'}',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          dateLabel,
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${session['startTime'] ?? ''}',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  void _openTutorSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SearchTutorPage()));
  }

  Widget _buildCalendar() {
    final firstDay = DateTime(_displayedMonth.year, _displayedMonth.month, 1);

    final daysInMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + 1,
      0,
    ).day;

    // Monday = 0, Sunday = 6.
    final startingWeekday = firstDay.weekday - 1;
    final today = DateTime.now();

    final isCurrentMonth =
        _displayedMonth.year == today.year &&
        _displayedMonth.month == today.month;

    final previousMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month - 1,
    );

    final canGoBack =
        previousMonth.year > today.year ||
        (previousMonth.year == today.year &&
            previousMonth.month >= today.month);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEDF0F7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23365D).withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCHEDULE',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: _primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your Calendar',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                      ),
                    ),
                  ],
                ),
              ),
              _monthButton(
                icon: Icons.chevron_left_rounded,
                enabled: canGoBack,
                onTap: () {
                  if (canGoBack) {
                    setState(() {
                      _displayedMonth = DateTime(
                        _displayedMonth.year,
                        _displayedMonth.month - 1,
                      );
                    });
                  }
                },
              ),
              const SizedBox(width: 8),
              _monthButton(
                icon: Icons.chevron_right_rounded,
                enabled: true,
                onTap: () {
                  setState(() {
                    _displayedMonth = DateTime(
                      _displayedMonth.year,
                      _displayedMonth.month + 1,
                    );
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 15,
                  color: _primaryBlue,
                ),
                const SizedBox(width: 9),
                Text(
                  '${_monthName(_displayedMonth.month)} ${_displayedMonth.year}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                ),
                const Spacer(),
                if (isCurrentMonth)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5EDFF),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      'CURRENT MONTH',
                      style: GoogleFonts.poppins(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: _primaryBlue,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 19),
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: GoogleFonts.poppins(
                          color: _textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 11),
          ...List.generate(((startingWeekday + daysInMonth) / 7).ceil(), (
            weekIndex,
          ) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: List.generate(7, (dayIndex) {
                  final dayNumber =
                      weekIndex * 7 + dayIndex - startingWeekday + 1;

                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 39));
                  }

                  final date = DateTime(
                    _displayedMonth.year,
                    _displayedMonth.month,
                    dayNumber,
                  );

                  final selected =
                      date.year == _selectedDate.year &&
                      date.month == _selectedDate.month &&
                      date.day == _selectedDate.day;

                  final isToday =
                      date.year == today.year &&
                      date.month == today.month &&
                      date.day == today.day;
                  final hasSession = _hasSessionOn(date);

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDate = date;
                        });
                      },
                      child: Container(
                        height: 39,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: selected ? _primaryBlue : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          border: !selected && isToday
                              ? Border.all(color: _primaryBlue, width: 1.3)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: GoogleFonts.poppins(
                                color: selected ? Colors.white : _textDark,
                                fontSize: 11,
                                fontWeight: selected || isToday
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            if (hasSession)
                              Container(
                                height: 3,
                                width: 3,
                                margin: const EdgeInsets.only(top: 2),
                                decoration: BoxDecoration(
                                  color: selected ? Colors.white : _primaryBlue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFEDF0F7)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.event_note_rounded,
                  color: _primaryBlue,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected date',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: _textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_selectedDate.day} ${_monthName(_selectedDate.month)} '
                      '${_selectedDate.year}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime.now();
                    _displayedMonth = DateTime.now();
                  });
                },
                child: Text(
                  'Today',
                  style: GoogleFonts.poppins(
                    color: _primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled ? _background : const Color(0xFFF4F5F8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 38,
          width: 38,
          child: Icon(
            icon,
            color: enabled ? _textDark : const Color(0xFFB8BECA),
            size: 22,
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }

  // ── RECOMMENDED TUTORS ──────────────────────────────────

  Widget _buildTopTutors() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available Tutors',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Find the right support for your studies.',
                    style: GoogleFonts.poppins(fontSize: 11, color: _textMuted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _openTutorSearch,
              child: Text(
                'Explore',
                style: GoogleFonts.poppins(
                  color: _primaryBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        if (_topTutors.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No approved tutors are available right now.',
              style: GoogleFonts.poppins(fontSize: 12, color: _textMuted),
            ),
          )
        else
          ..._topTutors.map(_buildTutorCard),
        const SizedBox(height: 5),
        SizedBox(
          width: double.infinity,
          height: 47,
          child: OutlinedButton(
            onPressed: _openTutorSearch,
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryBlue,
              side: const BorderSide(color: Color(0xFFD9E3FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'View All Tutors',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTutorCard(Map<String, dynamic> tutor) {
    final name = '${tutor['name'] ?? 'Tutor'}';
    final subjects = (tutor['subjects'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((subject) => '${subject['subjectName'] ?? ''}')
        .where((subject) => subject.isNotEmpty)
        .take(2)
        .toList();
    final rating = tutor['averageRating'];
    final ratingLabel = rating == null
        ? '—'
        : (rating as num).toStringAsFixed(1);
    final reviewCount = tutor['reviewCount'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFEDF0F7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23365D).withValues(alpha: 0.025),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 57,
                width: 57,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4ECFF),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Center(
                  child: Text(
                    name
                        .split(RegExp(r'\s+'))
                        .where((part) => part.isNotEmpty)
                        .take(2)
                        .map((part) => part[0].toUpperCase())
                        .join(),
                    style: GoogleFonts.poppins(
                      color: _darkBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.poppins(
                        color: _textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subjects.isEmpty
                          ? 'Subject not listed'
                          : subjects.join(' · '),
                      style: GoogleFonts.poppins(
                        color: _textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFB547),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ratingLabel,
                          style: GoogleFonts.poppins(
                            color: _textDark,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '($reviewCount reviews)',
                          style: GoogleFonts.poppins(
                            color: _textMuted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFFADB5C5),
                size: 15,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              ...subjects.map(
                (tag) => Container(
                  margin: const EdgeInsets.only(right: 7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag,
                    style: GoogleFonts.poppins(
                      color: _primaryBlue,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
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

  // ── BOTTOM NAVIGATION ───────────────────────────────────

  Widget _buildBottomNav() {
    const items = [
      _NavItem(Icons.home_rounded, 'Home'),
      _NavItem(Icons.menu_book_rounded, 'Lessons'),
      _NavItem(Icons.chat_bubble_outline_rounded, 'Chat'),
      _NavItem(Icons.person_outline_rounded, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFEDF0F7))),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23365D).withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = _currentIndex == index;

              return Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _currentIndex = index;
                    });

                    if (index != 0) {
                      _showMessage('${item.label} will be connected soon.');
                    }
                  },
                  borderRadius: BorderRadius.circular(13),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          color: selected ? _primaryBlue : _textMuted,
                          size: 22,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.label,
                          style: GoogleFonts.poppins(
                            color: selected ? _primaryBlue : _textMuted,
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ── HELPER ──────────────────────────────────────────────

  void _showMessage(String message) {
    if (!mounted) return;

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
}

class _OrganisationLogoCarousel extends StatefulWidget {
  const _OrganisationLogoCarousel();

  @override
  State<_OrganisationLogoCarousel> createState() =>
      _OrganisationLogoCarouselState();
}

class _OrganisationLogoCarouselState extends State<_OrganisationLogoCarousel>
    with SingleTickerProviderStateMixin {
  static const _organisations = <({String name, String url})>[
    (
      name: 'University of Pretoria',
      url: 'https://img.logo.dev/up.ac.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'Wits University',
      url: 'https://img.logo.dev/wits.ac.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'University of Cape Town',
      url: 'https://img.logo.dev/uct.ac.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'Stellenbosch University',
      url: 'https://img.logo.dev/sun.ac.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'UNISA',
      url: 'https://img.logo.dev/unisa.ac.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'North-West University',
      url: 'https://img.logo.dev/nwu.ac.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'Eduvos',
      url: 'https://img.logo.dev/eduvos.com?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'SANRAL',
      url: 'https://img.logo.dev/sanral.co.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'Airports Company South Africa',
      url:
          'https://img.logo.dev/airports.co.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'WBHO',
      url: 'https://img.logo.dev/wbho.co.za?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
    (
      name: 'Sasol',
      url: 'https://img.logo.dev/sasol.com?token=pk_RFuHpnZUQX2O_cCVSFpMkA',
    ),
  ];

  late final AnimationController _controller;
  bool? _reducedMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 42),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reducedMotion == reduceMotion) return;

    _reducedMotion = reduceMotion;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Students we help at',
          style: GoogleFonts.poppins(
            color: _StudentDashboardState._textDark,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth < 480 ? 132.0 : 156.0;
            const gap = 14.0;
            final cycleWidth = _organisations.length * (tileWidth + gap);
            final copies = _reducedMotion == true ? 1 : 2;

            return ClipRect(
              child: SizedBox(
                height: 94,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(-cycleWidth * _controller.value, 0),
                    child: child,
                  ),
                  child: Row(
                    children: [
                      for (var copy = 0; copy < copies; copy++)
                        for (final organisation in _organisations)
                          Padding(
                            padding: const EdgeInsets.only(right: gap),
                            child: SizedBox(
                              width: tileWidth,
                              height: 78,
                              child: _buildLogoTile(
                                organisation,
                                excludedFromSemantics: copy > 0,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLogoTile(
    ({String name, String url}) organisation, {
    required bool excludedFromSemantics,
  }) {
    final image = Image.network(
      organisation.url,
      fit: BoxFit.contain,
      width: 124,
      height: 48,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF356AE6),
              ),
            ),
      errorBuilder: (context, error, stackTrace) => _logoFallback(organisation),
    );

    final tile = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEDF0F7)),
      ),
      child: image,
    );

    return excludedFromSemantics
        ? ExcludeSemantics(child: tile)
        : Semantics(label: organisation.name, image: true, child: tile);
  }

  Widget _logoFallback(({String name, String url}) organisation) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.school_rounded, color: Color(0xFF356AE6), size: 23),
        const SizedBox(height: 3),
        Text(
          organisation.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: const Color(0xFF17233D),
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}
