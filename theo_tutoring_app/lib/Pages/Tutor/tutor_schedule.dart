import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tutor_api.dart';
import 'tutor_booking_detail.dart';
import 'tutor_format.dart';
import 'tutor_nav.dart';
import 'tutor_theme.dart';

// ── Model ──────────────────────────────────────────────────────────────────

class ScheduleSession {
  final int bookingId;
  final String subject;
  final String studentName;
  final String? studentPhoto;
  final String date;
  final String startTime;
  final String endTime;
  final String duration;
  final String status;
  final String? link;
  final String? note;
  final String platform;
  final String? statusAgo; // "Confirmed 25m ago" / "Requested 2h ago"

  const ScheduleSession({
    required this.bookingId,
    required this.subject,
    required this.studentName,
    this.studentPhoto,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.status,
    this.link,
    this.note,
    required this.platform,
    this.statusAgo,
  });

  // One session card from GET /TutorLandingpage/schedule
  factory ScheduleSession.fromJson(Map<String, dynamic> j) {
    final student = j['student'] as Map<String, dynamic>? ?? const {};
    final status = j['status']?.toString() ?? '';
    final requested = j['requestedMinutesAgo'] as int?;
    final confirmed = j['confirmedMinutesAgo'] as int?;
    final link = j['link']?.toString();
    return ScheduleSession(
      bookingId: j['bookingId'] as int? ?? 0,
      subject: j['subject']?.toString() ?? '',
      studentName: student['name']?.toString() ?? '',
      studentPhoto: student['profilePhotoUrl']?.toString(),
      date: j['date']?.toString() ?? '',
      startTime: j['startTime']?.toString() ?? '',
      endTime: j['endTime']?.toString() ?? '',
      duration: durationLabel(j['durationMinutes'] as int?),
      status: status,
      link: link,
      note: j['note']?.toString(),
      platform: platformOf(link),
      statusAgo: switch (status) {
        'Pending' when requested != null => 'Requested ${timeAgo(requested)}',
        'Confirmed' when confirmed != null => 'Confirmed ${timeAgo(confirmed)}',
        'Completed' => 'Completed',
        _ => null,
      },
    );
  }

  String get platformLabel {
    switch (platform) {
      case 'zoom':  return 'Zoom';
      case 'meet':  return 'Google Meet';
      case 'teams': return 'Microsoft Teams';
      case 'none':  return 'Session link not added yet';
      default:      return 'Online';
    }
  }

  IconData get platformIcon =>
      platform == 'none' ? Icons.link_off : Icons.videocam_outlined;

  /// Join session opens the tutor's own Meet room straight away, with no
  /// time limit (Google Meet design, section 3), for a lesson that is going
  /// ahead.
  bool get canJoin =>
      link != null &&
      link!.isNotEmpty &&
      (status == 'Confirmed' || status == 'Postponed');
}

/// One day heading with its sessions ("Today, 30 Sep  2 sessions").
class ScheduleDay {
  final String label;
  final List<ScheduleSession> sessions;

  const ScheduleDay({required this.label, required this.sessions});

  factory ScheduleDay.fromJson(Map<String, dynamic> j) => ScheduleDay(
        label: dayHeading(
            j['date']?.toString(), j['daysFromToday'] as int?),
        sessions: (j['sessions'] as List<dynamic>? ?? [])
            .map((s) => ScheduleSession.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

// ── Screen ────────────────────────────────────────────────────────────────

class TutorScheduleScreen extends StatefulWidget {
  const TutorScheduleScreen({
    super.key,
    this.loadSchedule = fetchTutorSchedule,
  });

  /// Loads the page; tests pass their own.
  final Future<Map<String, dynamic>> Function({
    String tab,
    String date,
    List<int> subjectIds,
  }) loadSchedule;

  @override
  State<TutorScheduleScreen> createState() => _TutorScheduleScreenState();
}

class _TutorScheduleScreenState extends State<TutorScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _dateFilter = 'All Dates';
  List<ScheduleDay> _days = [];
  Map<String, dynamic> _badges = {};
  List<Map<String, dynamic>> _subjects = []; // for the filter icon
  final Set<int> _subjectFilter = {};
  String? _tutorName;
  String? _tutorPhoto;
  bool _loading = true;
  String? _error;
  int? _errorStatus; // HTTP status of the failed load (403 = not approved yet)

  static const _tabs        = ['Upcoming', 'New', 'Past', 'All'];
  static const _dateFilters = ['All Dates', 'Today', 'Tomorrow', 'This Week'];

  // Values the backend expects for ?tab= and ?date=
  static const _tabParams  = ['upcoming', 'new', 'past', 'all'];
  static const _dateParams = {
    'All Dates': 'all',
    'Today': 'today',
    'Tomorrow': 'tomorrow',
    'This Week': 'week',
  };

  static const _blue   = Color(0xFF246BFE);

  // Light colours, or the dark ones when the tutor turned on Dark Mode
  bool get _dk => context.tutorDark;
  Color get _bg => _dk ? TutorDark.background : const Color(0xFFF2F4F8);
  Color get _card => _dk ? TutorDark.card : Colors.white;
  Color get _border => _dk ? TutorDark.border : const Color(0xFFE5E7EB);
  Color get _muted => _dk ? TutorDark.textMuted : const Color(0xFF6B7280);
  Color get _text1 => _dk ? TutorDark.text : const Color(0xFF111827);
  // the student's note
  Color get _text2 => _dk ? TutorDark.textSecondary : const Color(0xFF374151);
  // "No note from the student."
  Color get _faint => _dk ? TutorDark.textFaint : const Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) _load();
      });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.loadSchedule(
        tab: _tabParams[_tabController.index],
        date: _dateParams[_dateFilter]!,
        subjectIds: _subjectFilter.toList(),
      );
      final tutor = data['tutor'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _days = (data['days'] as List<dynamic>? ?? [])
              .map((d) => ScheduleDay.fromJson(d as Map<String, dynamic>))
              .toList();
          _badges = data['counts'] as Map<String, dynamic>? ?? {};
          _subjects = (data['subjects'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          _tutorName = tutor?['name']?.toString();
          _tutorPhoto = tutor?['profilePhotoUrl']?.toString();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _errorStatus = e is TutorApiException ? e.statusCode : null;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openBooking(ScheduleSession s) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TutorBookingDetailScreen(bookingId: s.bookingId),
      ),
    );
    if (changed == true) _load(); // postponed: it moved to another day
  }

  Future<void> _joinSession(ScheduleSession s) async {
    final opened = await launchUrl(
      Uri.parse(s.link!),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Meet could not be opened.')),
      );
    }
  }

  Future<void> _pickSubjects() async {
    final picked = Set<int>.of(_subjectFilter);
    final apply = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter by subject',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text1)),
                const SizedBox(height: 8),
                if (_subjects.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('You have no subjects yet.',
                        style: TextStyle(color: _muted, fontSize: 13)),
                  ),
                ..._subjects.map((s) {
                  final id = s['subjectId'] as int;
                  return CheckboxListTile(
                    value: picked.contains(id),
                    activeColor: _blue,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s['subjectName']?.toString() ?? '',
                        style: TextStyle(fontSize: 14, color: _text1)),
                    onChanged: (on) => setSheet(() {
                      on == true ? picked.add(id) : picked.remove(id);
                    }),
                  );
                }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setSheet(picked.clear),
                      child: Text('Clear',
                          style: TextStyle(color: _muted)),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          elevation: 0),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (apply != true) return;
    _subjectFilter
      ..clear()
      ..addAll(picked);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            _buildDateFilters(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _card,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('THEO TUTORING',
                  style: TextStyle(
                      color: _blue,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
              SizedBox(height: 2),
              Text('Schedule',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _text1)),
            ],
          ),
          CircleAvatar(
            radius: 20,
            backgroundColor: _blue,
            backgroundImage:
                _tutorPhoto != null ? NetworkImage(_tutorPhoto!) : null,
            child: _tutorPhoto != null
                ? null
                : _tutorName != null
                    ? Text(initialsOf(_tutorName!),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700))
                    : const Icon(Icons.person, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: _card,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: _blue,
        unselectedLabelColor: _muted,
        indicatorColor: _blue,
        indicatorWeight: 2,
        labelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: _tabs.map((t) {
          final count = _badges[t.toLowerCase()];
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t),
                if (count != null && (count as num) > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: _blue,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateFilters() {
    final filtering = _subjectFilter.isNotEmpty;
    return Container(
      color: _card,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _dateFilters.map((f) {
                  final sel = _dateFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        if (sel) return;
                        setState(() => _dateFilter = f);
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? _blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? _blue : _border),
                        ),
                        child: Text(f,
                            style: TextStyle(
                                color: sel ? Colors.white : _muted,
                                fontSize: 12,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _pickSubjects,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: filtering ? _blue : _border,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.tune,
                  color: filtering ? Colors.white : _muted, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    if (_error != null) {
      // 403: a Pending tutor, whose schedule opens once they are approved
      final pending = _errorStatus == 403;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(pending ? Icons.hourglass_top_rounded : Icons.wifi_off_rounded,
                  color: _muted, size: 40),
              const SizedBox(height: 12),
              Text(
                  pending
                      ? 'Your schedule opens once your tutor application '
                          'has been approved.'
                      : _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed:
                    pending ? () => openTutorTab(context, 0, current: 1) : _load,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _blue, foregroundColor: Colors.white),
                child: Text(pending ? 'Back to Dashboard' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _blue,
      child: _days.isEmpty
          // a scrollable list, so pull-to-refresh still works when empty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [_buildEmpty()],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                ..._days.map((d) => _buildDateGroup(d.label, d.sessions)),
              ],
            ),
    );
  }

  bool get _filtering =>
      _dateFilter != _dateFilters.first || _subjectFilter.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _dateFilter = _dateFilters.first;
      _subjectFilter.clear();
    });
    _load();
  }

  // What to say when a tab has nothing to show
  Widget _buildEmpty() {
    final (IconData icon, String title, String message) = _filtering
        ? (
            Icons.filter_alt_off_outlined,
            'No sessions match your filters',
            'Try another date or subject, or clear the filters.',
          )
        : switch (_tabController.index) {
            0 => (
                Icons.event_available_outlined,
                'No upcoming sessions',
                'Sessions appear here once a student has booked and paid.',
              ),
            1 => (
                Icons.mail_outline,
                'All caught up!',
                'New booking requests from students will arrive here.',
              ),
            2 => (
                Icons.history_rounded,
                'No past sessions yet',
                'Sessions you have finished will be listed here.',
              ),
            _ => (
                Icons.calendar_month_outlined,
                'No sessions yet',
                'Your confirmed and completed sessions will appear here.',
              ),
          };

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(50)),
            child: Icon(icon, color: _blue, size: 32),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _text1)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _muted)),
          if (_filtering) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _clearFilters,
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: BorderSide(color: _border),
              ),
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateGroup(String label, List<ScheduleSession> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day heading, centred: "Today, 24 Oct  [2 sessions]"
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _text1)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: _blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                    '${sessions.length} session${sessions.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: _blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        ...sessions.map(_buildSessionCard),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSessionCard(ScheduleSession s) {
    final initials = initialsOf(s.studentName);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student row
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: s.studentPhoto != null
                    ? NetworkImage(s.studentPhoto!)
                    : null,
                backgroundColor: _blue.withOpacity(0.2),
                child: s.studentPhoto == null
                    ? Text(initials,
                        style: const TextStyle(
                            color: _blue,
                            fontSize: 13,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(s.studentName,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _text1)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: _blue.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(s.subject,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: _blue,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                    if (s.statusAgo != null) ...[
                      const SizedBox(height: 2),
                      Text(s.statusAgo!,
                          style:
                              TextStyle(fontSize: 11, color: _muted)),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text('${s.startTime} – ${s.endTime}',
              style: TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 3),

          Text(s.subject,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _text1)),

          // The note the student wrote when booking (Booking.Note)
          const SizedBox(height: 6),
          if (s.note != null && s.note!.trim().isNotEmpty)
            Text('"${s.note!.trim()}"',
                style: TextStyle(
                    fontSize: 12.5,
                    color: _text2,
                    fontStyle: FontStyle.italic,
                    height: 1.5))
          else
            Text('No note from the student.',
                style: TextStyle(
                    fontSize: 12,
                    color: _faint,
                    fontStyle: FontStyle.italic,
                    height: 1.5)),

          const SizedBox(height: 10),

          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 13, color: _muted),
                  const SizedBox(width: 4),
                  Text(formatLongDate(s.date),
                      style: TextStyle(fontSize: 12, color: _muted)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_outlined,
                      size: 13, color: _muted),
                  const SizedBox(width: 4),
                  Text('${s.startTime} – ${s.endTime} (${s.duration})',
                      style: TextStyle(fontSize: 12, color: _muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),

          Row(
            children: [
              Icon(s.platformIcon, size: 13, color: _muted),
              const SizedBox(width: 4),
              Text(s.platformLabel,
                  style: TextStyle(fontSize: 12, color: _muted)),
            ],
          ),

          const SizedBox(height: 12),
          Divider(color: _border, height: 1),
          const SizedBox(height: 12),

          Row(
            children: [
              OutlinedButton.icon(
                onPressed: s.canJoin ? () => _joinSession(s) : null,
                icon: const Icon(Icons.videocam_outlined, size: 13),
                label: const Text('Join session',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blue,
                  side: BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _openBooking(s),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('View',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: 1,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: _blue,
        unselectedItemColor: _muted,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (i) => openTutorTab(context, i, current: 1),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded), label: 'Schedule'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}
