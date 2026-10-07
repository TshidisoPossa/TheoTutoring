import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/financial_models.dart';

import 'Services/financial_services.dart';
import 'Services/financial_report_pdf.dart';

import 'admin_shell.dart';

class AdminFinancialScreen extends StatefulWidget {
  const AdminFinancialScreen({super.key});

  @override
  State<AdminFinancialScreen> createState() => _AdminFinancialScreenState();
}

class _AdminFinancialScreenState extends State<AdminFinancialScreen> {
  final _service = AdminFinancialService();

  late DateTimeRange _range;
  FinancialOverview? _overview;
  List<SubjectRevenue> _subjects = [];
  String _period = 'monthly';
  String _search = '';
  String _statusFilter = 'all';
  bool _loading = true;
  bool _chartLoading = false;
  bool _exporting = false;
  bool _processing = false;
  String? _error;
  String? _chartError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
    _load();
  }

  String get _rangeLabel {
    final sameYear = _range.start.year == _range.end.year;
    final f = DateFormat(sameYear ? 'MMM d' : 'MMM d, yyyy');
    return '${f.format(_range.start)} - ${f.format(_range.end)}';
  }

  String get _quarterLabel =>
      'Q${(_range.start.month - 1) ~/ 3 + 1} ${_range.start.year}';

  List<TransactionItem> get _filteredTransactions {
    final q = _search.trim().toLowerCase();
    return (_overview?.transactions ?? []).where((t) {
      if (_statusFilter != 'all' && t.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return t.id.toLowerCase().contains(q) ||
          t.studentName.toLowerCase().contains(q) ||
          t.tutorName.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _service.fetchOverview(_range.start, _range.end),
        _service.fetchRevenueBySubject(_period),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as FinancialOverview;
        _subjects = results[1] as List<SubjectRevenue>;
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
    final period = _period;
    setState(() {
      _chartLoading = true;
      _chartError = null;
    });
    try {
      final subjects = await _service.fetchRevenueBySubject(period);
      if (!mounted || _period != period) return;
      setState(() {
        _subjects = subjects;
        _chartLoading = false;
      });
    } catch (e) {
      if (!mounted || _period != period) return;
      setState(() {
        _chartError = e.toString();
        _chartLoading = false;
      });
    }
  }

  void _changePeriod(String period) {
    if (period == _period) return;
    _period = period;
    _loadChart();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  Future<void> _export() async {
    final overview = _overview;
    if (overview == null) return;
    setState(() => _exporting = true);
    try {
      await FinancialReportPdf.export(
        overview: overview,
        subjects: _subjects,
        rangeLabel: _rangeLabel,
        periodLabel: _period == 'monthly' ? 'Monthly' : 'Quarterly',
      );
    } catch (e) {
      _snack('Could not export report: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _processBatch() async {
    final overview = _overview;
    if (overview == null || overview.payoutReadyCount == 0) return;
    final n = overview.payoutReadyCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Process payout batch'),
        content: Text('Process $n ready ${n == 1 ? 'payout' : 'payouts'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Process'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _processing = true);
    try {
      await _service.processBatch();
      if (!mounted) return;
      _snack('Payout batch processed.');
      await _load();
    } catch (e) {
      _snack('Could not process batch: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.payouts,
      adminName: _overview?.adminName,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final o = _overview;
    if (_error != null || o == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load financial data.'),
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

    final margin = o.grossRevenue > 0
        ? o.netProfit / o.grossRevenue * 100
        : 0.0;
    final marginText = margin.toStringAsFixed(
      margin == margin.roundToDouble() ? 0 : 1,
    );

    final cards = [
      _SummaryCard(
        title: 'Total Gross Revenue',
        value: formatRandFull(o.grossRevenue),
        subtitle: o.previousGrossRevenue == null
            ? 'For the selected period'
            : 'vs ${formatRandFull(o.previousGrossRevenue!)} previous period',
        watermark: Icons.account_balance_outlined,
        badge: _changePill(o.grossRevenueChange),
      ),
      _SummaryCard(
        title: 'Net Profit (Post-Payout)',
        value: formatRandFull(o.netProfit),
        subtitle: '$marginText% aggregate margin',
        watermark: Icons.savings_outlined,
        badge: _changePill(o.netProfitChange),
      ),
      _SummaryCard(
        title: 'Pending Payouts',
        value: formatRandFull(o.pendingPayouts),
        subtitle:
            'Across ${o.pendingPayoutTutors} active ${o.pendingPayoutTutors == 1 ? 'tutor' : 'tutors'}',
        watermark: Icons.hourglass_empty,
        badge: _duePill(o.payoutDueInDays),
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                runSpacing: 16,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'FINANCIAL OVERVIEW  /  ',
                              style: TextStyle(color: AdminColors.textMuted),
                            ),
                            TextSpan(
                              text: _quarterLabel,
                              style: const TextStyle(
                                color: AdminColors.textDark,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 10, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Revenue & Payouts',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _exporting ? null : _export,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE5E7EB),
                          foregroundColor: AdminColors.textDark,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
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
                                ),
                              )
                            : const Icon(Icons.download, size: 16),
                        label: const Text('Export Report'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _pickRange,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                        ),
                        label: Text(_rangeLabel),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 800
                      ? 3
                      : constraints.maxWidth >= 520
                      ? 2
                      : 1;
                  const gap = 24.0;
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
                  final chart = _RevenueCard(
                    subjects: _subjects,
                    period: _period,
                    loading: _chartLoading,
                    error: _chartError,
                    onPeriodChanged: _changePeriod,
                    onRetry: _loadChart,
                  );
                  final queue = _PayoutQueueCard(
                    items: o.payoutQueue,
                    readyCount: o.payoutReadyCount,
                    processing: _processing,
                    onProcess: _processBatch,
                  );
                  if (constraints.maxWidth >= 900) {
                    return SizedBox(
                      height: 420,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 2, child: chart),
                          const SizedBox(width: 24),
                          Expanded(child: queue),
                        ],
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 380, child: chart),
                      const SizedBox(height: 24),
                      SizedBox(height: 420, child: queue),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _TransactionsCard(
                transactions: _filteredTransactions,
                statusFilter: _statusFilter,
                onSearchChanged: (v) => setState(() => _search = v),
                onStatusChanged: (v) => setState(() => _statusFilter = v),
                onAction: (id) => Navigator.pushNamed(
                  context,
                  AdminRoutes.transactionDetail,
                  arguments: id,
                ),
                onViewAll: () =>
                    Navigator.pushNamed(context, AdminRoutes.transactions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- shared

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.bg,
    required this.fg,
    this.icon,
  });
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

Widget? _changePill(double? change) {
  if (change == null) return null;
  final up = change >= 0;
  return _Pill(
    text: signedPercent(change),
    bg: up ? const Color(0xFFD9F5E0) : const Color(0xFFFDE2E2),
    fg: up ? const Color(0xFF1B7F3A) : const Color(0xFFC62828),
    icon: up ? Icons.trending_up : Icons.trending_down,
  );
}

Widget? _duePill(int? days) {
  if (days == null) return null;
  final text = days < 0
      ? 'Overdue'
      : days == 0
      ? 'Due today'
      : 'Due in $days ${days == 1 ? 'day' : 'days'}';
  return _Pill(
    text: text,
    bg: const Color(0xFFFFF1C7),
    fg: const Color(0xFF8A5A00),
    icon: Icons.schedule,
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.photoUrl,
    required this.size,
    required this.radius,
  });
  final String initials;
  final String? photoUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF0F4),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.32,
          fontWeight: FontWeight.w600,
          color: AdminColors.textMuted,
        ),
      ),
    );
    final url = photoUrl;
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: AdminColors.border),
);

// ---------------------------------------------------------------- summary cards

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.watermark,
    this.badge,
  });
  final String title;
  final String value;
  final String subtitle;
  final IconData watermark;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Stack(
        children: [
          Positioned(
            right: -4,
            top: 0,
            child: Icon(watermark, size: 64, color: const Color(0x140A3FA6)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.textDark,
                      ),
                    ),
                  ),
                  if (badge != null) badge!,
                ],
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- revenue by subject

const _barColors = [
  [Color(0xFFCBD7EC), Color(0xFF0A3FA6)],
  [Color(0xFFCDE6E3), Color(0xFF00806E)],
  [Color(0xFFDDD3E8), Color(0xFF5B2D91)],
  [Color(0xFFCDDFE3), Color(0xFF00697A)],
];

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.subjects,
    required this.period,
    required this.loading,
    required this.error,
    required this.onPeriodChanged,
    required this.onRetry,
  });
  final List<SubjectRevenue> subjects;
  final String period;
  final bool loading;
  final String? error;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onRetry;

  Widget _body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load revenue by subject.'),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (subjects.isEmpty) {
      return const Center(child: Text('No revenue data for this period yet.'));
    }
    return _SubjectBars(subjects: subjects);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revenue by Subject',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.textDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Gross volume per academic category',
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _PeriodButton(
                label: 'Monthly',
                value: 'monthly',
                current: period,
                onTap: onPeriodChanged,
              ),
              const SizedBox(width: 4),
              _PeriodButton(
                label: 'Quarterly',
                value: 'quarterly',
                current: period,
                onTap: onPeriodChanged,
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

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
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
      borderRadius: BorderRadius.circular(4),
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AdminColors.accent : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AdminColors.textDark,
          ),
        ),
      ),
    );
  }
}

class _SubjectBars extends StatelessWidget {
  const _SubjectBars({required this.subjects});
  final List<SubjectRevenue> subjects;

  @override
  Widget build(BuildContext context) {
    final maxRevenue = subjects.map((s) => s.revenue).reduce(max);
    final total = subjects.fold<double>(0, (sum, s) => sum + s.revenue);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < subjects.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Tooltip(
                      message:
                          '${subjects[i].subject}\n${formatRandFull(subjects[i].revenue)}'
                          '${total > 0 ? ' (${(subjects[i].revenue / total * 100).toStringAsFixed(1)}%)' : ''}',
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ColoredBox(
                                color: _barColors[i % _barColors.length][0],
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                widthFactor: 1,
                                heightFactor: maxRevenue > 0
                                    ? subjects[i].revenue / maxRevenue
                                    : 0,
                                child: ColoredBox(
                                  color: _barColors[i % _barColors.length][1],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: AdminColors.border),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final s in subjects)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    s.subject,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdminColors.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- payout queue

class _PayoutQueueCard extends StatelessWidget {
  const _PayoutQueueCard({
    required this.items,
    required this.readyCount,
    required this.processing,
    required this.onProcess,
  });
  final List<PayoutItem> items;
  final int readyCount;
  final bool processing;
  final VoidCallback onProcess;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Payout Queue',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.textDark,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'No payouts in the queue.',
                      style: TextStyle(color: AdminColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 20),
                    itemBuilder: (_, i) => _PayoutRow(item: items[i]),
                  ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: (readyCount == 0 || processing) ? null : onProcess,
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('Process Batch ($readyCount)'),
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.item});
  final PayoutItem item;

  @override
  Widget build(BuildContext context) {
    final ready = item.status == 'ready';
    final processing = item.status == 'processing';
    final statusColor = ready
        ? const Color(0xFF1B7F3A)
        : processing
        ? const Color(0xFF8A5A00)
        : AdminColors.textMuted;
    final statusText = item.status.isEmpty
        ? ''
        : item.status[0].toUpperCase() + item.status.substring(1);

    return Row(
      children: [
        _Avatar(
          initials: item.initials,
          photoUrl: item.photoUrl,
          size: 40,
          radius: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.tutorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.textDark,
                ),
              ),
              Text(
                item.subject,
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
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatRandFull(item.amount),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminColors.textDark,
              ),
            ),
            Text(
              statusText,
              style: TextStyle(fontSize: 11, color: statusColor),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- transactions

class _TxStyle {
  const _TxStyle(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;

  static _TxStyle of(String status) {
    switch (status) {
      case 'settled':
        return const _TxStyle('Settled', Color(0xFFD9F5E0), Color(0xFF1B7F3A));
      case 'pending':
        return const _TxStyle('Pending', Color(0xFFFFF1C7), Color(0xFF8A5A00));
      case 'failed':
        return const _TxStyle('Failed', Color(0xFFFDE2E2), Color(0xFFC62828));
      default:
        return _TxStyle(
          status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1),
          const Color(0xFFE8EAEE),
          const Color(0xFF4B5563),
        );
    }
  }
}

class _TransactionsCard extends StatelessWidget {
  const _TransactionsCard({
    required this.transactions,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onAction,
    required this.onViewAll,
  });
  final List<TransactionItem> transactions;
  final String statusFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onAction;
  final VoidCallback onViewAll;

  static const _headerStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: AdminColors.textMuted,
  );

  Widget _cell(Widget child, {Alignment align = Alignment.centerLeft}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Align(alignment: align, child: child),
      );

  Widget _headerCell(String text, {Alignment align = Alignment.centerLeft}) =>
      _cell(Text(text, style: _headerStyle), align: align);

  TableRow _row(TransactionItem t) {
    final style = _TxStyle.of(t.status);
    return TableRow(
      children: [
        _cell(
          Text(
            t.id,
            style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
          ),
        ),
        _cell(
          Text(
            DateFormat('MMM d, HH:mm').format(t.date.toLocal()),
            style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
          ),
        ),
        _cell(
          Row(
            children: [
              _Avatar(
                initials: t.studentInitials,
                photoUrl: t.studentPhotoUrl,
                size: 24,
                radius: 12,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  t.studentName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminColors.textDark,
                  ),
                ),
              ),
            ],
          ),
        ),
        _cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.tutorName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textDark,
                ),
              ),
              Text(
                t.subject,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        _cell(
          Text(
            formatRandFull(t.amount),
            style: const TextStyle(fontSize: 12, color: AdminColors.textDark),
          ),
          align: Alignment.centerRight,
        ),
        _cell(_Pill(text: style.label, bg: style.bg, fg: style.fg)),
        _cell(
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.receipt_long_outlined, size: 20),
            color: AdminColors.textMuted,
            onPressed: () => onAction(t.id),
          ),
          align: Alignment.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filterLabel = statusFilter == 'all'
        ? 'Status'
        : statusFilter[0].toUpperCase() + statusFilter.substring(1);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              children: [
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.textDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Student payments and platform fees',
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: TextField(
                        onChanged: onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search ID or name...',
                          hintStyle: const TextStyle(fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: onStatusChanged,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'all', child: Text('All')),
                        PopupMenuItem(value: 'settled', child: Text('Settled')),
                        PopupMenuItem(value: 'pending', child: Text('Pending')),
                        PopupMenuItem(value: 'failed', child: Text('Failed')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.filter_list, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              filterLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No transactions found.',
                  style: TextStyle(color: AdminColors.textMuted),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = max(constraints.maxWidth, 820.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.4),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.6),
                        3: FlexColumnWidth(1.6),
                        4: FlexColumnWidth(1.1),
                        5: FlexColumnWidth(1),
                        6: FixedColumnWidth(72),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: AdminColors.border),
                      ),
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(
                            color: Color(0xFFF3F4F6),
                          ),
                          children: [
                            _headerCell('TRANSACTION ID'),
                            _headerCell('DATE'),
                            _headerCell('STUDENT'),
                            _headerCell('TUTOR / SUBJECT'),
                            _headerCell('AMOUNT', align: Alignment.centerRight),
                            _headerCell('STATUS'),
                            _headerCell('ACTION', align: Alignment.center),
                          ],
                        ),
                        for (final t in transactions) _row(t),
                      ],
                    ),
                  ),
                );
              },
            ),
          InkWell(
            onTap: onViewAll,
            child: Container(
              color: const Color(0xFFF3F4F6),
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: const Text(
                'View All Transactions',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
