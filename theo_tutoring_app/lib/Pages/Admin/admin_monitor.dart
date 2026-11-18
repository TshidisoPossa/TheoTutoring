// Monitor Platform: the platform counts the database can answer (active users,
// active tutors, pending tutor applications) and the audit log of recorded
// administrator activity.
//
// Uptime, request rate, error rate, latency and traffic are not shown: this
// backend records no request telemetry, so there is nothing real to display.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/monitor_models.dart';
import 'Services/monitor_services.dart';
import 'admin_shell.dart';

const _surface2 = Color(0xFFF8F9FB);
const _green = Color(0xFF1B7F3A);
const _blueBg = Color(0xFFDCE8FF);

final _number = NumberFormat('#,##0');

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

  MonitorSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

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
      final snapshot = await _service.fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
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
                else
                  _buildOperationalStats(_snapshot!.operationalMetrics),
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
          'Current platform counts and recorded administrator activity.',
          style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
        ),
      ],
    );
  }

  // Only counts the backend actually returned are shown; a missing one is
  // left out rather than shown as a dash.
  Widget _buildOperationalStats(OperationalMetrics metrics) {
    final cards = [
      for (final (label, value, icon) in [
        ('Active Users', metrics.activeUsers, Icons.people_outline),
        ('Active Tutors', metrics.activeTutors, Icons.school_outlined),
        (
          'Pending Applications',
          metrics.pendingApplications,
          Icons.assignment_outlined,
        ),
      ])
        if (value != null)
          _MetricCard(label: label, value: _number.format(value), icon: icon),
    ];
    if (cards.isEmpty) {
      return const _Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No platform counts are available right now.',
              style: TextStyle(color: AdminColors.textMuted),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 900 ? cards.length : 1;
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
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
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
          ],
        ),
      ),
    );
  }
}
