import 'package:flutter/material.dart';

class TutorRequestsScreen extends StatefulWidget {
  const TutorRequestsScreen({super.key});

  @override
  State<TutorRequestsScreen> createState() => _TutorRequestsScreenState();
}

class _TutorRequestsScreenState extends State<TutorRequestsScreen> {
  int _selectedTab = 0; // 0=Pending, 1=Accepted, 2=Declined, 3=Paid

  final List<Map<String, dynamic>> _requests = [
    {
      'name': 'Emma Roberts',
      'university': 'Stanford University',
      'subject': 'Calculus',
      'status': 'Pending',
      'time': '35 mins ago',
      'date': 'Tue, Oct 24',
      'slot': '4:00 PM – 5:30 PM (1.5hrs)',
      'platform': 'Zoom',
      'note': 'Looking for help with derivatives and chain rule before my midterm next Tuesday. Prefer practice problems and step-by-step breakdown.',
      'avatar': 'ER',
    },
    {
      'name': 'Marcus Chen',
      'university': 'MIT',
      'subject': 'Physics',
      'status': 'Pending',
      'time': '1hr ago',
      'date': 'Wed, Oct 25',
      'slot': '2:00 PM – 3:00 PM (1hr)',
      'platform': 'Zoom',
      'note': 'Need to review kinematics equations. I\'m struggling with projectile motion concepts and...',
      'avatar': 'MC',
    },
    {
      'name': 'Sophia Patel',
      'university': 'UCLA',
      'subject': 'Chemistry',
      'status': 'Pending',
      'time': '3hrs ago',
      'date': 'Thu, Oct 26',
      'slot': '5:00 PM – 6:00 PM (1hr)',
      'platform': 'Zoom',
      'note': 'Struggling with stoichiometry and redox reactions ahead of chapter test on Thursday.',
      'avatar': 'SP',
    },
    {
      'name': 'Liam Walker',
      'university': 'Harvard',
      'subject': 'Statistics',
      'status': 'Accepted',
      'time': 'Confirmed yesterday',
      'date': 'Fri, Oct 27',
      'slot': '3:30 PM – 4:30 PM (1hr)',
      'platform': 'Zoom',
      'note': 'Confirmed session on hypothesis testing and p-values for intro data science.',
      'avatar': 'LW',
    },
  ];

  List<Map<String, dynamic>> get _filteredRequests {
    switch (_selectedTab) {
      case 0:
        return _requests.where((r) => r['status'] == 'Pending').toList();
      case 1:
        return _requests.where((r) => r['status'] == 'Accepted').toList();
      case 2:
        return _requests.where((r) => r['status'] == 'Declined').toList();
      case 3:
        return _requests.where((r) => r['status'] == 'Paid').toList();
      default:
        return _requests;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Pending':
        return const Color(0xFFFFA500);
      case 'Accepted':
        return const Color(0xFF28C76F);
      case 'Declined':
        return const Color(0xFFEA5455);
      case 'Paid':
        return const Color(0xFF1457D9);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _requests.where((r) => r['status'] == 'Pending').length;
    final accepted = _requests.where((r) => r['status'] == 'Accepted').length;

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
                      Text(
                        'THEO TUTORING',
                        style: TextStyle(
                          color: const Color(0xFF1457D9),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Requests',
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
                  _buildTab('Pending', 0, badge: pending),
                  const SizedBox(width: 8),
                  _buildTab('Accepted', 1, badge: accepted),
                  const SizedBox(width: 8),
                  _buildTab('Declined', 2),
                  const SizedBox(width: 8),
                  _buildTab('Paid', 3),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Request list
            Expanded(
              child: _filteredRequests.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filteredRequests.length,
                      itemBuilder: (context, index) {
                        final request = _filteredRequests[index];
                        return _buildRequestCard(request);
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTab(String label, int index, {int badge = 0}) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            if (badge > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white24 : const Color(0xFF1457D9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    return GestureDetector(
      onTap: () => _showRequestDetails(request),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141928),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E2235)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF1457D9).withOpacity(0.2),
                  child: Text(
                    request['avatar'],
                    style: const TextStyle(
                      color: Color(0xFF1457D9),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['name'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Requested ${request['time']}',
                        style: const TextStyle(color: Color(0xFF9295A3), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(request['status']).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor(request['status']).withOpacity(0.4)),
                  ),
                  child: Text(
                    request['subject'],
                    style: TextStyle(
                      color: const Color(0xFF9295A3),
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(request['status']).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    request['status'],
                    style: TextStyle(
                      color: _statusColor(request['status']),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              request['note'],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF9295A3), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 13, color: Color(0xFF9295A3)),
                const SizedBox(width: 4),
                Text(
                  '${request['date']}  •  ${request['slot']}',
                  style: const TextStyle(color: Color(0xFF9295A3), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.videocam_outlined, size: 13, color: Color(0xFF9295A3)),
                const SizedBox(width: 4),
                Text(
                  request['platform'],
                  style: const TextStyle(color: Color(0xFF9295A3), fontSize: 12),
                ),
              ],
            ),
            if (request['status'] == 'Pending') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showRequestDetails(request),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1457D9),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('View', style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ),
            ],
            if (request['status'] == 'Accepted') ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF28C76F), size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Calendar Synced',
                    style: TextStyle(color: Color(0xFF28C76F), fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      'View Session →',
                      style: TextStyle(color: Color(0xFF1457D9), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(
            'All caught up!',
            style: TextStyle(color: Colors.grey[400], fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'New student booking requests\nwill arrive here in real-time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Adjust Availability'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[400],
              side: BorderSide(color: Colors.grey[700]!),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  void _showRequestDetails(Map<String, dynamic> request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RequestDetailsSheet(request: request),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141928),
        border: Border(top: BorderSide(color: Color(0xFF1E2235))),
      ),
      child: BottomNavigationBar(
        currentIndex: 1,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: const Color(0xFF1457D9),
        unselectedItemColor: const Color(0xFF9295A3),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (index) {
          // Navigation handled by parent
        },
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

// ── Request Details Bottom Sheet ──────────────────────────────────────────────

class _RequestDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> request;
  const _RequestDetailsSheet({required this.request});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.6,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2D3E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Top row
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Request Details',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.more_horiz, color: Color(0xFF9295A3)),
              ],
            ),
            const SizedBox(height: 20),

            // ID & time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1457D9).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    request['subject'].toString().toUpperCase(),
                    style: const TextStyle(color: Color(0xFF1457D9), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA500).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Pending Review',
                    style: TextStyle(color: Color(0xFFFFA500), fontSize: 11),
                  ),
                ),
                const Spacer(),
                Text(
                  'Received ${request['time']}',
                  style: const TextStyle(color: Color(0xFF9295A3), fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Date & time
            Text(
              request['date'].toString().replaceAll(',', ','),
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Color(0xFF9295A3)),
                const SizedBox(width: 4),
                Text(
                  request['slot'],
                  style: const TextStyle(color: Color(0xFF9295A3), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Format
            _detailRow('FORMAT', request['platform'] == 'Zoom' ? 'Online (Theo Meet)' : request['platform'],
                Icons.videocam_outlined),
            const SizedBox(height: 16),

            // Student note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141928),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E2235)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.format_quote, color: Color(0xFF9295A3), size: 16),
                      SizedBox(width: 6),
                      Text('STUDENT NOTE', style: TextStyle(color: Color(0xFF9295A3), fontSize: 11, letterSpacing: 1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '"${request['note']}"',
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Student info
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF1457D9).withOpacity(0.2),
                  child: Text(
                    request['avatar'],
                    style: const TextStyle(color: Color(0xFF1457D9), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['name'],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text(
                      request['university'],
                      style: const TextStyle(color: Color(0xFF9295A3), fontSize: 12),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Color(0xFFFFA500), size: 14),
                        const Text(' 4.9', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Schedule conflict section
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141928),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E2235)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Color(0xFF9295A3)),
                      const SizedBox(width: 6),
                      Text(
                        'Your Schedule On This Day  ${request['date']}',
                        style: const TextStyle(color: Color(0xFF9295A3), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _scheduleBlock('1:30 PM – 2:30 PM', 'Intro to Python • David Kim', const Color(0xFF2A2D3E), false),
                  const SizedBox(height: 6),
                  _scheduleBlock('4:30 PM – 5:30 PM', 'Advanced Essay Writing • Sarah Jenkins', const Color(0xFFEA5455), true),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF28C76F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF28C76F).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Text('6:00 PM – 7:30 PM  Suggested Open Window',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Propose', style: TextStyle(color: Color(0xFF1457D9), fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEA5455),
                      side: const BorderSide(color: Color(0xFFEA5455)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('✕  Decline', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1457D9),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('✓  Accept Request', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF9295A3)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF9295A3), fontSize: 10, letterSpacing: 1)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _scheduleBlock(String time, String title, Color color, bool isConflict) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time, style: const TextStyle(color: Color(0xFF9295A3), fontSize: 11)),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          if (isConflict)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEA5455).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('CONFLICT', style: TextStyle(color: Color(0xFFEA5455), fontSize: 10)),
            ),
        ],
      ),
    );
  }
}