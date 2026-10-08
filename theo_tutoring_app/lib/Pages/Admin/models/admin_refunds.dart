import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────

enum DisputeStatus { open, pending, pendingOverride, pendingReview, denied, approved }

enum IssueType { technicalIssue, tutorNoShow, disputedQuality, lateCancellation }

class Dispute {
  final String txnId;
  final String studentName;
  final String tutorName;
  final IssueType issueType;
  final String amount;
  final DisputeStatus status;

  const Dispute({
    required this.txnId,
    required this.studentName,
    required this.tutorName,
    required this.issueType,
    required this.amount,
    required this.status,
  });
}

// ─────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────

class AdminRefundsIssuesScreen extends StatefulWidget {
  const AdminRefundsIssuesScreen({super.key});

  @override
  State<AdminRefundsIssuesScreen> createState() => _AdminRefundsIssuesScreenState();
}

class _AdminRefundsIssuesScreenState extends State<AdminRefundsIssuesScreen> {
  int _selectedFilter = 0; // 0=All, 1=No Show, 2=Tech Issue, 3=Quality
  int _selectedDisputeIndex = 0;

  static const _filters = ['All Issues', 'No Show', 'Tech Issue', 'Quality'];

  final List<Dispute> _disputes = const [
    Dispute(
      txnId: 'TXN-8924A',
      studentName: 'Sarah Jenkins',
      tutorName: 'Dr. Robert Chen',
      issueType: IssueType.technicalIssue,
      amount: 'R810.00',
      status: DisputeStatus.pendingOverride,
    ),
    Dispute(
      txnId: 'TXN-8923B',
      studentName: 'Michael Chang',
      tutorName: 'Elena Rostova',
      issueType: IssueType.tutorNoShow,
      amount: 'R1,080.00',
      status: DisputeStatus.pendingReview,
    ),
    Dispute(
      txnId: 'TXN-8919F',
      studentName: 'Emily Watson',
      tutorName: 'David Kim',
      issueType: IssueType.disputedQuality,
      amount: 'R640.00',
      status: DisputeStatus.denied,
    ),
    Dispute(
      txnId: 'TXN-8901X',
      studentName: 'Ahmed Al-Farsi',
      tutorName: 'Sarah Jenkins',
      issueType: IssueType.lateCancellation,
      amount: '-R360.00',
      status: DisputeStatus.approved,
    ),
  ];

  // Colors
  static const Color _bg = Color(0xFF0D1117);
  static const Color _surface = Color(0xFF161B22);
  static const Color _surface2 = Color(0xFF1C2333);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _accent = Color(0xFF1457D9);
  static const Color _green = Color(0xFF3FB950);
  static const Color _yellow = Color(0xFFD29922);
  static const Color _red = Color(0xFFF85149);
  static const Color _purple = Color(0xFFBC8CFF);

  List<Dispute> get _filteredDisputes {
    if (_selectedFilter == 0) return _disputes;
    final type = [
      null,
      IssueType.tutorNoShow,
      IssueType.technicalIssue,
      IssueType.disputedQuality,
    ][_selectedFilter];
    return _disputes.where((d) => d.issueType == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          _Sidebar(currentRoute: 'refunds'),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: 'Refunds & Issues'),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildMain()),
                      _buildRightPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(),
          const SizedBox(height: 20),
          _buildDisputeTable(),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatCard(label: 'Open Disputes', value: '42', delta: '↑ +5 this week', deltaColor: _red),
        const SizedBox(width: 14),
        _StatCard(label: 'Pending Refunds', value: 'R58,320', delta: '18 requests', deltaColor: _fgMid),
        const SizedBox(width: 14),
        _StatCard(label: 'Resolved (7D)', value: '156', delta: '✓ 94% SLA met', deltaColor: _green),
        const SizedBox(width: 14),
        _StatCard(
          label: 'Admin Action Required',
          value: '3',
          valueColor: _red,
          delta: 'Overrides pending',
          deltaColor: _red,
        ),
      ].map((w) => Expanded(child: w)).toList(),
    );
  }

  Widget _buildDisputeTable() {
    final disputes = _filteredDisputes;
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Text('Disputes', style: TextStyle(color: _fg, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                Row(
                  children: List.generate(_filters.length, (i) {
                    final active = i == _selectedFilter;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedFilter = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: active ? _accent : Colors.transparent,
                            border: Border.all(color: active ? _accent : _border),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _filters[i],
                            style: TextStyle(
                              color: active ? Colors.white : _fgMid,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          // Table header
          Container(
            color: _surface2,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: const [
                Expanded(flex: 2, child: _TableHeader('Transaction ID')),
                Expanded(flex: 3, child: _TableHeader('Student & Tutor')),
                Expanded(flex: 2, child: _TableHeader('Issue Type')),
                Expanded(flex: 2, child: _TableHeader('Amount')),
                Expanded(flex: 2, child: _TableHeader('Status')),
                Expanded(flex: 2, child: _TableHeader('Actions')),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          // Rows
          ...List.generate(disputes.length, (i) {
            final d = disputes[i];
            final selected = _disputes.indexOf(d) == _selectedDisputeIndex;
            return _DisputeRow(
              dispute: d,
              selected: selected,
              onTap: () => setState(() => _selectedDisputeIndex = _disputes.indexOf(d)),
              isLast: i == disputes.length - 1,
            );
          }),
          // Footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text('Showing 1–${disputes.length} of 142 disputes',
                style: const TextStyle(color: _fgMid, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    final dispute = _disputes[_selectedDisputeIndex];
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(left: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dispute.txnId,
                          style: const TextStyle(color: Color(0xFF5B9EFF), fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      const Text('Dispute Review',
                          style: TextStyle(color: _fg, fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                _StatusBadge(dispute.status),
              ],
            ),
            const SizedBox(height: 18),
            const _SectionLabel('PARTIES INVOLVED'),
            const SizedBox(height: 8),
            _PartyRow(initials: _initials(dispute.studentName), name: dispute.studentName, role: 'Student'),
            const SizedBox(height: 8),
            _PartyRow(initials: _initials(dispute.tutorName), name: dispute.tutorName, role: 'Tutor'),
            const SizedBox(height: 16),
            Divider(color: _border),
            const SizedBox(height: 12),
            const _SectionLabel('ISSUE REPORT'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '"The tutor\'s video cut out 10 minutes into our 60-minute session. We tried reconnecting multiple times but couldn\'t establish a stable connection. I\'m requesting a full refund as we couldn\'t complete the lesson."',
                style: TextStyle(color: _fgMid, fontSize: 12.5, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),
            const _SectionLabel('SYSTEM TELEMETRY'),
            const SizedBox(height: 8),
            _TelemetryRow(label: 'Session Duration', value: '47:22'),
            _TelemetryRow(label: 'Connection Quality', value: 'Poor'),
            _TelemetryRow(label: 'Drop Events', value: '4'),
            _TelemetryRow(label: 'Recorded', value: 'Yes'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surface2,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Refund Amount', style: TextStyle(color: _fgMid, fontSize: 11.5)),
                  const SizedBox(height: 4),
                  Text(dispute.amount,
                      style: const TextStyle(color: _fg, fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                child: const Text('✓  Approve Refund', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: BorderSide(color: _red.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                child: const Text('✗  Deny Refund', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF5B9EFF),
                  side: BorderSide(color: _accent.withOpacity(0.4)),
                  backgroundColor: const Color(0xFF1A2540),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                child: const Text('⚡  Force Override Decision', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ─────────────────────────────────────────────
//  Dispute Row
// ─────────────────────────────────────────────

class _DisputeRow extends StatelessWidget {
  final Dispute dispute;
  final bool selected;
  final VoidCallback onTap;
  final bool isLast;

  const _DisputeRow({
    required this.dispute,
    required this.selected,
    required this.onTap,
    required this.isLast,
  });

  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _border = Color(0xFF30363D);
  static const Color _accent = Color(0xFF1457D9);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(0.06) : Colors.transparent,
          border: isLast ? null : Border(bottom: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(dispute.txnId,
                  style: const TextStyle(
                      color: _fgMid, fontSize: 12, fontFamily: 'monospace')),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dispute.studentName,
                      style: const TextStyle(color: _fg, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('↔ ${dispute.tutorName}',
                      style: const TextStyle(color: _fgMid, fontSize: 11.5)),
                ],
              ),
            ),
            Expanded(flex: 2, child: _IssueTypeBadge(dispute.issueType)),
            Expanded(
              flex: 2,
              child: Text(dispute.amount,
                  style: const TextStyle(color: _fg, fontSize: 13)),
            ),
            Expanded(flex: 2, child: _StatusBadge(dispute.status)),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _SmallButton(
                    label: dispute.status == DisputeStatus.approved ||
                            dispute.status == DisputeStatus.denied
                        ? 'View'
                        : 'Review',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Small reusable widgets
// ─────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            color: Color(0xFF8B949E), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.04));
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String delta;
  final Color deltaColor;

  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor,
    required this.delta,
    required this.deltaColor,
  });

  static const Color _surface = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _fgMid, fontSize: 11.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? _fg, fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 4),
          Text(delta, style: TextStyle(color: deltaColor, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _IssueTypeBadge extends StatelessWidget {
  final IssueType type;
  const _IssueTypeBadge(this.type);

  @override
  Widget build(BuildContext context) {
    late String label;
    late Color bg;
    late Color fg;
    switch (type) {
      case IssueType.technicalIssue:
        label = 'Tech Issue';
        bg = const Color(0xFF1A1040);
        fg = const Color(0xFFBC8CFF);
        break;
      case IssueType.tutorNoShow:
        label = 'No Show';
        bg = const Color(0xFF2D1F00);
        fg = const Color(0xFFD29922);
        break;
      case IssueType.disputedQuality:
        label = 'Quality';
        bg = const Color(0xFF1A2540);
        fg = const Color(0xFF5B9EFF);
        break;
      case IssueType.lateCancellation:
        label = 'Late Cancel';
        bg = const Color(0xFF1A2540);
        fg = const Color(0xFF5B9EFF);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final DisputeStatus status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    late String label;
    late Color bg;
    late Color fg;
    switch (status) {
      case DisputeStatus.open:
        label = 'Open';
        bg = const Color(0xFF2D0A09);
        fg = const Color(0xFFF85149);
        break;
      case DisputeStatus.pending:
        label = 'Pending';
        bg = const Color(0xFF2D1F00);
        fg = const Color(0xFFD29922);
        break;
      case DisputeStatus.pendingOverride:
        label = 'Pending Override';
        bg = const Color(0xFF2D1F00);
        fg = const Color(0xFFD29922);
        break;
      case DisputeStatus.pendingReview:
        label = 'Pending Review';
        bg = const Color(0xFF2D1F00);
        fg = const Color(0xFFD29922);
        break;
      case DisputeStatus.denied:
        label = 'Denied';
        bg = const Color(0xFF2D0A09);
        fg = const Color(0xFFF85149);
        break;
      case DisputeStatus.approved:
        label = 'Approved';
        bg = const Color(0xFF0D2818);
        fg = const Color(0xFF3FB950);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2333),
          border: Border.all(color: const Color(0xFF30363D)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _PartyRow extends StatelessWidget {
  final String initials;
  final String name;
  final String role;
  const _PartyRow({required this.initials, required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2333),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: const Color(0xFFD0E4FF),
            child: Text(initials,
                style: const TextStyle(
                    color: Color(0xFF1457D9), fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: Color(0xFFE6EDF3), fontSize: 13, fontWeight: FontWeight.w600)),
              Text(role,
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  final String label;
  final String value;
  const _TelemetryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12.5)),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFFE6EDF3),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: Color(0xFF484F58),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08));
  }
}

// ─────────────────────────────────────────────
//  Shared Sidebar + TopBar
// ─────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final String currentRoute;
  const _Sidebar({required this.currentRoute});

  static const Color _surface = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _fgMuted = Color(0xFF484F58);
  static const Color _accent = Color(0xFF1457D9);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(child: Text('🎓', style: TextStyle(fontSize: 16))),
                ),
                const SizedBox(width: 10),
                const Text('TheoTutor',
                    style: TextStyle(color: _fg, fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          _NavSection(label: 'OVERVIEW', items: [
            _NavItem(icon: '📊', label: 'Dashboard', route: 'dashboard', current: currentRoute),
            _NavItem(icon: '👥', label: 'Users', route: 'users', current: currentRoute),
            _NavItem(icon: '📚', label: 'Sessions', route: 'sessions', current: currentRoute),
          ]),
          _NavSection(label: 'FINANCE', items: [
            _NavItem(icon: '⚖️', label: 'Refunds & Issues', route: 'refunds', current: currentRoute),
            _NavItem(icon: '💳', label: 'Payments', route: 'payments', current: currentRoute),
          ]),
          _NavSection(label: 'SYSTEM', items: [
            _NavItem(icon: '🖥️', label: 'Monitor Platform', route: 'monitor', current: currentRoute),
            _NavItem(icon: '🔔', label: 'Notifications', route: 'notifications', current: currentRoute),
            _NavItem(icon: '⚙️', label: 'Settings', route: 'settings', current: currentRoute),
          ]),
        ],
      ),
    );
  }
}

class _NavSection extends StatelessWidget {
  final String label;
  final List<Widget> items;
  const _NavSection({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF484F58),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1)),
          ),
          ...items,
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String icon;
  final String label;
  final String route;
  final String current;
  const _NavItem(
      {required this.icon, required this.label, required this.route, required this.current});

  @override
  Widget build(BuildContext context) {
    final active = route == current;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1457D9).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: active ? const Color(0xFF5B9EFF) : const Color(0xFF8B949E),
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  static const Color _surface = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _accent = Color(0xFF1457D9);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: _fg, fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFD0E4FF),
            child: const Text('IA',
                style: TextStyle(
                    color: Color(0xFF1457D9), fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────

enum DisputeStatus { open, pending, pendingOverride, pendingReview, denied, approved }

enum IssueType { technicalIssue, tutorNoShow, disputedQuality, lateCancellation }

class Dispute {
  final String txnId;
  final String studentName;
  final String tutorName;
  final IssueType issueType;
  final String amount;
  final DisputeStatus status;

  const Dispute({
    required this.txnId,
    required this.studentName,
    required this.tutorName,
    required this.issueType,
    required this.amount,
    required this.status,
  });
}

// ─────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────

class AdminRefundsIssuesScreen extends StatefulWidget {
  const AdminRefundsIssuesScreen({super.key});

  @override
  State<AdminRefundsIssuesScreen> createState() => _AdminRefundsIssuesScreenState();
}

class _AdminRefundsIssuesScreenState extends State<AdminRefundsIssuesScreen> {
  int _selectedFilter = 0; // 0=All, 1=No Show, 2=Tech Issue, 3=Quality
  int _selectedDisputeIndex = 0;

  static const _filters = ['All Issues', 'No Show', 'Tech Issue', 'Quality'];

  final List<Dispute> _disputes = const [
    Dispute(
      txnId: 'TXN-8924A',
      studentName: 'Sarah Jenkins',
      tutorName: 'Dr. Robert Chen',
      issueType: IssueType.technicalIssue,
      amount: 'R810.00',
      status: DisputeStatus.pendingOverride,
    ),
    Dispute(
      txnId: 'TXN-8923B',
      studentName: 'Michael Chang',
      tutorName: 'Elena Rostova',
      issueType: IssueType.tutorNoShow,
      amount: 'R1,080.00',
      status: DisputeStatus.pendingReview,
    ),
    Dispute(
      txnId: 'TXN-8919F',
      studentName: 'Emily Watson',
      tutorName: 'David Kim',
      issueType: IssueType.disputedQuality,
      amount: 'R640.00',
      status: DisputeStatus.denied,
    ),
    Dispute(
      txnId: 'TXN-8901X',
      studentName: 'Ahmed Al-Farsi',
      tutorName: 'Sarah Jenkins',
      issueType: IssueType.lateCancellation,
      amount: '-R360.00',
      status: DisputeStatus.approved,
    ),
  ];

  // Colors
  static const Color _bg = Color(0xFF0D1117);
  static const Color _surface = Color(0xFF161B22);
  static const Color _surface2 = Color(0xFF1C2333);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _accent = Color(0xFF1457D9);
  static const Color _green = Color(0xFF3FB950);
  static const Color _yellow = Color(0xFFD29922);
  static const Color _red = Color(0xFFF85149);
  static const Color _purple = Color(0xFFBC8CFF);

  List<Dispute> get _filteredDisputes {
    if (_selectedFilter == 0) return _disputes;
    final type = [
      null,
      IssueType.tutorNoShow,
      IssueType.technicalIssue,
      IssueType.disputedQuality,
    ][_selectedFilter];
    return _disputes.where((d) => d.issueType == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          _Sidebar(currentRoute: 'refunds'),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: 'Refunds & Issues'),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildMain()),
                      _buildRightPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(),
          const SizedBox(height: 20),
          _buildDisputeTable(),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatCard(label: 'Open Disputes', value: '42', delta: '↑ +5 this week', deltaColor: _red),
        const SizedBox(width: 14),
        _StatCard(label: 'Pending Refunds', value: 'R58,320', delta: '18 requests', deltaColor: _fgMid),
        const SizedBox(width: 14),
        _StatCard(label: 'Resolved (7D)', value: '156', delta: '✓ 94% SLA met', deltaColor: _green),
        const SizedBox(width: 14),
        _StatCard(
          label: 'Admin Action Required',
          value: '3',
          valueColor: _red,
          delta: 'Overrides pending',
          deltaColor: _red,
        ),
      ].map((w) => Expanded(child: w)).toList(),
    );
  }

  Widget _buildDisputeTable() {
    final disputes = _filteredDisputes;
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Text('Disputes', style: TextStyle(color: _fg, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                Row(
                  children: List.generate(_filters.length, (i) {
                    final active = i == _selectedFilter;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedFilter = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: active ? _accent : Colors.transparent,
                            border: Border.all(color: active ? _accent : _border),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _filters[i],
                            style: TextStyle(
                              color: active ? Colors.white : _fgMid,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          // Table header
          Container(
            color: _surface2,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: const [
                Expanded(flex: 2, child: _TableHeader('Transaction ID')),
                Expanded(flex: 3, child: _TableHeader('Student & Tutor')),
                Expanded(flex: 2, child: _TableHeader('Issue Type')),
                Expanded(flex: 2, child: _TableHeader('Amount')),
                Expanded(flex: 2, child: _TableHeader('Status')),
                Expanded(flex: 2, child: _TableHeader('Actions')),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          // Rows
          ...List.generate(disputes.length, (i) {
            final d = disputes[i];
            final selected = _disputes.indexOf(d) == _selectedDisputeIndex;
            return _DisputeRow(
              dispute: d,
              selected: selected,
              onTap: () => setState(() => _selectedDisputeIndex = _disputes.indexOf(d)),
              isLast: i == disputes.length - 1,
            );
          }),
          // Footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text('Showing 1–${disputes.length} of 142 disputes',
                style: const TextStyle(color: _fgMid, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    final dispute = _disputes[_selectedDisputeIndex];
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(left: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dispute.txnId,
                          style: const TextStyle(color: Color(0xFF5B9EFF), fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      const Text('Dispute Review',
                          style: TextStyle(color: _fg, fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                _StatusBadge(dispute.status),
              ],
            ),
            const SizedBox(height: 18),
            const _SectionLabel('PARTIES INVOLVED'),
            const SizedBox(height: 8),
            _PartyRow(initials: _initials(dispute.studentName), name: dispute.studentName, role: 'Student'),
            const SizedBox(height: 8),
            _PartyRow(initials: _initials(dispute.tutorName), name: dispute.tutorName, role: 'Tutor'),
            const SizedBox(height: 16),
            Divider(color: _border),
            const SizedBox(height: 12),
            const _SectionLabel('ISSUE REPORT'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '"The tutor\'s video cut out 10 minutes into our 60-minute session. We tried reconnecting multiple times but couldn\'t establish a stable connection. I\'m requesting a full refund as we couldn\'t complete the lesson."',
                style: TextStyle(color: _fgMid, fontSize: 12.5, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),
            const _SectionLabel('SYSTEM TELEMETRY'),
            const SizedBox(height: 8),
            _TelemetryRow(label: 'Session Duration', value: '47:22'),
            _TelemetryRow(label: 'Connection Quality', value: 'Poor'),
            _TelemetryRow(label: 'Drop Events', value: '4'),
            _TelemetryRow(label: 'Recorded', value: 'Yes'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surface2,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Refund Amount', style: TextStyle(color: _fgMid, fontSize: 11.5)),
                  const SizedBox(height: 4),
                  Text(dispute.amount,
                      style: const TextStyle(color: _fg, fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                child: const Text('✓  Approve Refund', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: BorderSide(color: _red.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                child: const Text('✗  Deny Refund', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF5B9EFF),
                  side: BorderSide(color: _accent.withOpacity(0.4)),
                  backgroundColor: const Color(0xFF1A2540),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                child: const Text('⚡  Force Override Decision', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ─────────────────────────────────────────────
//  Dispute Row
// ─────────────────────────────────────────────

class _DisputeRow extends StatelessWidget {
  final Dispute dispute;
  final bool selected;
  final VoidCallback onTap;
  final bool isLast;

  const _DisputeRow({
    required this.dispute,
    required this.selected,
    required this.onTap,
    required this.isLast,
  });

  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _border = Color(0xFF30363D);
  static const Color _accent = Color(0xFF1457D9);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(0.06) : Colors.transparent,
          border: isLast ? null : Border(bottom: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(dispute.txnId,
                  style: const TextStyle(
                      color: _fgMid, fontSize: 12, fontFamily: 'monospace')),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dispute.studentName,
                      style: const TextStyle(color: _fg, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('↔ ${dispute.tutorName}',
                      style: const TextStyle(color: _fgMid, fontSize: 11.5)),
                ],
              ),
            ),
            Expanded(flex: 2, child: _IssueTypeBadge(dispute.issueType)),
            Expanded(
              flex: 2,
              child: Text(dispute.amount,
                  style: const TextStyle(color: _fg, fontSize: 13)),
            ),
            Expanded(flex: 2, child: _StatusBadge(dispute.status)),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _SmallButton(
                    label: dispute.status == DisputeStatus.approved ||
                            dispute.status == DisputeStatus.denied
                        ? 'View'
                        : 'Review',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Small reusable widgets
// ─────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            color: Color(0xFF8B949E), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.04));
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String delta;
  final Color deltaColor;

  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor,
    required this.delta,
    required this.deltaColor,
  });

  static const Color _surface = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _fgMid, fontSize: 11.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? _fg, fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 4),
          Text(delta, style: TextStyle(color: deltaColor, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _IssueTypeBadge extends StatelessWidget {
  final IssueType type;
  const _IssueTypeBadge(this.type);

  @override
  Widget build(BuildContext context) {
    late String label;
    late Color bg;
    late Color fg;
    switch (type) {
      case IssueType.technicalIssue:
        label = 'Tech Issue';
        bg = const Color(0xFF1A1040);
        fg = const Color(0xFFBC8CFF);
        break;
      case IssueType.tutorNoShow:
        label = 'No Show';
        bg = const Color(0xFF2D1F00);
        fg = const Color(0xFFD29922);
        break;
      case IssueType.disputedQuality:
        label = 'Quality';
        bg = const Color(0xFF1A2540);
        fg = const Color(0xFF5B9EFF);
        break;
      case IssueType.lateCancellation:
        label = 'Late Cancel';
        bg = const Color(0xFF1A2540);
        fg = const Color(0xFF5B9EFF);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final DisputeStatus status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    late String label;
    late Color bg;
    late Color fg;
    switch (status) {
      case DisputeStatus.open:
        label = 'Open';
        bg = const Color(0xFF2D0A09);
        fg = const Color(0xFFF85149);
        break;
      case DisputeStatus.pending:
        label = 'Pending';
        bg = const Color(0xFF2D1F00);
        fg = const Color(0xFFD29922);
        break;
      case DisputeStatus.pendingOverride:
        label = 'Pending Override';
        bg = const Color(0xFF2D1F00);
        fg = const Color(0xFFD29922);
        break;
      case DisputeStatus.pendingReview:
        label = 'Pending Review';
        bg = const Color(0xFF2D1F00);
        fg = const Color(0xFFD29922);
        break;
      case DisputeStatus.denied:
        label = 'Denied';
        bg = const Color(0xFF2D0A09);
        fg = const Color(0xFFF85149);
        break;
      case DisputeStatus.approved:
        label = 'Approved';
        bg = const Color(0xFF0D2818);
        fg = const Color(0xFF3FB950);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2333),
          border: Border.all(color: const Color(0xFF30363D)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _PartyRow extends StatelessWidget {
  final String initials;
  final String name;
  final String role;
  const _PartyRow({required this.initials, required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2333),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: const Color(0xFFD0E4FF),
            child: Text(initials,
                style: const TextStyle(
                    color: Color(0xFF1457D9), fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: Color(0xFFE6EDF3), fontSize: 13, fontWeight: FontWeight.w600)),
              Text(role,
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  final String label;
  final String value;
  const _TelemetryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12.5)),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFFE6EDF3),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: Color(0xFF484F58),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08));
  }
}

// ─────────────────────────────────────────────
//  Shared Sidebar + TopBar
// ─────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final String currentRoute;
  const _Sidebar({required this.currentRoute});

  static const Color _surface = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _fgMuted = Color(0xFF484F58);
  static const Color _accent = Color(0xFF1457D9);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(child: Text('🎓', style: TextStyle(fontSize: 16))),
                ),
                const SizedBox(width: 10),
                const Text('TheoTutor',
                    style: TextStyle(color: _fg, fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          _NavSection(label: 'OVERVIEW', items: [
            _NavItem(icon: '📊', label: 'Dashboard', route: 'dashboard', current: currentRoute),
            _NavItem(icon: '👥', label: 'Users', route: 'users', current: currentRoute),
            _NavItem(icon: '📚', label: 'Sessions', route: 'sessions', current: currentRoute),
          ]),
          _NavSection(label: 'FINANCE', items: [
            _NavItem(icon: '⚖️', label: 'Refunds & Issues', route: 'refunds', current: currentRoute),
            _NavItem(icon: '💳', label: 'Payments', route: 'payments', current: currentRoute),
          ]),
          _NavSection(label: 'SYSTEM', items: [
            _NavItem(icon: '🖥️', label: 'Monitor Platform', route: 'monitor', current: currentRoute),
            _NavItem(icon: '🔔', label: 'Notifications', route: 'notifications', current: currentRoute),
            _NavItem(icon: '⚙️', label: 'Settings', route: 'settings', current: currentRoute),
          ]),
        ],
      ),
    );
  }
}

class _NavSection extends StatelessWidget {
  final String label;
  final List<Widget> items;
  const _NavSection({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF484F58),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1)),
          ),
          ...items,
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String icon;
  final String label;
  final String route;
  final String current;
  const _NavItem(
      {required this.icon, required this.label, required this.route, required this.current});

  @override
  Widget build(BuildContext context) {
    final active = route == current;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1457D9).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: active ? const Color(0xFF5B9EFF) : const Color(0xFF8B949E),
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  static const Color _surface = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _accent = Color(0xFF1457D9);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: _fg, fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFD0E4FF),
            child: const Text('IA',
                style: TextStyle(
                    color: Color(0xFF1457D9), fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
