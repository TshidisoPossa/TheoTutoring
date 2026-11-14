// Payouts: tutor earnings recorded per lesson. An administrator first
// approves a pending payout, then marks it as paid once the payment has been
// made outside the platform. Marking as paid only records the status; this
// page never transfers money.

import 'package:flutter/material.dart';

import 'Services/admin_payouts_service.dart';
import 'admin_access_guard.dart';
import 'admin_shell.dart';
import 'models/admin_payout_models.dart';
import 'models/refund_models.dart' show formatCaseDate, formatRand;

const _green = Color(0xFF1B7F3A);
const _greenBg = Color(0xFFD9F5E0);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFDEBD0);
const _blue = Color(0xFF1D4ED8);
const _blueBg = Color(0xFFDCE8FF);
const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDE2E2);
const _grey = AdminColors.textMuted;
const _greyBg = Color(0xFFF3F4F6);

const managePayoutsPermission = 'admin.payouts.manage';

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

class AdminPayoutsScreen extends StatefulWidget {
  const AdminPayoutsScreen({super.key, this.service});

  final AdminPayoutsService? service;

  @override
  State<AdminPayoutsScreen> createState() => _AdminPayoutsScreenState();
}

class _AdminPayoutsScreenState extends State<AdminPayoutsScreen> {
  late final _service = widget.service ?? AdminPayoutsService();

  static const _filters = <(String, PayoutStatus?)>[
    ('All', null),
    ('Pending', PayoutStatus.pending),
    ('Approved', PayoutStatus.approved),
    ('Paid', PayoutStatus.paid),
  ];

  PayoutStatus? _status;
  int _page = 1;
  AdminPayoutsPage? _result;
  bool _loading = true;
  String? _error;

  /// The payout an action is running for, so only its button shows progress.
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchPayouts(status: _status, page: _page);
      if (!mounted) return;
      setState(() {
        _result = result;
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

  void _setStatus(PayoutStatus? status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _page = 1;
    });
    _load();
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _load();
  }

  bool get _canManage =>
      AdminPermissionScope.maybeOf(context)?.has(managePayoutsPermission) ??
      false;

  // ------------------------------------------------------------ actions

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color color,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: color),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(
    AdminPayout payout,
    Future<void> Function() action,
    String success,
  ) async {
    setState(() => _busyId = payout.id);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _red,
          content: Text('Action failed: ${_msg(e)}'),
        ),
      );
      // The payout may have changed under another admin: show its real state.
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _approve(AdminPayout p) async {
    final ok = await _confirm(
      title: 'Approve payout?',
      message:
          'Approve the ${formatRand(p.netAmount)} payout to ${p.tutorName} '
          '(payout #${p.id})? Approval confirms the amount is owed. It does '
          'not pay the tutor; mark it as paid once the payment has been made.',
      confirmLabel: 'Approve payout',
      color: _green,
    );
    if (!ok) return;
    await _run(p, () => _service.approve(p.id), 'Payout approved.');
  }

  Future<void> _markPaid(AdminPayout p) async {
    final ok = await _confirm(
      title: 'Mark payout as paid?',
      message:
          'Record that ${formatRand(p.netAmount)} has been paid to '
          '${p.tutorName} (payout #${p.id})? This only records the payment '
          'status. It does not transfer any money, and it cannot be undone.',
      confirmLabel: 'Mark as paid',
      color: AdminColors.primary,
    );
    if (!ok) return;
    await _run(p, () => _service.markPaid(p.id), 'Payout recorded as paid.');
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.payouts,
      adminName: _result?.adminName,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final result = _result;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                if (result == null)
                  _Card(
                    child: _StateMessage(
                      icon: Icons.cloud_off_outlined,
                      iconColor: _red,
                      iconBg: _redBg,
                      title: 'Could not load payouts.',
                      message: _error ?? 'Please try again.',
                      action: ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  )
                else ...[
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!, onRetry: _load),
                    const SizedBox(height: 16),
                  ],
                  _buildStats(result.summary),
                  const SizedBox(height: 20),
                  _buildList(result),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payouts',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AdminColors.textDark,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Approve tutor earnings, then record them as paid once the '
              'payment has been made.',
              style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: _loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _buildStats(PayoutSummary s) {
    final cards = [
      _StatCard(
        label: 'Pending approval',
        value: '${s.pendingCount}',
        caption: '${formatRand(s.pendingNetAmount)} tutor net',
        valueColor: s.pendingCount > 0 ? _amber : null,
      ),
      _StatCard(
        label: 'Approved, not yet paid',
        value: '${s.approvedCount}',
        caption: '${formatRand(s.approvedNetAmount)} to be paid',
        valueColor: s.approvedCount > 0 ? _blue : null,
      ),
      _StatCard(
        label: 'Paid',
        value: '${s.paidCount}',
        caption: '${formatRand(s.paidNetAmount)} recorded as paid',
        valueColor: _green,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 640 ? 3 : 1;
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

  Widget _buildList(AdminPayoutsPage result) {
    final canManage = _canManage;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in _filters)
                      _FilterChip(
                        label: f.$1,
                        active: _status == f.$2,
                        onTap: () => _setStatus(f.$2),
                      ),
                  ],
                ),
                Text(
                  '${result.total} '
                  '${result.total == 1 ? 'payout' : 'payouts'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminColors.border),
          if (result.payouts.isEmpty)
            _StateMessage(
              icon: Icons.payments_outlined,
              iconColor: AdminColors.primary,
              iconBg: AdminColors.selected,
              title: _status == null
                  ? 'No payouts yet'
                  : 'No ${_status!.label.toLowerCase()} payouts',
              message: _status == null
                  ? 'Tutor payouts will appear here once they are recorded.'
                  : 'Choose another status to see other payouts.',
            )
          else
            for (final (i, payout) in result.payouts.indexed) ...[
              if (i > 0) const Divider(height: 1, color: AdminColors.border),
              _PayoutTile(
                payout: payout,
                canManage: canManage,
                busy: _busyId == payout.id,
                actionsLocked: _busyId != null,
                onApprove: () => _approve(payout),
                onMarkPaid: () => _markPaid(payout),
              ),
            ],
          if (result.pageCount > 1) ...[
            const Divider(height: 1, color: AdminColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Page ${result.page} of ${result.pageCount}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.textMuted,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _loading || result.page <= 1
                        ? null
                        : () => _goToPage(result.page - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _loading || result.page >= result.pageCount
                        ? null
                        : () => _goToPage(result.page + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  const _PayoutTile({
    required this.payout,
    required this.canManage,
    required this.busy,
    required this.actionsLocked,
    required this.onApprove,
    required this.onMarkPaid,
  });

  final AdminPayout payout;
  final bool canManage;
  final bool busy;
  final bool actionsLocked;
  final VoidCallback onApprove;
  final VoidCallback onMarkPaid;

  String _bookingLine(PayoutBooking b) {
    final parts = <String>[
      'Booking #${b.bookingId}',
      if (b.subject != null) b.subject!,
      if (b.studentName != null) 'Student: ${b.studentName}',
      if (b.date != null)
        [
          b.date!,
          if (b.startTime != null)
            b.endTime == null ? b.startTime! : '${b.startTime}–${b.endTime}',
        ].join(' '),
    ];
    return parts.join(' · ');
  }

  Widget? _action() {
    if (!canManage) return null;
    final onPressed = actionsLocked ? null : _onPressed;
    final child = busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null;
    return switch (payout.status) {
      PayoutStatus.pending => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(backgroundColor: _green),
        child: child ?? const Text('Approve payout'),
      ),
      PayoutStatus.approved => FilledButton(
        onPressed: onPressed,
        child: child ?? const Text('Mark as paid'),
      ),
      PayoutStatus.paid || PayoutStatus.unknown => null,
    };
  }

  VoidCallback? get _onPressed => switch (payout.status) {
    PayoutStatus.pending => onApprove,
    PayoutStatus.approved => onMarkPaid,
    PayoutStatus.paid || PayoutStatus.unknown => null,
  };

  @override
  Widget build(BuildContext context) {
    final booking = payout.booking;
    final action = _action();
    final timeline = <String>[
      if (payout.createdAt != null)
        'Created ${formatCaseDate(payout.createdAt!)}',
      if (payout.approvedAt != null)
        'Approved ${formatCaseDate(payout.approvedAt!)}'
            '${payout.approvedBy == null ? '' : ' by ${payout.approvedBy}'}',
      if (payout.paidAt != null)
        'Marked paid ${formatCaseDate(payout.paidAt!)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        payout.tutorName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.textDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StatusBadge(payout.status),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Payout #${payout.id}'
                    '${payout.tutorEmail == null ? '' : ' · ${payout.tutorEmail}'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.textMuted,
                    ),
                  ),
                ],
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 28,
            runSpacing: 8,
            children: [
              _Amount(label: 'Gross amount', value: payout.amount),
              _Amount(label: 'Commission', value: payout.commissionAmount),
              _Amount(
                label: 'Tutor net',
                value: payout.netAmount,
                emphasised: true,
              ),
            ],
          ),
          if (booking != null) ...[
            const SizedBox(height: 10),
            Text(
              _bookingLine(booking),
              style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
            ),
          ],
          if (timeline.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              timeline.join('  ·  '),
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final String label;
  final double value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AdminColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          formatRand(value),
          style: TextStyle(
            fontSize: emphasised ? 16 : 14,
            fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
            color: AdminColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final PayoutStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      PayoutStatus.pending => (_amberBg, _amber),
      PayoutStatus.approved => (_blueBg, _blue),
      PayoutStatus.paid => (_greenBg, _green),
      PayoutStatus.unknown => (_greyBg, _grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // A refresh failed: the last loaded payouts stay, but say so.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: _redBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: _red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not refresh payouts: $message',
              style: const TextStyle(fontSize: 13, color: _red),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

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

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.textMuted,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 14), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.caption,
    this.valueColor,
  });

  final String label;
  final String value;
  final String caption;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AdminColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? AdminColors.textDark,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              caption,
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
