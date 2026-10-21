import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'tutor_booking_detail.dart';

// ── Model ──────────────────────────────────────────────────────────────────

class ScheduleSession {
  final int bookingId;
  final String subject;
  final String studentName;
  final String? studentPhoto;
  final String? studentUniversity;
  final String date;
  final String startTime;
  final String endTime;
  final String duration;
  final String status;
  final String? link;
  final String? note;
  final String platform;
  final String? confirmedAgo;
  final bool isRecurring;

  const ScheduleSession({
    required this.bookingId,
    required this.subject,
    required this.studentName,
    this.studentPhoto,
    this.studentUniversity,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.duration = '1 hr',
    required this.status,
    this.link,
    this.note,
    required this.platform,
    this.confirmedAgo,
    this.isRecurring = false,
  });

  factory ScheduleSession.fromJson(Map<String, dynamic> j) => ScheduleSession(
        bookingId: int.tryParse(j['bookingId']?.toString() ?? '') ?? 0,
        subject: j['subject']?.toString() ?? '',
        studentName: j['studentName']?.toString() ?? '',
        studentPhoto: j['studentPhoto']?.toString(),
        studentUniversity: j['studentUniversity']?.toString(),
        date: j['date']?.toString() ?? '',
        startTime: j['startTime']?.toString() ?? '',
        endTime: j['endTime']?.toString() ?? '',
        duration: j['duration']?.toString() ?? '1 hr',
        status: j['status']?.toString() ?? '',
        link: j['link']?.toString(),
        note: j['note']?.toString(),
        platform: j['platform']?.toString() ?? 'online',
        confirmedAgo: j['confirmedAgo']?.toString(),
        isRecurring: j['isRecurring'] == true,
      );

  String get platformLabel {
    switch (platform.toLowerCase()) {
      case 'zoom':        return 'Zoom';
      case 'google_meet':
      case 'meet':        return 'Google Meet';
      case 'in_person':
      case 'in-person':  return 'In-person';
      default:            return 'Online';
    }
  }

  IconData get platformIcon {
    switch (platform.toLowerCase()) {
      case 'zoom':
      case 'google_meet':
      case 'meet':        return Icons.videocam_outlined;
      case 'in_person':
      case 'in-person':  return Icons.location_on_outlined;
      default:            return Icons.videocam_outlined;
    }
  }
}

// ── Service ────────────────────────────────────────────────────────────────

class TutorScheduleService {
  static String get _base =>
      kIsWeb ? 'http://localhost:8080' : 'http://10.0.2.2:8080';

  static Future<Map<String, dynamic>> fetchSchedule(String filter) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    final res = await http.get(
      Uri.parse('$_base/tutor/schedule?filter=$filter'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) throw Exception('Failed to load schedule');
    final data = jsonDecode(res.body) as Map<String, dynamic>;

    final grouped = <String, List<ScheduleSession>>{};
    ((data['grouped'] ?? {}) as Map<String, dynamic>).forEach((label, list) {
      grouped[label] = (list as List)
          .map((s) => ScheduleSession.fromJson(s as Map<String, dynamic>))
          .toList();
    });

    return {
      'grouped': grouped,
      'badges': (data['badges'] as Map<String, dynamic>?) ?? {},
    };
  }
}

// ── Screen ────────────────────────────────────────────────────────────────

class TutorScheduleScreen extends StatefulWidget {
  const TutorScheduleScreen({super.key});

  @override
  State<TutorScheduleScreen> createState() => _TutorScheduleScreenState();
}

class _TutorScheduleScreenState extends State<TutorScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _dateFilter = 'All Dates';
  Map<String, List<ScheduleSession>> _grouped = {};
  Map<String, dynamic> _badges = {};
  bool _loading = true;
  String? _error;

  static const _tabs        = ['Upcoming', 'New', 'Past', 'All'];
  static const _dateFilters = ['All Dates', 'Today', 'Tomorrow', 'This Week'];

  static const _blue   = Color(0xFF246BFE);
  static const _bg     = Color(0xFFF2F4F8);
  static const _card   = Colors.white;
  static const _border = Color(0xFFE5E7EB);
  static const _muted  = Color(0xFF6B7280);
  static const _text1  = Color(0xFF111827);
  static const _text2  = Color(0xFF374151);

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
      final result = await TutorScheduleService.fetchSchedule(
          _tabs[_tabController.index].toLowerCase());
      if (mounted) setState(() {
        _grouped = result['grouped'] as Map<String, List<ScheduleSession>>;
        _badges  = result['badges']  as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
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
            children: const [
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
            child: const Icon(Icons.person, color: Colors.white, size: 22),
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
          final count = _badges[t];
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
                      onTap: () => setState(() => _dateFilter = f),
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
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.tune, color: _muted, size: 16),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: _muted, size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _blue, foregroundColor: Colors.white),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_grouped.isEmpty) return _buildEmpty();
    return RefreshIndicator(
      onRefresh: _load,
      color: _blue,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ..._grouped.entries.map((e) => _buildDateGroup(e.key, e.value)),
          _buildAllCaughtUp(),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
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
                  color: _blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(50)),
              child:
                  const Icon(Icons.mail_outline, color: _blue, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('All caught up!',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _text1)),
            const SizedBox(height: 8),
            const Text(
                'New student booking requests will arrive\nhere in real-time.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildAllCaughtUp() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(50)),
            child:
                const Icon(Icons.mail_outline, color: _blue, size: 28),
          ),
          const SizedBox(height: 14),
          const Text('All caught up!',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _text1)),
          const SizedBox(height: 6),
          const Text(
              'New student booking requests will arrive\nhere in real-time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _muted)),
        ],
      ),
    );
  }

  Widget _buildDateGroup(String label, List<ScheduleSession> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(label,
                  style: const TextStyle(
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
    final parts = s.studentName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : s.studentName.isNotEmpty
            ? s.studentName[0].toUpperCase()
            : '?';

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
                              style: const TextStyle(
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
                    if (s.confirmedAgo != null) ...[
                      const SizedBox(height: 2),
                      Text(s.confirmedAgo!,
                          style:
                              const TextStyle(fontSize: 11, color: _muted)),
                    ],
                    if (s.studentUniversity != null) ...[
                      const SizedBox(height: 1),
                      Text(s.studentUniversity!,
                          style:
                              const TextStyle(fontSize: 11, color: _muted)),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text('${s.startTime} – ${s.endTime}',
              style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 3),

          Text(s.subject,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _text1)),

          if (s.note != null && s.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"${s.note}"',
                style: const TextStyle(
                    fontSize: 12,
                    color: _muted,
                    fontStyle: FontStyle.italic,
                    height: 1.5)),
          ],

          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 13, color: _muted),
              const SizedBox(width: 4),
              Text(s.date,
                  style: const TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(width: 12),
              const Icon(Icons.access_time_outlined,
                  size: 13, color: _muted),
              const SizedBox(width: 4),
              Text('${s.startTime} – ${s.endTime} (${s.duration})',
                  style: const TextStyle(fontSize: 12, color: _muted)),
            ],
          ),
          const SizedBox(height: 4),

          Row(
            children: [
              Icon(s.platformIcon, size: 13, color: _muted),
              const SizedBox(width: 4),
              Text(s.platformLabel,
                  style: const TextStyle(fontSize: 12, color: _muted)),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFFE5E7EB), height: 1),
          const SizedBox(height: 12),

          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.link, size: 13),
                label: const Text('Session link',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blue,
                  side: const BorderSide(color: _border),
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
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TutorBookingDetailScreen(
                        bookingId: s.bookingId),
                  ),
                ),
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
        onTap: (_) {},
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
