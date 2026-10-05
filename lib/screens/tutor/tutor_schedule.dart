import 'package:flutter/material.dart';

class TutorScheduleScreen extends StatefulWidget {
  const TutorScheduleScreen({super.key});

  @override
  State<TutorScheduleScreen> createState() => _TutorScheduleScreenState();
}

class _TutorScheduleScreenState extends State<TutorScheduleScreen> {
  int _selectedTab = 0; // 0=Upcoming, 1=Past, 2=All

  final List<Map<String, dynamic>> _sessions = [
    {
      'group': 'Today, 30 Sep',
      'sessions': [
        {
          'time': '3:00 PM – 4:00 PM',
          'title': 'Advanced Essay Writing',
          'subtitle': null,
          'tag': 'Join Room',
          'tagColor': Color(0xFF1457D9),
          'note': 'Starts in 45m',
          'platform': 'online',
          'hasLink': true,
        },
        {
          'time': '5:30 PM – 6:30 PM',
          'title': 'Intro to Python',
          'subtitle': null,
          'tag': null,
          'tagColor': null,
          'note': null,
          'platform': 'online',
          'hasLink': false,
        },
      ],
    },
    {
      'group': 'Tomorrow, 1 Oct',
      'sessions': [
        {
          'time': '10:00 AM – 11:30 AM',
          'title': 'Calculus III: Multivariable',
          'subtitle': null,
          'tag': 'Session link',
          'tagColor': Color(0xFF1457D9),
          'note': 'Prep notes shared',
          'platform': 'online',
          'hasLink': true,
        },
        {
          'time': '2:00 PM – 3:00 PM',
          'title': 'Physics: Kinematics',
          'subtitle': 'Student Academic Commons #4',
          'tag': null,
          'tagColor': null,
          'note': null,
          'platform': 'in-person',
          'hasLink': false,
        },
      ],
    },
    {
      'group': 'Fri, 3 Oct',
      'sessions': [
        {
          'time': '4:00 PM – 5:00 PM',
          'title': 'Organic Chemistry Reactions',
          'subtitle': null,
          'tag': 'Session link',
          'tagColor': Color(0xFF1457D9),
          'note': 'Materials attached',
          'platform': 'online',
          'hasLink': true,
        },
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'THEO TUTORING',
                        style: TextStyle(
                          color: Color(0xFF1457D9),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Schedule',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF1457D9),
                    child: const Icon(Icons.person, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildTab('Upcoming', 0, count: 5),
                  const SizedBox(width: 8),
                  _buildTab('Past', 1),
                  const SizedBox(width: 8),
                  _buildTab('All', 2),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Session list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _sessions.length,
                itemBuilder: (context, groupIndex) {
                  final group = _sessions[groupIndex];
                  final sessions = group['sessions'] as List;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            group['group'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1457D9).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${sessions.length} session${sessions.length > 1 ? 's' : ''}',
                              style: const TextStyle(color: Color(0xFF1457D9), fontSize: 11),
                            ),
                          ),
                          const Spacer(),
                          if (groupIndex == 0)
                            const Text(
                              'Eastern Time',
                              style: TextStyle(color: Color(0xFF9295A3), fontSize: 11),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...sessions.map((session) => _buildSessionCard(session)),
                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTab(String label, int index, {int count = 0}) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1457D9) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF1457D9) : const Color(0xFF2A2D3E),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '($count)',
                style: TextStyle(
                  color: isSelected ? Colors.white70 : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final isOnline = session['platform'] == 'online';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141928),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time column
          SizedBox(
            width: 100,
            child: Text(
              session['time'],
              style: const TextStyle(color: Color(0xFF9295A3), fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session['title'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (session['subtitle'] != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF9295A3)),
                      const SizedBox(width: 4),
                      Text(
                        session['subtitle'],
                        style: const TextStyle(color: Color(0xFF9295A3), fontSize: 12),
                      ),
                    ],
                  ),
                ],
                if (session['tag'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (session['tagColor'] as Color).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              session['hasLink'] ? Icons.videocam_outlined : Icons.link,
                              size: 12,
                              color: session['tagColor'] as Color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              session['tag'],
                              style: TextStyle(
                                color: session['tagColor'] as Color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (session['note'] != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          session['note'],
                          style: const TextStyle(color: Color(0xFF9295A3), fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Platform icon
          Icon(
            isOnline ? Icons.videocam_outlined : Icons.location_on_outlined,
            color: const Color(0xFF9295A3),
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141928),
        border: Border(top: BorderSide(color: Color(0xFF1E2235))),
      ),
      child: BottomNavigationBar(
        currentIndex: 2,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: const Color(0xFF1457D9),
        unselectedItemColor: const Color(0xFF9295A3),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (index) {},
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.inbox_rounded), label: 'Requests'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'Schedule'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}