// Refunds & Issues (project documentation 4.6, 4.9 and 9.5): summary badges, a
// filterable table of cases, and a review panel with the issue report, related
// records, the calculated refund and Deny / Approve Refund / Override Decision.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/refund_models.dart';
import 'Services/refund_services.dart';
import 'admin_shell.dart';

const _surface2 = Color(0xFFF8F9FB);
const _green = Color(0xFF1B7F3A);
const _greenBg = Color(0xFFD9F5E0);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFDEBD0);
const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDE2E2);
const _purple = Color(0xFF6D28D9);
const _purpleBg = Color(0xFFEDE4FF);
const _blueBg = Color(0xFFDCE8FF);
const _greyBg = Color(0xFFE8EAEE);
const _grey = Color(0xFF4B5563);

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

class AdminRefundsIssuesScreen extends StatefulWidget {
  const AdminRefundsIssuesScreen({super.key, this.service});

  final AdminRefundsService? service;

  @override
  State<AdminRefundsIssuesScreen> createState() =>
      _AdminRefundsIssuesScreenState();
}

class _AdminRefundsIssuesScreenState extends State<AdminRefundsIssuesScreen> {
  late final _service = widget.service ?? AdminRefundsService();

  static const _typeFilters = <(String, CaseType?)>[
    ('All Cases', null),
    ('Cancellations', CaseType.cancellation),
    ('User Reports', CaseType.report),
  ];
  static const _statusFilters = <(String, String)>[
    ('All statuses', 'all'),
    ('Open', 'open'),
    ('Resolved', 'resolved'),
  ];

  CaseType? _type;
  String _status = 'all';

  RefundCasesResult? _result;
  String? _selectedId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchCases(type: _type, status: _status);
      if (!mounted) return;
      setState(() {
        _result = result;
        final stillListed = result.cases.any((c) => c.id == _selectedId);
        if (!stillListed) {
          _selectedId = result.cases.isEmpty ? null : result.cases.first.id;
        }
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

  RefundCase? get _selected {
    final cases = _result?.cases ?? const <RefundCase>[];
    for (final c in cases) {
      if (c.id == _selectedId) return c;
    }
    return null;
  }

  void _setType(CaseType? type) {
    if (type == _type) return;
    setState(() => _type = type);
    _load();
  }

  void _setStatus(String status) {
    if (status == _status) return;
    setState(() => _status = status);
    _load();
  }

  // ------------------------------------------------------------ actions

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _red,
          content: Text('Action failed: ${_msg(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(RefundCase c) async {
    final amount = c.refundAmount == null
        ? 'the calculated refund'
        : formatRand(c.refundAmount!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve refund?'),
        content: Text(
          'Approve a refund decision of $amount for ${c.studentName} '
            '(${c.reference})? This records approval; payment processing '
            'is separate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _green),
            child: const Text('Approve Refund'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => _service.approve(c.id),
      'Refund decision approved. Payment processing remains separate.',
    );
  }

  Future<void> _deny(RefundCase c) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Deny refund',
        label: 'Reason for denying',
        confirmLabel: 'Deny Refund',
        confirmColor: _red,
      ),
    );
    if (reason == null) return;
    await _run(() => _service.deny(c.id, reason), 'Refund denied.');
  }

  Future<void> _override(RefundCase c) async {
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (_) => _OverrideDialog(refundCase: c),
    );
    if (result == null) return;
    await _run(
      () => _service.override(c.id, result.$1, result.$2),
      'Refund decision overridden.',
    );
  }

  Future<void> _resolve(RefundCase c) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Resolve report',
        label: 'Outcome of the investigation',
        confirmLabel: 'Mark Resolved',
        confirmColor: AdminColors.primary,
      ),
    );
    if (note == null) return;
    await _run(() => _service.resolve(c.id, note), 'Report resolved.');
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.refunds,
      adminName: _result?.adminName,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _result == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _Card(
              child: _StateMessage(
                icon: Icons.cloud_off_outlined,
                iconColor: _red,
                iconBg: _redBg,
                title: 'Could not load refunds and issues.',
                message: _error!,
                action: ElevatedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final selected = _selected;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Side-by-side review panel on wide screens, stacked below on narrow ones.
        if (constraints.maxWidth < 1000) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMainContent(),
                if (selected != null) ...[
                  const SizedBox(height: 20),
                  _Card(child: _buildReviewPanel(selected)),
                ],
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildMainContent(),
              ),
            ),
            Container(
              width: 340,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: AdminColors.border)),
              ),
              child: selected == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _result!.cases.isEmpty
                              ? 'No cases to review.'
                              : 'Select a case to review it.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AdminColors.textMuted),
                        ),
                      ),
                    )
                  : SingleChildScrollView(child: _buildReviewPanel(selected)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Refunds & Issues',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AdminColors.textDark,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Review cancellation refunds and user reports, and override decisions where necessary.',
          style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 20),
        // A filter change or refresh failed: keep the last loaded cases on
        // screen, but say so instead of silently showing stale data.
        if (_error != null) ...[
          Container(
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
                    'Could not refresh cases: $_error',
                    style: const TextStyle(fontSize: 13, color: _red),
                  ),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _buildStatsRow(_result!.summary),
        const SizedBox(height: 20),
        _buildCaseTable(_result!.cases),
      ],
    );
  }

  Widget _buildStatsRow(RefundSummary s) {
    final cards = [
      _StatCard(
        label: 'Open Disputes',
        value: '${s.openDisputes}',
        caption: 'User reports not yet resolved',
      ),
      _StatCard(
        label: 'Pending Refunds',
        value: '${s.pendingRefunds}',
        caption: '${formatRand(s.pendingRefundAmount)} awaiting a decision',
      ),
      _StatCard(
        label: 'Resolved (7 days)',
        value: '${s.resolvedLast7Days}',
        caption: 'Cases closed this week',
        valueColor: _green,
      ),
      _StatCard(
        label: 'Needs Action',
        value: '${s.needsAction}',
        caption: 'Waiting on an administrator',
        valueColor: s.needsAction > 0 ? _red : null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 420
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

  Widget _buildCaseTable(List<RefundCase> cases) {
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
                    for (final f in _typeFilters)
                      _FilterChip(
                        label: f.$1,
                        active: _type == f.$2,
                        onTap: () => _setType(f.$2),
                      ),
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
                    DropdownButton<String>(
                      value: _status,
                      underline: const SizedBox(),
                      isDense: true,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AdminColors.textDark,
                      ),
                      items: [
                        for (final f in _statusFilters)
                          DropdownMenuItem(value: f.$2, child: Text(f.$1)),
                      ],
                      onChanged: (v) {
                        if (v != null) _setStatus(v);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: AdminColors.border, height: 1),
          _MinWidthScroll(
            minWidth: 720,
            child: Column(
              children: [
                Container(
                  color: _surface2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: _TableHeader('Reference')),
                      Expanded(flex: 3, child: _TableHeader('Student & Tutor')),
                      Expanded(flex: 2, child: _TableHeader('Issue Type')),
                      Expanded(flex: 2, child: _TableHeader('Amount')),
                      Expanded(flex: 2, child: _TableHeader('Status')),
                      Expanded(flex: 2, child: _TableHeader('Actions')),
                    ],
                  ),
                ),
                const Divider(color: AdminColors.border, height: 1),
                for (var i = 0; i < cases.length; i++)
                  _CaseRow(
                    refundCase: cases[i],
                    selected: cases[i].id == _selectedId,
                    onTap: () => setState(() => _selectedId = cases[i].id),
                    isLast: i == cases.length - 1,
                  ),
              ],
            ),
          ),
          // Outside the min-width scroll so it stays centred on phones.
          if (cases.isEmpty)
            _type == null && _status == 'all'
                ? const _StateMessage(
                    icon: Icons.inbox_outlined,
                    iconColor: AdminColors.primary,
                    iconBg: _blueBg,
                    title: 'No refund cases or reports yet',
                    message:
                        'Cancellation refunds and user reports will appear '
                        'here as soon as they are submitted.',
                  )
                : _StateMessage(
                    icon: Icons.filter_alt_off_outlined,
                    iconColor: _grey,
                    iconBg: _greyBg,
                    title: 'No cases match these filters',
                    message: 'Try another case type or status to see more cases.',
                    action: TextButton(
                      onPressed: () {
                        setState(() {
                          _type = null;
                          _status = 'all';
                        });
                        _load();
                      },
                      child: const Text('Clear filters'),
                    ),
                  ),
          const Divider(color: AdminColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              cases.length == 1 ? '1 case' : '${cases.length} cases',
              style: const TextStyle(
                color: AdminColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewPanel(RefundCase c) {
    final notice = c.hoursNotice;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: c.reference));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reference copied')),
                        );
                      },
                      child: Text(
                        c.reference,
                        style: const TextStyle(
                          color: AdminColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.type == CaseType.report
                          ? 'Report Review'
                          : 'Refund Review',
                      style: const TextStyle(
                        color: AdminColors.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(c.status),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionLabel('PARTIES INVOLVED'),
          const SizedBox(height: 8),
          _PartyRow(
            name: c.studentName,
            role: c.reportedBy == 'student' ? 'Student · Reporter' : 'Student',
          ),
          const SizedBox(height: 8),
          _PartyRow(
            name: c.tutorName,
            role: c.reportedBy == 'tutor' ? 'Tutor · Reporter' : 'Tutor',
          ),
          const SizedBox(height: 16),
          const Divider(color: AdminColors.border),
          const SizedBox(height: 12),
          const _SectionLabel('ISSUE REPORT'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface2,
              border: Border.all(color: AdminColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              c.reason ??
                  (c.type == CaseType.cancellation
                      ? notice == null
                            ? 'Booking cancelled.'
                            : 'Booking cancelled ${_formatNotice(notice)} before the session.'
                      : 'No description was provided.'),
              style: const TextStyle(
                color: AdminColors.textDark,
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('RELATED RECORDS'),
          const SizedBox(height: 8),
          _DetailRow(label: 'Booking', value: c.bookingId ?? '—'),
          _DetailRow(label: 'Subject', value: c.subject ?? '—'),
          _DetailRow(
            label: 'Session',
            value: c.sessionStart == null
                ? '—'
                : formatCaseDate(c.sessionStart!),
          ),
          if (c.cancelledAt != null)
            _DetailRow(
              label: 'Cancelled',
              value: formatCaseDate(c.cancelledAt!),
            ),
          if (c.type == CaseType.report && c.createdAt != null)
            _DetailRow(label: 'Reported', value: formatCaseDate(c.createdAt!)),
          _DetailRow(
            label: 'Amount paid',
            value: c.amountPaid == null ? 'Not paid' : formatRand(c.amountPaid!),
          ),
          if (c.paymentMethod != null)
            _DetailRow(label: 'Payment method', value: c.paymentMethod!),
          if (c.refundPercentage != null || c.refundAmount != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _blueBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.overriddenByAdmin
                        ? 'Refund (overridden by administrator)'
                        : 'Calculated Refund',
                    style: const TextStyle(
                      color: AdminColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.refundAmount == null ? '—' : formatRand(c.refundAmount!),
                    style: const TextStyle(
                      color: AdminColors.textDark,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (c.refundPercentage != null)
                    Text(
                      '${c.refundPercentage!.toStringAsFixed(0)}% of the amount paid',
                      style: const TextStyle(
                        color: AdminColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  if (c.decidedBy != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Decided by ${c.decidedBy}',
                      style: const TextStyle(
                        color: AdminColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (c.type == CaseType.cancellation) ...[
            const SizedBox(height: 10),
            const Text(
              'Policy: 48 hours or more before the session = 100%, '
              '24–48 hours = 50%, under 24 hours = no refund.',
              style: TextStyle(color: AdminColors.textMuted, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 16),
          ..._buildActions(c),
        ],
      ),
    );
  }

  List<Widget> _buildActions(RefundCase c) {
    final buttons = <Widget>[
      if (c.canApproveOrDeny)
        ElevatedButton(
          onPressed: _busy ? null : () => _approve(c),
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: const Text(
            'Approve Refund',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      if (c.canApproveOrDeny)
        OutlinedButton(
          onPressed: _busy ? null : () => _deny(c),
          style: OutlinedButton.styleFrom(
            foregroundColor: _red,
            side: BorderSide(color: _red.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: const Text(
            'Deny Refund',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      if (c.canResolve)
        ElevatedButton(
          onPressed: _busy ? null : () => _resolve(c),
          style: ElevatedButton.styleFrom(
            backgroundColor: AdminColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: const Text(
            'Mark Resolved',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      if (c.canOverride)
        OutlinedButton(
          onPressed: _busy ? null : () => _override(c),
          style: OutlinedButton.styleFrom(
            foregroundColor: AdminColors.primary,
            backgroundColor: AdminColors.selected,
            side: BorderSide(
              color: AdminColors.primary.withValues(alpha: 0.3),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: const Text(
            'Override Decision',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
    ];
    if (buttons.isEmpty) {
      return [
        Text(
          c.status.isClosed
              ? 'This case is closed. No further action is needed.'
              : 'No refund applies to this case.',
          style: const TextStyle(color: AdminColors.textMuted, fontSize: 12),
        ),
      ];
    }
    return [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        buttons[i],
      ],
    ];
  }

  String _formatNotice(double hours) {
    if (hours < 0) return 'after the start time';
    if (hours < 1) return '${(hours * 60).round()} minutes';
    final whole = hours.floor();
    return whole == 1 ? '1 hour' : '$whole hours';
  }
}

// ─────────────────────────────────────────────
//  Dialogs
// ─────────────────────────────────────────────

/// Asks for a required written reason; returns it, or null if cancelled.
class _ReasonDialog extends StatefulWidget {
  final String title;
  final String label;
  final String confirmLabel;
  final Color confirmColor;
  const _ReasonDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().length < 5)
                ? 'Please give a short reason (at least 5 characters).'
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: widget.confirmColor),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Lets the admin set an alternative refund percentage with a reason.
class _OverrideDialog extends StatefulWidget {
  final RefundCase refundCase;
  const _OverrideDialog({required this.refundCase});

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _percent = TextEditingController(
    text: widget.refundCase.refundPercentage?.toStringAsFixed(0) ?? '',
  );
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _percent.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _percent.dispose();
    _reason.dispose();
    super.dispose();
  }

  double? get _parsed => double.tryParse(_percent.text.trim());

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, (_parsed!, _reason.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = widget.refundCase.amountPaid ?? 0;
    final pct = _parsed;
    final preview = pct == null || pct < 0 || pct > 100
        ? null
        : formatRand(paid * pct / 100);
    return AlertDialog(
      title: const Text('Override refund decision'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Amount paid: ${formatRand(paid)}. Use this for exceptional '
                'circumstances; the override is recorded against your account.',
                style: const TextStyle(
                  color: AdminColors.textMuted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _percent,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Refund percentage',
                  suffixText: '%',
                  helperText: preview == null ? null : 'Refund: $preview',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null) return 'Enter a number from 0 to 100.';
                  if (n < 0 || n > 100) return 'Must be between 0 and 100.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Reason for the override',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().length < 5)
                    ? 'Please give a short reason (at least 5 characters).'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Override')),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Case row
// ─────────────────────────────────────────────

class _CaseRow extends StatelessWidget {
  final RefundCase refundCase;
  final bool selected;
  final VoidCallback onTap;
  final bool isLast;

  const _CaseRow({
    required this.refundCase,
    required this.selected,
    required this.onTap,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final c = refundCase;
    final amount = c.type == CaseType.cancellation
        ? c.refundAmount
        : c.amountPaid;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AdminColors.selected : Colors.transparent,
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: AdminColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                c.reference,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AdminColors.textMuted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.studentName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminColors.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '↔ ${c.tutorName}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: c.type == CaseType.report
                    ? const _Pill(
                        label: 'User Report',
                        bg: _purpleBg,
                        fg: _purple,
                      )
                    : const _Pill(
                        label: 'Cancellation',
                        bg: _blueBg,
                        fg: AdminColors.primary,
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                amount == null ? '—' : formatRand(amount),
                style: const TextStyle(
                  color: AdminColors.textDark,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StatusBadge(c.status),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _SmallButton(
                  label: c.status.isClosed ? 'View' : 'Review',
                  highlighted: c.needsAction,
                  onTap: onTap,
                ),
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

/// Centred icon, title, message and optional action, used for the empty and
/// error states.
class _StateMessage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String message;
  final Widget? action;

  const _StateMessage({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.message,
    this.action,
  });

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

class _MinWidthScroll extends StatelessWidget {
  final double minWidth;
  final Widget child;
  const _MinWidthScroll({required this.minWidth, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < minWidth
            ? minWidth
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: width, child: child),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({
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

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AdminColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color? valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.caption,
    this.valueColor,
  });

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

class _Pill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Pill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final CaseStatus status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      CaseStatus.pending || CaseStatus.underReview => (_amberBg, _amber),
      CaseStatus.open => (_redBg, _red),
      CaseStatus.approved || CaseStatus.resolved => (_greenBg, _green),
      CaseStatus.denied => (_greyBg, _grey),
    };
    return _Pill(label: status.label, bg: bg, fg: fg);
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final bool highlighted;
  final VoidCallback onTap;
  const _SmallButton({
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: highlighted ? AdminColors.primary : Colors.white,
          border: Border.all(
            color: highlighted ? AdminColors.primary : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: highlighted ? Colors.white : AdminColors.textDark,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PartyRow extends StatelessWidget {
  final String name;
  final String role;
  const _PartyRow({required this.name, required this.role});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surface2,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: _blueBg,
            child: Text(
              _initials,
              style: const TextStyle(
                color: AdminColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdminColors.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  role,
                  style: const TextStyle(
                    color: AdminColors.textMuted,
                    fontSize: 11,
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AdminColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AdminColors.textDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
    return Text(
      text,
      style: const TextStyle(
        color: AdminColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}
