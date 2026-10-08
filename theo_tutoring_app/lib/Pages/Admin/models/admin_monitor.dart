import 'dart:math';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────

enum AlertSeverity { critical, warning, info }

class SystemAlert {
  final AlertSeverity severity;
  final String service;
  final String message;
  final String time;

  const SystemAlert({
    required this.severity,
    required this.service,
    required this.message,
    required this.time,
  });
}

class AuditEntry {
  final String initials;
  final Color avatarColor;
  final String actor;
  final String event;
  final String detail;
  final String time;
  final Color dotColor;
  final bool isSuccess;

  const AuditEntry({
    required this.initials,
    required this.avatarColor,
    required this.actor,
    required this.event,
    required this.detail,
    required this.time,
    required this.dotColor,
    this.isSuccess = false,
  });
}

// ─────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────

class AdminMonitorPlatformScreen extends StatelessWidget {
  const AdminMonitorPlatformScreen({super.key});

  static const Color _bg = Color(0xFF0D1117);
  static const Color _surface = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _green = Color(0xFF3FB950);
  static const Color _yellow = Color(0xFFD29922);
  static const Color _red = Color(0xFFF85149);
  static const Color _accent = Color(0xFF1457D9);

  static const _alerts = [
    SystemAlert(
      severity: AlertSeverity.critical,
      service: 'db-cluster-01',
      message: 'CPU utilization exceeded 95% threshold for 5m',
      time: '2m ago',
    ),
    SystemAlert(
      severity: AlertSeverity.warning,
      service: 'payment-gw-ext',
      message: 'Latency spike detected in 3rd party API (Avg 800ms)',
      time: '14m ago',
    ),
    SystemAlert(
      severity: AlertSeverity.info,
      service: 'worker-node-8',
      message: 'Auto-scaling event triggered. Added 2 instances.',
      time: '1h ago',
    ),
  ];

  static const _auditEntries = [
    AuditEntry(
      initials: 'SJ',
      avatarColor: Color(0xFF1A3A5C),
      actor: 'Sarah Jenkins',
      event: 'Updated system configuration flag',
      detail: 'ENABLE_NEW_PAYMENT_GW to TRUE',
      time: '10:42 AM',
      dotColor: Color(0xFF5B9EFF),
    ),
    AuditEntry(
      initials: '⚙',
      avatarColor: Color(0xFF1C2333),
      actor: 'System Auto-Scheduler',
      event: 'Initiated weekly database backup and index optimization.',
      detail: '',
      time: '08:00 AM',
      dotColor: Color(0xFF3FB950),
      isSuccess: true,
    ),
    AuditEntry(
      initials: 'MC',
      avatarColor: Color(0xFF2A1A1A),
      actor: 'Michael Chang',
      event: 'east-cache-pool',
      detail: '"Resolving stale session data issue ticket #4492"',
      time: 'Yesterday, 11:23 PM',
      dotColor: Color(0xFFD29922),
    ),
    AuditEntry(
      initials: 'AC',
      avatarColor: Color(0xFF1A2540),
      actor: 'Admin Central',
      event: 'Revoked API access keys for 3 inactive developer accounts.',
      detail: '',
      time: 'Yesterday, 04:15 PM',
      dotColor: Color(0xFFF85149),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          _Sidebar(currentRoute: 'monitor'),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatsRow(),
                        const SizedBox(height: 20),
                        _buildTrafficChart(),
                        const SizedBox(height: 20),
                        _buildBottomRow(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          const Text('Monitor Platform',
              style: TextStyle(color: _fg, fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          // Status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _green,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _green.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)],
            ),
          ),
          const SizedBox(width: 6),
          const Text('All Systems Operational',
              style: TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          const CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFFD0E4FF),
            child: Text('IA',
                style: TextStyle(
                    color: Color(0xFF1457D9), fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _MonitorStatCard(
          label: 'Server Uptime',
          value: '99.98%',
          valueColor: _green,
          delta: '↑ +0.01% vs last 30d',
          deltaColor: _green,
          icon: '🟢',
        ),
        const SizedBox(width: 14),
        _MonitorStatCard(
          label: 'Active API Req/s',
          value: '1,245',
          delta: '↑ +0.04% spike detected',
          deltaColor: _yellow,
          icon: '⚡',
          showChart: true,
        ),
        const SizedBox(width: 14),
        _MonitorStatCard(
          label: 'Global Error Rate',
          value: '0.12%',
          valueColor: _green,
          delta: '↓ Below threshold',
          deltaColor: _green,
          icon: '🛡️',
        ),
        const SizedBox(width: 14),
        _MonitorStatCard(
          label: 'Avg Latency (ms)',
          value: '42',
          delta: '↓ p95: 89ms',
          deltaColor: _green,
          icon: '🕐',
          showSparkline: true,
        ),
      ].map((w) => Expanded(child: w)).toList(),
    );
  }

  Widget _buildTrafficChart() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Real-time Traffic Overload',
                        style: TextStyle(
                            color: _fg, fontSize: 15, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('Requests per minute vs Baseline capacity',
                        style: TextStyle(color: _fgMid, fontSize: 12)),
                  ],
                ),
                const Spacer(),
                _ChipButton(label: 'Live', active: true),
                const SizedBox(width: 6),
                _ChipButton(label: '24h', active: false),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: CustomPaint(
                painter: _TrafficChartPainter(),
                child: Container(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildAlertsTable()),
        const SizedBox(width: 16),
        SizedBox(width: 340, child: _buildAuditLog()),
      ],
    );
  }

  Widget _buildAlertsTable() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Text('Active System Alerts',
                    style: TextStyle(color: _fg, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                // Live pulsing badge
                _LiveBadge(),
                const SizedBox(width: 12),
                const Text('View All',
                    style: TextStyle(color: Color(0xFF5B9EFF), fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          // Header
          Container(
            color: const Color(0xFF1C2333),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: const [
                Expanded(flex: 2, child: _TH('Severity')),
                Expanded(flex: 2, child: _TH('Service')),
                Expanded(flex: 4, child: _TH('Message')),
                Expanded(flex: 2, child: _TH('Time')),
                Expanded(flex: 2, child: _TH('Action')),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          ..._alerts.asMap().entries.map((e) {
            final a = e.value;
            final isLast = e.key == _alerts.length - 1;
            return _AlertRow(alert: a, isLast: isLast);
          }),
        ],
      ),
    );
  }

  Widget _buildAuditLog() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Text('🔄', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                const Text('Audit Log',
                    style: TextStyle(color: _fg, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                const Icon(Icons.filter_list, color: _fgMid, size: 18),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          ..._auditEntries.asMap().entries.map((e) {
            final entry = e.value;
            final isLast = e.key == _auditEntries.length - 1;
            return _AuditRow(entry: entry, isLast: isLast);
          }),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text('Load Older Logs',
                  style: const TextStyle(
                      color: Color(0xFF5B9EFF), fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Chart painter
// ─────────────────────────────────────────────

class _TrafficChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF30363D)
      ..strokeWidth = 1;

    // Grid lines
    for (int i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Traffic points (normalized 0–1, representing req/s dipping then spiking)
    final points = [
      0.55, 0.50, 0.52, 0.45, 0.48, 0.38, 0.42, 0.35, 0.40, 0.30, 0.25, 0.28,
      0.22, 0.20, 0.35, 0.50, 0.65, 0.75, 0.80, 0.85, 0.90, 0.95, 0.98, 1.0,
    ];

    final n = points.length;
    final step = size.width / (n - 1);

    // Build path
    final path = Path();
    final areaPath = Path();

    for (int i = 0; i < n; i++) {
      final x = i * step;
      final y = size.height * (1 - points[i]);
      if (i == 0) {
        path.moveTo(x, y);
        areaPath.moveTo(x, size.height);
        areaPath.lineTo(x, y);
      } else {
        // Smooth curve
        final prevX = (i - 1) * step;
        final prevY = size.height * (1 - points[i - 1]);
        final cpX = (prevX + x) / 2;
        path.cubicTo(cpX, prevY, cpX, y, x, y);
        areaPath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }

    // Close area path
    areaPath.lineTo(size.width, size.height);
    areaPath.close();

    // Draw area with gradient
    final areaGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF1457D9).withOpacity(0.25),
        const Color(0xFF1457D9).withOpacity(0.0),
      ],
    );
    final areaPaint = Paint()
      ..shader = areaGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(areaPath, areaPaint);

    // Draw line
    final linePaint = Paint()
      ..color = const Color(0xFF5B9EFF)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────
//  Alert row
// ─────────────────────────────────────────────

class _AlertRow extends StatelessWidget {
  final SystemAlert alert;
  final bool isLast;
  const _AlertRow({required this.alert, required this.isLast});

  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _border = Color(0xFF30363D);

  Color get _severityColor {
    switch (alert.severity) {
      case AlertSeverity.critical:
        return const Color(0xFFF85149);
      case AlertSeverity.warning:
        return const Color(0xFFD29922);
      case AlertSeverity.info:
        return const Color(0xFF5B9EFF);
    }
  }

  String get _severityLabel {
    switch (alert.severity) {
      case AlertSeverity.critical:
        return 'Critical';
      case AlertSeverity.warning:
        return 'Warning';
      case AlertSeverity.info:
        return 'Info';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _severityColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(_severityLabel,
                    style: TextStyle(
                        color: _severityColor, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(alert.service,
                style: const TextStyle(color: _fgMid, fontSize: 12, fontFamily: 'monospace')),
          ),
          Expanded(
            flex: 4,
            child: Text(alert.message,
                style: const TextStyle(color: _fg, fontSize: 12.5)),
          ),
          Expanded(
            flex: 2,
            child: Text(alert.time,
                style: const TextStyle(color: _fgMid, fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: _SmallBtn(label: 'Resolve'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Audit row
// ─────────────────────────────────────────────

class _AuditRow extends StatelessWidget {
  final AuditEntry entry;
  final bool isLast;
  const _AuditRow({required this.entry, required this.isLast});

  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _border = Color(0xFF30363D);
  static const Color _green = Color(0xFF3FB950);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: entry.avatarColor,
            child: Text(
              entry.initials,
              style: const TextStyle(
                  color: Color(0xFFE6EDF3), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(entry.actor,
                        style: const TextStyle(
                            color: _fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(entry.time,
                        style: const TextStyle(color: _fgMid, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(entry.event,
                    style: const TextStyle(color: _fgMid, fontSize: 12, height: 1.4)),
                if (entry.detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(entry.detail,
                      style: const TextStyle(
                          color: Color(0xFF5B9EFF), fontSize: 11.5, fontStyle: FontStyle.italic)),
                ],
                if (entry.isSuccess) ...[
                  const SizedBox(height: 4),
                  const Text('✓ Completed successfully',
                      style: TextStyle(color: _green, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Small widgets
// ─────────────────────────────────────────────

class _MonitorStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String delta;
  final Color deltaColor;
  final String icon;
  final bool showChart;
  final bool showSparkline;

  const _MonitorStatCard({
    required this.label,
    required this.value,
    this.valueColor,
    required this.delta,
    required this.deltaColor,
    required this.icon,
    this.showChart = false,
    this.showSparkline = false,
  });

  static const Color _surface = Color(0xFF161B22);
  static const Color _surface2 = Color(0xFF1C2333);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
  static const Color _fgMid = Color(0xFF8B949E);
  static const Color _accent = Color(0xFF5B9EFF);

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
          Row(
            children: [
              Text(label, style: const TextStyle(color: _fgMid, fontSize: 11.5, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(icon, style: const TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? _fg, fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
          if (showChart) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(8, (i) {
                  final heights = [0.3, 0.5, 0.4, 0.7, 0.6, 0.8, 0.9, 1.0];
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        heightFactor: heights[i],
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _accent.withOpacity(0.6 + heights[i] * 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
          if (showSparkline) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: CustomPaint(painter: _SparklinePainter()),
            ),
          ],
          const SizedBox(height: 6),
          Text(delta, style: TextStyle(color: deltaColor, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pts = [0.6, 0.4, 0.7, 0.5, 0.3, 0.6, 0.4, 0.5, 0.3, 0.2];
    final n = pts.length;
    final paint = Paint()
      ..color = const Color(0xFF5B9EFF)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final y = size.height * pts[i];
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: Color(0xFFF85149), shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        const Text('LIVE',
            style: TextStyle(color: Color(0xFFF85149), fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ChipButton extends StatelessWidget {
  final String label;
  final bool active;
  const _ChipButton({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1457D9) : Colors.transparent,
        border: Border.all(color: active ? const Color(0xFF1457D9) : const Color(0xFF30363D)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: active ? Colors.white : const Color(0xFF8B949E),
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  const _SmallBtn({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2333),
        border: Border.all(color: const Color(0xFF30363D)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Color(0xFF8B949E), fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            color: Color(0xFF8B949E),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.04));
  }
}

// ─────────────────────────────────────────────
//  Shared Sidebar (same as refunds page)
// ─────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final String currentRoute;
  const _Sidebar({required this.currentRoute});

  static const Color _surface = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _fg = Color(0xFFE6EDF3);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(8)),
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
