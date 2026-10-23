// Monitor Platform (project documentation 9.5): server uptime, API requests per
// second, error rate and average latency, a traffic chart comparing requests per
// minute with baseline capacity, and an audit log of system events.

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/monitor_models.dart';
import 'Services/monitor_services.dart';
import 'admin_shell.dart';

const _surface2 = Color(0xFFF8F9FB);
const _green = Color(0xFF1B7F3A);
const _blueBg = Color(0xFFDCE8FF);
const _axisStyle = TextStyle(fontSize: 11, color: AdminColors.textMuted);

/// How often the "Live" view refreshes itself.
const _livePollInterval = Duration(seconds: 15);

final _number = NumberFormat('#,##0.##');

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

class AdminMonitorPlatformScreen extends StatefulWidget {
  const AdminMonitorPlatformScreen({super.key, this.service});

  final AdminMonitorService? service;

  @override
  State<AdminMonitorPlatformScreen> createState() =>
      _AdminMonitorPlatformScreenState();
}

class _AdminMonitorPlatformScreenState
    extends State<AdminMonitorPlatformScreen> {
  late final AdminMonitorService _service;
  late final bool _ownsService;
  Timer? _poll;

  String _range = 'live';
  MonitorSnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  DateTime? _updatedAt;
  bool _refreshFailed = false;

  final List<AuditEntry> _audit = [];
  String? _auditCursor;
  bool _auditLoading = true;
  bool _auditLoadingMore = false;
  String? _auditError;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminMonitorService();
    _ownsService = widget.service == null;
    _load();
    _loadAudit();
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ loading

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _service.fetchSnapshot(_range);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _updatedAt = DateTime.now();
        _refreshFailed = false;
        _loading = false;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_range != 'live') return;
    _poll = Timer.periodic(_livePollInterval, (_) => _refresh());
  }

  // Background refresh for the live view: keeps the last good data on failure.
  Future<void> _refresh() async {
    try {
      final snapshot = await _service.fetchSnapshot(_range);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _updatedAt = DateTime.now();
        _refreshFailed = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _refreshFailed = true);
    }
  }

  void _setRange(String range) {
    if (range == _range) return;
    setState(() => _range = range);
    _load();
  }

  Future<void> _loadAudit() async {
    setState(() {
      _auditLoading = true;
      _auditError = null;
    });
    try {
      final page = await _service.fetchAuditLog();
      if (!mounted) return;
      setState(() {
        _audit
          ..clear()
          ..addAll(page.entries);
        _auditCursor = page.nextCursor;
        _auditLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _auditError = _msg(e);
        _auditLoading = false;
      });
    }
  }

  Future<void> _loadOlderAudit() async {
    if (_auditCursor == null || _auditLoadingMore) return;
    setState(() => _auditLoadingMore = true);
    try {
      final page = await _service.fetchAuditLog(before: _auditCursor);
      if (!mounted) return;
      setState(() {
        _audit.addAll(page.entries);
        _auditCursor = page.nextCursor;
        _auditLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _auditLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load older logs: ${_msg(e)}')),
      );
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.monitor,
      adminName: _snapshot?.adminName,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                if (_loading && _snapshot == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null && _snapshot == null)
                  _ErrorCard(
                    title: 'Could not load platform metrics.',
                    message: _error!,
                    onRetry: _load,
                  )
                else ...[
                  if (_error != null)
                    _ErrorCard(
                      title: 'Could not refresh platform metrics.',
                      message: _error!,
                      onRetry: _load,
                    ),
                  if (_error != null) const SizedBox(height: 20),
                  _buildStatsRow(_snapshot!.metrics),
                  const SizedBox(height: 20),
                  _buildOperationalStats(_snapshot!.operationalMetrics),
                  const SizedBox(height: 20),
                  _buildTrafficCard(_snapshot!.traffic),
                ],
                const SizedBox(height: 20),
                _buildAuditLog(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monitor Platform',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AdminColors.textDark,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Live platform counts and recorded administrator activity.',
          style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildStatsRow(PlatformMetrics m) {
    final cards = [
      _MetricCard(
        label: 'Server Uptime',
        value: m.uptimePercent == null
            ? '—'
            : '${_number.format(m.uptimePercent)}%',
        caption: m.uptimeSince == null
            ? null
            : 'Up since ${DateFormat('d MMM, HH:mm').format(m.uptimeSince!)}',
        icon: Icons.cloud_done_outlined,
      ),
      _MetricCard(
        label: 'API Requests / sec',
        value: m.requestsPerSecond == null
            ? '—'
            : _number.format(m.requestsPerSecond),
        icon: Icons.bolt_outlined,
      ),
      _MetricCard(
        label: 'Error Rate',
        value: m.errorRatePercent == null
            ? '—'
            : '${_number.format(m.errorRatePercent)}%',
        caption: 'Share of requests that failed',
        icon: Icons.shield_outlined,
      ),
      _MetricCard(
        label: 'Avg Latency',
        value: m.avgLatencyMs == null
            ? '—'
            : '${_number.format(m.avgLatencyMs)} ms',
        caption: m.p95LatencyMs == null
            ? null
            : 'p95: ${_number.format(m.p95LatencyMs)} ms',
        icon: Icons.schedule_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // 4 across on wide screens, 2 across on medium, 1 on phones.
        final perRow = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 500
            ? 2
            : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _buildOperationalStats(OperationalMetrics metrics) {
    final cards = [
      _MetricCard(
        label: 'Active Users',
        value: metrics.activeUsers == null
            ? '—'
            : _number.format(metrics.activeUsers),
        icon: Icons.people_outline,
      ),
      _MetricCard(
        label: 'Active Tutors',
        value: metrics.activeTutors == null
            ? '—'
            : _number.format(metrics.activeTutors),
        icon: Icons.school_outlined,
      ),
      _MetricCard(
        label: 'Pending Applications',
        value: metrics.pendingApplications == null
            ? '—'
            : _number.format(metrics.pendingApplications),
        icon: Icons.assignment_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 900 ? 3 : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _buildTrafficCard(TrafficSeries traffic) {
    final updated = _updatedAt == null
        ? null
        : _refreshFailed
        ? 'Last refresh failed · showing ${DateFormat('HH:mm:ss').format(_updatedAt!)}'
        : 'Updated ${DateFormat('HH:mm:ss').format(_updatedAt!)}';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Real-time Traffic',
                      style: TextStyle(
                        color: AdminColors.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Requests per minute vs baseline capacity',
                      style: TextStyle(
                        color: AdminColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    if (updated != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        updated,
                        style: TextStyle(
                          color: _refreshFailed
                              ? const Color(0xFFC62828)
                              : AdminColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    _ChipButton(
                      label: 'Live',
                      active: _range == 'live',
                      onTap: () => _setRange('live'),
                    ),
                    const SizedBox(width: 6),
                    _ChipButton(
                      label: '24h',
                      active: _range == '24h',
                      onTap: () => _setRange('24h'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 20, 12),
              child: traffic.points.length < 2
                  ? const Center(
                      child: Text(
                        'Request telemetry is not available from this backend.',
                        style: TextStyle(color: AdminColors.textMuted),
                      ),
                    )
                  : _TrafficChart(traffic: traffic, range: _range),
            ),
          ),
          if (traffic.baselinePerMinute != null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Wrap(
                spacing: 16,
                children: [
                  _Legend(color: AdminColors.primary, label: 'Requests / min'),
                  _Legend(
                    color: Color(0xFF9CA3AF),
                    label: 'Baseline capacity',
                    dashed: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditLog() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.history, size: 18, color: AdminColors.primary),
                SizedBox(width: 8),
                Text(
                  'Audit Log',
                  style: TextStyle(
                    color: AdminColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AdminColors.border, height: 1),
          if (_auditLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_auditError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _ErrorCard(
                title: 'Could not load the audit log.',
                message: _auditError!,
                onRetry: _loadAudit,
                bordered: false,
              ),
            )
          else if (_audit.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No audit events recorded yet.',
                  style: TextStyle(color: AdminColors.textMuted),
                ),
              ),
            )
          else ...[
            for (var i = 0; i < _audit.length; i++)
              _AuditRow(entry: _audit[i], isLast: i == _audit.length - 1),
            if (_auditCursor != null) ...[
              const Divider(color: AdminColors.border, height: 1),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _auditLoadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          onPressed: _loadOlderAudit,
                          child: const Text('Load older logs'),
                        ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Traffic chart
// ─────────────────────────────────────────────

class _TrafficChart extends StatelessWidget {
  final TrafficSeries traffic;
  final String range;
  const _TrafficChart({required this.traffic, required this.range});

  @override
  Widget build(BuildContext context) {
    final points = traffic.points;
    final baseline = traffic.baselinePerMinute;
    var maxY = points.fold<double>(
      0,
      (m, p) => p.requests > m ? p.requests : m,
    );
    if (baseline != null && baseline > maxY) maxY = baseline;
    maxY = maxY <= 0 ? 10 : maxY * 1.15;
    final interval = maxY / 4;
    final timeFormat = DateFormat(range == 'live' ? 'HH:mm' : 'HH:00');
    final labelStep = (points.length / 6).ceil().clamp(1, points.length);

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
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (baseline != null)
              HorizontalLine(
                y: baseline,
                color: const Color(0xFF9CA3AF),
                strokeWidth: 1.5,
                dashArray: [6, 4],
              ),
          ],
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
              reservedSize: 44,
              interval: interval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  NumberFormat.compact().format(value),
                  style: _axisStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: labelStep.toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    timeFormat.format(points[i].time),
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
              return LineTooltipItem(
                '${timeFormat.format(p.time)}\n'
                '${_number.format(p.requests)} req/min',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].requests),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            color: AdminColors.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0x140A3FA6),
            ),
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

  IconData get _icon => switch (entry.category) {
    AuditCategory.config => Icons.tune,
    AuditCategory.backup => Icons.backup_outlined,
    AuditCategory.adminAction => Icons.admin_panel_settings_outlined,
    AuditCategory.security => Icons.lock_outline,
    AuditCategory.other => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: entry.isSystem ? const Color(0xFFD9F5E0) : _blueBg,
            child: entry.isSystem
                ? const Icon(Icons.settings_outlined, size: 16, color: _green)
                : Text(
                    entry.initials,
                    style: const TextStyle(
                      color: AdminColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.actorName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AdminColors.textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.timeLabel,
                      style: const TextStyle(
                        color: AdminColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 6),
                      child: Icon(
                        _icon,
                        size: 13,
                        color: AdminColors.textMuted,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.action,
                        style: const TextStyle(
                          color: AdminColors.textMuted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          entry.recordType ==
                              AuditRecordType.currentStateSummary
                          ? const Color(0xFFFFF3CD)
                          : _surface2,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.recordTypeLabel,
                      style: const TextStyle(
                        color: AdminColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (entry.detail != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _surface2,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.detail!,
                      style: const TextStyle(
                        color: AdminColors.textDark,
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
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

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final bool bordered;
  const _ErrorCard({
    required this.title,
    required this.message,
    required this.onRetry,
    this.bordered = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AdminColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
    return bordered ? _Card(child: content) : content;
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? caption;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AdminColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _blueBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: AdminColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: AdminColors.textDark,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              caption ?? '',
              style: const TextStyle(
                color: AdminColors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _Legend({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 4,
                  height: 2,
                  margin: const EdgeInsets.only(right: 2),
                  color: color,
                ),
            ],
          )
        else
          Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label, style: _axisStyle),
      ],
    );
  }
}

class _ChipButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ChipButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AdminColors.primary : Colors.white,
          border: Border.all(
            color: active ? AdminColors.primary : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AdminColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
