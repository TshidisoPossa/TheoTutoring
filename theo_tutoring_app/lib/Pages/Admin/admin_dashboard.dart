// Admin landing page ("System Overview"). Shown straight after an Admin signs
// in, inside the shared AdminShell (sidebar + top bar).
//
// Every figure comes from an existing backend endpoint, and each section only
// loads when the signed-in Admin's role grants the matching permission:
//   GET /admin/me                         -> admin name and permissions
//   GET /admin/monitor?range=live         -> active users / tutors, pending applications
//   GET /admin/monitor/audit-log          -> recent activity
//   GET /admin/refunds?type=cancellation  -> pending refund count and amount
// There is no revenue, growth or session-volume endpoint yet, so those parts of
// the design are intentionally left out rather than filled with sample data.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'Services/admin_access_service.dart';
import 'Services/monitor_services.dart';
import 'Services/refund_services.dart';
import 'admin_shell.dart';
import 'models/monitor_models.dart';
import 'models/refund_models.dart';

final _count = NumberFormat('#,##0');

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

const _cardShadow = [
  BoxShadow(color: Color(0x0F111827), blurRadius: 12, offset: Offset(0, 4)),
];

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    this.loadAccess,
    this.loadMonitor,
    this.loadActivity,
    this.loadRefunds,
  });

  // Injectable for tests; default to the existing Admin services.
  final Future<AdminAccessResult> Function()? loadAccess;
  final Future<MonitorSnapshot> Function()? loadMonitor;
  final Future<AuditLogPage> Function()? loadActivity;
  final Future<RefundCasesResult> Function()? loadRefunds;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

/// Load state of one independently fetched dashboard section.
class _Section<T> {
  bool loading = false;
  T? data;
  String? error;
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminMonitorService? _monitorService;

  bool _accessLoading = true;
  String? _accessError;
  AdminAccessResult? _access;

  final _monitor = _Section<MonitorSnapshot>();
  final _activity = _Section<AuditLogPage>();
  final _refunds = _Section<RefundCasesResult>();

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void dispose() {
    _monitorService?.dispose();
    super.dispose();
  }

  bool _can(String permission) =>
      _access?.permissions.contains(permission) ?? false;

  bool get _canMonitor => _can('admin.monitor.read');
  bool get _canRefunds => _can('admin.refunds.read');
  bool get _canApplications => _can('admin.applications.read');
  bool get _canRefundsPage =>
      _can('admin.refunds.read') && _can('admin.reports.read');

  AdminMonitorService get _monitorApi =>
      _monitorService ??= AdminMonitorService();

  // ------------------------------------------------------------ loading

  Future<void> _loadAccess() async {
    setState(() {
      _accessLoading = true;
      _accessError = null;
    });
    final AdminAccessResult access;
    try {
      access = await (widget.loadAccess ??
          () => AdminAccessService().checkCurrentUser())();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _accessError = _msg(e);
        _accessLoading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _access = access.isAllowed ? access : null;
      _accessError = access.isAllowed
          ? null
          : 'Administrator access could not be verified.';
      _accessLoading = false;
    });
    if (!access.isAllowed) return;
    if (_canMonitor) {
      _loadMonitor();
      _loadActivity();
    }
    if (_canRefunds) _loadRefunds();
  }

  Future<void> _run<T>(_Section<T> section, Future<T> Function() load) async {
    setState(() {
      section.loading = true;
      section.error = null;
    });
    try {
      final data = await load();
      if (!mounted) return;
      setState(() {
        section.data = data;
        section.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        section.error = _msg(e);
        section.loading = false;
      });
    }
  }

  Future<void> _loadMonitor() => _run(
    _monitor,
    widget.loadMonitor ?? () => _monitorApi.fetchSnapshot('live'),
  );

  Future<void> _loadActivity() => _run(
    _activity,
    widget.loadActivity ?? () => _monitorApi.fetchAuditLog(limit: 5),
  );

  Future<void> _loadRefunds() => _run(
    _refunds,
    widget.loadRefunds ??
        () => AdminRefundsService().fetchCases(
          type: CaseType.cancellation,
          status: 'open',
        ),
  );

  void _open(String route) => Navigator.pushReplacementNamed(context, route);

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.dashboard,
      adminName: _access?.adminName,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                const SizedBox(height: 24),
                if (_accessLoading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_access == null)
                  _SurfaceCard(
                    child: _Notice(
                      icon: Icons.error_outline,
                      title: 'Could not load the dashboard.',
                      message: _accessError,
                      onRetry: _loadAccess,
                    ),
                  )
                else
                  ..._buildContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    final stats = _buildStatCards();
    final actions = _buildQuickActions();
    final activity = _canMonitor ? _buildActivity() : null;

    return [
      if (stats.isNotEmpty) ...[
        _StatGrid(cards: stats),
        if (_monitor.error != null || _refunds.error != null) ...[
          const SizedBox(height: 12),
          _InlineError(
            message: 'Some figures could not be loaded.',
            onRetry: () {
              if (_monitor.error != null) _loadMonitor();
              if (_refunds.error != null) _loadRefunds();
            },
          ),
        ],
        const SizedBox(height: 24),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          if (activity != null && constraints.maxWidth >= 960) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: activity),
                const SizedBox(width: 24),
                Expanded(child: actions),
              ],
            );
          }
          // Narrow screens: shortcuts first, then the activity feed.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              actions,
              if (activity != null) ...[const SizedBox(height: 24), activity],
            ],
          );
        },
      ),
    ];
  }

  List<_StatCard> _buildStatCards() {
    final ops = _monitor.data?.operationalMetrics;
    final summary = _refunds.data?.summary;
    return [
      if (_canMonitor) ...[
        _StatCard(
          label: 'Active Users',
          value: ops?.activeUsers,
          caption: 'Active accounts across all roles',
          icon: Icons.groups_outlined,
          tint: const Color(0xFF0052D4),
          loading: _monitor.loading,
        ),
        _StatCard(
          label: 'Active Tutors',
          value: ops?.activeTutors,
          caption: 'Approved and active',
          icon: Icons.co_present_outlined,
          tint: const Color(0xFF0E7490),
          loading: _monitor.loading,
        ),
        _StatCard(
          label: 'Pending Applications',
          value: ops?.pendingApplications,
          caption: 'Tutor applications awaiting review',
          icon: Icons.assignment_ind_outlined,
          tint: const Color(0xFFB45309),
          loading: _monitor.loading,
        ),
      ],
      if (_canRefunds)
        _StatCard(
          label: 'Pending Refunds',
          value: summary?.pendingRefunds,
          caption: summary == null
              ? 'Cancellation refunds awaiting a decision'
              : '${formatRand(summary.pendingRefundAmount)} awaiting a decision',
          icon: Icons.currency_exchange,
          tint: const Color(0xFFB42318),
          loading: _refunds.loading,
        ),
    ];
  }

  Widget _buildQuickActions() {
    final pendingApplications =
        _monitor.data?.operationalMetrics.pendingApplications;
    final pendingRefunds = _refunds.data?.summary.pendingRefunds;

    final actions = [
      if (_canApplications)
        _QuickAction(
          title: 'Review Applications',
          subtitle: pendingApplications == null
              ? 'Approve or reject tutor applications'
              : '${_count.format(pendingApplications)} pending '
                    '${pendingApplications == 1 ? 'application' : 'applications'}',
          icon: Icons.how_to_reg_outlined,
          onTap: () => _open(AdminRoutes.applications),
        ),
      if (_canRefundsPage)
        _QuickAction(
          title: 'Refunds & Issues',
          subtitle: pendingRefunds == null
              ? 'Decide refunds and resolve reports'
              : '${_count.format(pendingRefunds)} '
                    '${pendingRefunds == 1 ? 'request' : 'requests'} waiting',
          icon: Icons.payments_outlined,
          onTap: () => _open(AdminRoutes.refunds),
        ),
      if (_canMonitor)
        _QuickAction(
          title: 'Monitor Platform',
          subtitle: 'Uptime, traffic and audit log',
          icon: Icons.monitor_heart_outlined,
          onTap: () => _open(AdminRoutes.monitor),
        ),
      _QuickAction(
        title: 'Settings',
        subtitle: 'Session rate and account settings',
        icon: Icons.settings_outlined,
        onTap: () => _open(AdminRoutes.settings),
      ),
    ];
    return _QuickActionsPanel(actions: actions);
  }

  Widget _buildActivity() {
    final Widget body;
    if (_activity.loading && _activity.data == null) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_activity.error != null) {
      body = _Notice(
        icon: Icons.error_outline,
        title: 'Could not load recent activity.',
        message: _activity.error,
        onRetry: _loadActivity,
      );
    } else if (_activity.data?.entries.isEmpty ?? true) {
      body = const _Notice(
        icon: Icons.history,
        title: 'No recent activity.',
        message: 'Recorded administrator and system events will appear here.',
      );
    } else {
      final entries = _activity.data!.entries.take(5).toList();
      body = Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AdminColors.border),
            _ActivityRow(entry: entries[i]),
          ],
        ],
      );
    }

    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
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
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textDark,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _open(AdminRoutes.monitor),
                style: TextButton.styleFrom(
                  foregroundColor: AdminColors.accent,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'VIEW ALL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ widgets

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    const crumb = TextStyle(
      fontSize: 11,
      letterSpacing: 1,
      fontWeight: FontWeight.w600,
      color: AdminColors.textMuted,
    );
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('ADMIN', style: crumb),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('/', style: crumb),
            ),
            Text(
              'DASHBOARD',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: AdminColors.accent,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          'System Overview',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AdminColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
      boxShadow: _cardShadow,
    ),
    child: child,
  );
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cards});
  final List<_StatCard> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 16.0;
      final width = constraints.maxWidth;
      final perRow = width >= 1000
          ? cards.length.clamp(1, 4)
          : width >= 560
          ? cards.length.clamp(1, 2)
          : 1;
      final cardWidth = (width - gap * (perRow - 1)) / perRow;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards) SizedBox(width: cardWidth, child: card),
        ],
      );
    },
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.tint,
    required this.loading,
  });

  final String label;
  final int? value;
  final String caption;
  final IconData icon;
  final Color tint;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 152,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
        boxShadow: _cardShadow,
      ),
      child: Stack(
        children: [
          // Soft tinted base, echoing the coloured card footers in the design.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tint.withValues(alpha: 0),
                    tint.withValues(alpha: 0.12),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.textMuted,
                        ),
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 18, color: tint),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 40,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: loading && value == null
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            value == null ? '—' : _count.format(value),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.textDark,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({required this.actions});
  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AdminColors.primary, AdminColors.accent],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330A3FA6),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _QuickActionTile(action: actions[i], highlighted: i == 0),
          ],
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action, required this.highlighted});
  final _QuickAction action;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? AdminColors.primary : Colors.white;
    final subtle = highlighted
        ? AdminColors.textMuted
        : Colors.white.withValues(alpha: 0.75);
    return Material(
      color: highlighted ? Colors.white : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: highlighted
                      ? AdminColors.selected
                      : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(action.icon, size: 18, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: subtle),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});
  final AuditEntry entry;

  (IconData, String, Color) get _style => switch (entry.category) {
    AuditCategory.config => (Icons.tune, 'CONFIG', const Color(0xFF0A3FA6)),
    AuditCategory.backup => (
      Icons.backup_outlined,
      'BACKUP',
      const Color(0xFF1B7F3A),
    ),
    AuditCategory.adminAction => (
      Icons.admin_panel_settings_outlined,
      'ADMIN ACTION',
      const Color(0xFF0052D4),
    ),
    AuditCategory.security => (
      Icons.lock_outline,
      'SECURITY',
      const Color(0xFFB42318),
    ),
    AuditCategory.other => (
      Icons.circle_outlined,
      'EVENT',
      AdminColors.textMuted,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _style;
    final subtitle = [
      entry.isSystem ? 'System' : entry.actorName,
      ?entry.detail,
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.action,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                entry.timeLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 32, color: AdminColors.textMuted),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AdminColors.textDark,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.info_outline, size: 16, color: AdminColors.textMuted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
        ),
      ),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}
