// Payouts: the platform's money overview and tutor earnings recorded per
// lesson. An administrator generates payouts for finished lessons, approves a
// pending payout, then marks it as paid (with an optional external reference)
// once the payment has been made outside the platform. Marking as paid only
// records the payment; this page never transfers money. The figures and
// their definitions come from the backend (lib/payout_finance.dart).

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

/// Cents -> "R 1,234.50" (display only; amounts stay in cents).
String _rand(int cents) => formatRand(cents / 100);

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
  bool _generating = false;

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
    // null = cancelled; '' = paid without a reference.
    final reference = await showDialog<String>(
      context: context,
      builder: (_) => _MarkPaidDialog(payout: p),
    );
    if (reference == null) return;
    await _run(
      p,
      () => _service.markPaid(p.id, reference: reference),
      'Payout recorded as paid.',
    );
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final result = await _service.generate();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _red,
          content: Text('Could not generate payouts: ${_msg(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
    // Totals and the list change either way (another admin may have run it).
    if (mounted) await _load();
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
                  if (result.finance == null)
                    _buildStats(result.summary)
                  else
                    _buildFinance(result.finance!),
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
              'Generate payouts for finished lessons, approve them, then '
              'record them as paid once the payment has been made.',
              style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (_canManage)
              FilledButton.icon(
                onPressed: _loading || _generating || _busyId != null
                    ? null
                    : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.playlist_add_check, size: 18),
                label: const Text('Generate eligible payouts'),
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
        ),
      ],
    );
  }

  /// The four headline figures, any reconciliation warnings, then where
  /// every rand received has gone.
  Widget _buildFinance(PayoutFinance f) {
    final cards = [
      _StatCard(
        label: 'Money received',
        value: _rand(f.moneyReceived),
        caption: 'Successful student payments',
      ),
      _StatCard(
        label: 'Platform commission',
        value: _rand(f.platformCommission),
        caption: 'Earned on completed lessons',
        valueColor: _green,
      ),
      _StatCard(
        label: 'Owed to tutors',
        value: _rand(f.owedToTutors),
        caption:
            '${f.pendingPayouts} pending approval · '
            '${f.approvedPayouts} approved',
        valueColor: f.owedToTutors > 0 ? _amber : null,
      ),
      _StatCard(
        label: 'Paid to tutors',
        value: _rand(f.paidToTutors),
        caption:
            '${f.paidPayouts} ${f.paidPayouts == 1 ? 'payout' : 'payouts'} '
            'recorded as paid',
        valueColor: _blue,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardGrid(cards, wide: 4),
        if (f.issues.isNotEmpty) ...[
          const SizedBox(height: 14),
          _IssuesBanner(issues: f.issues),
        ],
        const SizedBox(height: 14),
        _Reconciliation(finance: f),
      ],
    );
  }

  Widget _cardGrid(List<Widget> cards, {required int wide}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 900
            ? wide
            : constraints.maxWidth >= 560
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
    // A Pending, Approved or Processed refund blocks approval and payment
    // (the backend refuses them too); refund is null for a rejected one.
    final onPressed = actionsLocked || payout.refundStatus != null
        ? null
        : _onPressed;
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
        'Marked paid ${formatCaseDate(payout.paidAt!)}'
            '${payout.paidBy == null ? '' : ' by ${payout.paidBy}'}',
    ];
    final rate = payout.commissionRate;
    final commissionLabel = rate == null
        ? 'Commission'
        : 'Commission ($rate%'
              '${payout.commissionRateBackfilled ? ', backfilled rate' : ''})';
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
              _Amount(label: commissionLabel, value: payout.commissionAmount),
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
          if (payout.paymentReference != null) ...[
            const SizedBox(height: 4),
            Text(
              'Payment reference: ${payout.paymentReference}',
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.textDark,
              ),
            ),
          ],
          if (payout.refundStatus != null) ...[
            const SizedBox(height: 10),
            _RefundFlag(payout: payout),
          ],
        ],
      ),
    );
  }
}

/// A refund recorded for the lesson after its payout was generated. The
/// payout is never changed automatically; an administrator has to review it.
class _RefundFlag extends StatelessWidget {
  const _RefundFlag({required this.payout});
  final AdminPayout payout;

  @override
  Widget build(BuildContext context) {
    final pending = payout.refundStatus == 'pending';
    final amount = formatRand(payout.refundAmount ?? 0);
    final paid = payout.status == PayoutStatus.paid;
    final next = paid
        ? 'it was already paid, so recover the amount from the tutor if '
              'needed.'
        : 'it cannot be approved or paid until the refund is resolved.';
    final text = pending
        ? 'A refund is awaiting a decision for this lesson. '
              '${paid ? 'This payout was already paid.' : 'This payout cannot be approved or paid until it is decided.'}'
        : 'Refund of $amount ${payout.refundStatus} after this payout was '
              'generated. The payout was not changed: $next';
    final (bg, fg) = pending ? (_amberBg, _amber) : (_redBg, _red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Mark as paid: confirms, and takes the optional external payment
/// reference. Pops the trimmed reference ('' for none), or null to cancel.
class _MarkPaidDialog extends StatefulWidget {
  const _MarkPaidDialog({required this.payout});
  final AdminPayout payout;

  @override
  State<_MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends State<_MarkPaidDialog> {
  final _reference = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payout;
    return AlertDialog(
      title: const Text('Mark payout as paid?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record that ${formatRand(p.netAmount)} has been paid to '
              '${p.tutorName} (payout #${p.id})? This only records the '
              'payment. It does not transfer any money, and it cannot be '
              'undone.',
            ),
            if (p.flagged) ...[
              const SizedBox(height: 10),
              const Text(
                'This lesson has a refund recorded after the payout was '
                'generated. Check it before paying.',
                style: TextStyle(color: _red, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _reference,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Payment reference (optional)',
                hintText: 'e.g. the EFT reference',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reference.text.trim()),
          child: const Text('Mark as paid'),
        ),
      ],
    );
  }
}

/// Reconciliation findings: anything that does not add up is shown, never
/// adjusted away.
class _IssuesBanner extends StatelessWidget {
  const _IssuesBanner({required this.issues});
  final List<PayoutIssue> issues;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, issue) in issues.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: issue.isWarning ? _amberBg : _blueBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  issue.isWarning
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline,
                  size: 18,
                  color: issue.isWarning ? _amber : _blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    [
                      issue.message,
                      if (issue.count != null)
                        '${issue.count} '
                            '${issue.count == 1 ? 'record' : 'records'}',
                      if (issue.amountCents != null) _rand(issue.amountCents!),
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: issue.isWarning ? _amber : _blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Where every rand received has gone. Each paid lesson is counted in exactly
/// one line; the difference is shown as it is.
class _Reconciliation extends StatelessWidget {
  const _Reconciliation({required this.finance});
  final PayoutFinance finance;

  @override
  Widget build(BuildContext context) {
    final f = finance;
    final lines = <(String, int)>[
      ('Refunded to students', f.refunded),
      ('Retained from cancellations', f.retainedCancellationRevenue),
      ('Awaiting a refund decision', f.awaitingRefundDecision),
      (
        'Held for upcoming lessons (${f.upcomingLessons})',
        f.heldForUpcomingLessons,
      ),
      (
        'Finished lessons awaiting payout generation '
            '(${f.awaitingPayoutGenerationCount})',
        f.awaitingPayoutGeneration,
      ),
      ('Platform commission', f.platformCommission),
      ('Owed to tutors', f.owedToTutors),
      ('Paid to tutors', f.paidToTutors),
      if (f.unallocated != 0) ('Unallocated (see warnings)', f.unallocated),
    ];
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Where the money is',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AdminColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            _Line('Money received from students', f.moneyReceived, bold: true),
            const Divider(height: 18, color: AdminColors.border),
            for (final (label, cents) in lines) _Line(label, cents),
            const Divider(height: 18, color: AdminColors.border),
            _Line('Accounted for', f.accountedFor, bold: true),
            _Line(
              'Difference',
              f.difference,
              bold: true,
              color: f.difference == 0 ? _green : _red,
            ),
            const SizedBox(height: 8),
            Text(
              f.reconciled
                  ? 'Reconciled: every rand received is accounted for.'
                  : 'Not reconciled: ${_rand(f.difference)} is not explained '
                        'by the records. See the warnings above.',
              style: TextStyle(
                fontSize: 12,
                color: f.reconciled ? _green : _red,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (f.eligibleLessons > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${f.eligibleLessons} finished '
                '${f.eligibleLessons == 1 ? 'lesson is' : 'lessons are'} '
                'ready for a payout: use Generate eligible payouts.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.cents, {this.bold = false, this.color});
  final String label;
  final int cents;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color ?? AdminColors.textDark,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(_rand(cents), style: style),
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
