import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/dashborad_models.dart';
import 'Services/admin_dashboard_services.dart';
import 'Services/dashboard_report_pdf.dart';
import 'admin_shell.dart';

const _axisStyle = TextStyle(fontSize: 11, color: AdminColors.textMuted);

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _service = AdminDashboardService();

  DashboardSummary? _summary;
  List<ChartPoint> _points = [];
  String _range = '30d';
  bool _loading = true;
  bool _chartLoading = false;
  bool _exporting = false;
  String? _error;
  String? _chartError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _rangeLabel {
    switch (_range) {
      case '30d':
        return 'Last 30 days';
      case '90d':
        return 'Last 90 days';
      default:
        return 'Year to date';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _service.fetchSummary(),
        _service.fetchChart(_range),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as DashboardSummary;
        _points = results[1] as List<ChartPoint>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadChart() async {
    final range = _range;
    setState(() {
      _chartLoading = true;
      _chartError = null;
    });
    try {
      final points = await _service.fetchChart(range);
      if (!mounted || _range != range) return;
      setState(() {
        _points = points;
        _chartLoading = false;
      });
    } catch (e) {
      if (!mounted || _range != range) return;
      setState(() {
        _chartError = e.toString();
        _chartLoading = false;
      });
    }
  }

  void _changeRange(String range) {
    if (range == _range) return;
    _range = range;
    _loadChart();
  }

  Future<void> _export() async {
    final summary = _summary;
    if (summary == null) return;
    setState(() => _exporting = true);
    try {
      await DashboardReportPdf.export(
        summary: summary,
        points: _points,
        rangeLabel: _rangeLabel,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export report: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.dashboard,
      adminName: _summary?.adminName,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final summary = _summary;
    if (_error != null || summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load the dashboard.'),
              const SizedBox(height: 8),
              Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AdminColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final count = NumberFormat.decimalPattern();

    final cards = [
      _StatCard(
        label: 'TOTAL REVENUE',
        value: compactRand(summary.totalRevenue),
        change: summary.totalRevenueChange,
        icon: Icons.trending_up,
        iconColor: const Color(0xFF1B7F3A),
        iconBg: const Color(0xFFD9F5E0),
        waveColor: const Color(0x338AA8E0),
      ),
      _StatCard(
        label: 'ACTIVE STUDENTS',
        value: count.format(summary.activeStudents),
        change: summary.activeStudentsChange,
        icon: Icons.groups_outlined,
        iconColor: AdminColors.primary,
        iconBg: const Color(0xFFDCE8FF),
        waveColor: const Color(0x338AA8E0),
      ),
      _StatCard(
        label: 'ACTIVE TUTORS',
        value: count.format(summary.activeTutors),
        change: summary.activeTutorsChange,
        icon: Icons.person_outline,
        iconColor: const Color(0xFF0E7490),
        iconBg: const Color(0xFFCFF3FA),
        waveColor: const Color(0x3380A8A0),
      ),
      _StatCard(
        label: 'MONTHLY GROWTH',
        value: '${summary.monthlyGrowth.toStringAsFixed(1)}%',
        change: summary.monthlyGrowthChange,
        icon: Icons.bar_chart,
        iconColor: const Color(0xFFB45309),
        iconBg: const Color(0xFFFDEBD0),
        waveColor: const Color(0x33D9B98A),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'ADMIN  /  ',
                                style: TextStyle(color: AdminColors.textMuted),
                              ),
                              TextSpan(
                                text: 'DASHBOARD',
                                style: TextStyle(color: AdminColors.primary),
                              ),
                            ],
                          ),
                          style: TextStyle(fontSize: 10, letterSpacing: 1),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'System Overview',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _exporting ? null : _export,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download, size: 16),
                    label: const Text('Export Report'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 900
                      ? 4
                      : constraints.maxWidth >= 500
                      ? 2
                      : 1;
                  const gap = 16.0;
                  final width =
                      (constraints.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final card in cards)
                        SizedBox(width: width, child: card),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final chart = _ChartCard(
                    points: _points,
                    range: _range,
                    loading: _chartLoading,
                    error: _chartError,
                    onRangeChanged: _changeRange,
                    onRetry: _loadChart,
                  );
                  final quick = _QuickActionsPanel(
                    pendingApplications: summary.pendingApplications,
                    pendingRefunds: summary.pendingRefunds,
                  );
                  if (constraints.maxWidth >= 900) {
                    return SizedBox(
                      height: 380,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 2, child: chart),
                          const SizedBox(width: 24),
                          Expanded(child: quick),
                        ],
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 380, child: chart),
                      const SizedBox(height: 24),
                      quick,
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _RecentActivityCard(
                items: summary.recentActivity,
                onViewAll: () =>
                    Navigator.pushNamed(context, AdminRoutes.activity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- shared box

class _CardBox extends StatelessWidget {
  const _CardBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------- stat cards

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.change,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.waveColor,
  });

  final String label;
  final String value;
  final double? change;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color waveColor;

  @override
  Widget build(BuildContext context) {
    final c = change;
    final changeColor = c == null
        ? AdminColors.textMuted
        : c > 0
        ? const Color(0xFF1B7F3A)
        : c < 0
        ? const Color(0xFFC62828)
        : AdminColors.textMuted;

    return Container(
      height: 140,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 44,
            child: CustomPaint(painter: _WavePainter(waveColor)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.textMuted,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: iconColor),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.textDark,
                        ),
                      ),
                    ),
                    if (c != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          formatChange(c),
                          style: TextStyle(fontSize: 12, color: changeColor),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.5)
      ..cubicTo(w * 0.3, h * 0.1, w * 0.6, h * 0.9, w, h * 0.3)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.color != color;
}

// ---------------------------------------------------------------- chart

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.points,
    required this.range,
    required this.loading,
    required this.error,
    required this.onRangeChanged,
    required this.onRetry,
  });

  final List<ChartPoint> points;
  final String range;
  final bool loading;
  final String? error;
  final ValueChanged<String> onRangeChanged;
  final VoidCallback onRetry;

  String get _subtitle {
    switch (range) {
      case '30d':
        return 'Comparing total booked sessions to realized revenue over 30 days.';
      case '90d':
        return 'Comparing total booked sessions to realized revenue over 90 days.';
      default:
        return 'Comparing total booked sessions to realized revenue year to date.';
    }
  }

  Widget _body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load chart data.'),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (points.length < 2) {
      return const Center(
        child: Text('Not enough data to display the chart yet.'),
      );
    }
    return _SessionRevenueChart(points: points);
  }

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Session Volume vs Revenue',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _RangeButton(
                label: '30D',
                value: '30d',
                current: range,
                onTap: onRangeChanged,
              ),
              _RangeButton(
                label: '90D',
                value: '90d',
                current: range,
                onTap: onRangeChanged,
              ),
              _RangeButton(
                label: 'YTD',
                value: 'ytd',
                current: range,
                onTap: onRangeChanged,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF0F4) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AdminColors.textDark : AdminColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SessionRevenueChart extends StatelessWidget {
  const _SessionRevenueChart({required this.points});
  final List<ChartPoint> points;

  double _niceInterval(double maxValue) {
    if (maxValue <= 0) return 1;
    final raw = maxValue / 4;
    final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
    final n = raw / magnitude;
    final step = n <= 1
        ? 1
        : n <= 2
        ? 2
        : n <= 2.5
        ? 2.5
        : n <= 5
        ? 5
        : 10;
    return (step * magnitude).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final maxRevenue = points.map((p) => p.revenue).reduce(max);
    final maxSessions = points.map((p) => p.sessions).reduce(max);
    final interval = _niceInterval(maxRevenue);
    final maxY = interval * 4;
    final scaleTo = maxRevenue > 0 ? maxRevenue : maxY;
    final step = max(1, ((points.length - 1) / 4).round());

    final revenueSpots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].revenue),
    ];
    final sessionSpots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(
          i.toDouble(),
          maxSessions == 0 ? 0 : points[i].sessions / maxSessions * scaleTo,
        ),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AdminColors.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: interval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  compactRand(value),
                  style: _axisStyle,
                  textAlign: TextAlign.left,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: step.toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    DateFormat('MMM dd').format(points[i].date),
                    style: _axisStyle,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched.map((s) {
              final p = points[s.spotIndex];
              final text = s.barIndex == 0
                  ? '${DateFormat('d MMM').format(p.date)}\nRevenue: R${NumberFormat('#,##0.00').format(p.revenue)}'
                  : 'Sessions: ${p.sessions}';
              return LineTooltipItem(
                text,
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: revenueSpots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: AdminColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0x140A3FA6),
            ),
          ),
          LineChartBarData(
            spots: sessionSpots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: const Color(0xFF9DB4F5),
            barWidth: 2,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- quick actions

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({
    required this.pendingApplications,
    required this.pendingRefunds,
  });

  final int pendingApplications;
  final int pendingRefunds;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          _QuickActionTile(
            icon: Icons.how_to_reg_outlined,
            title: 'Approve New Tutors',
            subtitle:
                '$pendingApplications pending ${pendingApplications == 1 ? 'application' : 'applications'}',
            highlighted: true,
            onTap: () => Navigator.pushNamed(context, AdminRoutes.applications),
          ),
          const SizedBox(height: 12),
          _QuickActionTile(
            icon: Icons.payments_outlined,
            title: 'Issue Refunds',
            subtitle:
                '$pendingRefunds ${pendingRefunds == 1 ? 'request' : 'requests'} waiting',
            onTap: () => Navigator.pushNamed(context, AdminRoutes.refunds),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? AdminColors.primary : Colors.white;
    return Material(
      color: highlighted ? Colors.white : const Color(0x1FFFFFFF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: highlighted
                      ? AdminColors.selected
                      : const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: highlighted
                            ? AdminColors.textMuted
                            : const Color(0xB3FFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- recent activity

class _TypeStyle {
  const _TypeStyle(this.label, this.bg, this.fg, this.icon);
  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;

  static _TypeStyle of(String type) {
    switch (type) {
      case 'new_tutor':
        return const _TypeStyle(
          'NEW TUTOR',
          Color(0xFFD9F5E0),
          Color(0xFF1B7F3A),
          Icons.person_add_alt_1,
        );
      case 'booking':
        return const _TypeStyle(
          'BOOKING',
          Color(0xFFE8EAEE),
          Color(0xFF4B5563),
          Icons.event_note,
        );
      case 'alert':
        return const _TypeStyle(
          'ALERT',
          Color(0xFFFDE2E2),
          Color(0xFFC62828),
          Icons.warning_amber_rounded,
        );
      default:
        return _TypeStyle(
          type.replaceAll('_', ' ').toUpperCase(),
          const Color(0xFFE8EAEE),
          const Color(0xFF4B5563),
          Icons.info_outline,
        );
    }
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.items, required this.onViewAll});
  final List<ActivityItem> items;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.textDark,
                  ),
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'VIEW ALL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AdminColors.primary,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: AdminColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No recent activity yet.',
                style: TextStyle(color: AdminColors.textMuted),
              ),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              _ActivityRow(item: items[i]),
            ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final style = _TypeStyle.of(item.type);
    return Row(
      children: [
        _ActivityLeading(item: item),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatActivityTime(item.createdAt),
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: style.bg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                style.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: style.fg,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActivityLeading extends StatelessWidget {
  const _ActivityLeading({required this.item});
  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final style = _TypeStyle.of(item.type);
    final isBooking = item.type == 'booking';
    final tileBg = isBooking ? const Color(0xFFD6E6FF) : style.bg;
    final tileFg = isBooking ? AdminColors.primary : style.fg;
    final hasPhoto = item.photoUrl != null && item.photoUrl!.isNotEmpty;

    final iconTile = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(style.icon, color: tileFg),
    );

    final tile = hasPhoto
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              item.photoUrl!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => iconTile,
            ),
          )
        : iconTile;

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 0, child: tile),
          if (hasPhoto)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: style.fg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(style.icon, size: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
