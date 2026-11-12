// Reports: what tutors and students have reported (documentation: the admin
// can "view reviews and user reports"). A filterable, paginated, read-only
// list; the supplied Reports API has no resolve or other actions.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'Services/admin_reports_service.dart';
import 'admin_shell.dart';
import 'models/admin_report_models.dart';

const _green = Color(0xFF1B7F3A);
const _greenBg = Color(0xFFD9F5E0);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFDEBD0);
const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDE2E2);
const _greyBg = Color(0xFFE8EAEE);

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

String _date(String? iso) {
  final parsed = iso == null ? null : DateTime.tryParse(iso);
  return parsed == null
      ? (iso ?? 'Unknown date')
      : DateFormat('d MMM yyyy, HH:mm').format(parsed);
}

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key, this.service, this.pageSize = 20});

  final AdminReportsService? service;
  final int pageSize;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  late final AdminReportsService _service;
  late final bool _ownsService;

  String _status = 'all';
  String? _category;
  int _page = 1;
  AdminReportsPage? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminReportsService();
    _ownsService = widget.service == null;
    _load();
  }

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchReports(
        status: _status,
        category: _category,
        page: _page,
        pageSize: widget.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setFilters({String? status, String? Function()? category}) {
    setState(() {
      _status = status ?? _status;
      if (category != null) _category = category();
      _page = 1;
    });
    _load();
  }

  void _goToPage(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AdminShell(
      currentRoute: AdminRoutes.reports,
      adminName: data?.adminName,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                const SizedBox(height: 20),
                if (_loading && data == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null && data == null)
                  _Card(
                    child: _StateMessage(
                      icon: Icons.error_outline,
                      title: 'Could not load reports.',
                      message: _msg(_error!),
                      action: ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  )
                else ...[
                  if (_error != null) ...[
                    _InlineError(
                      message: 'Could not refresh reports: ${_msg(_error!)}',
                      onRetry: _load,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildFilters(),
                  const SizedBox(height: 12),
                  _buildList(data!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final (label, key) in adminReportStatuses)
        _FilterChip(
          label: label,
          active: _status == key,
          onTap: () => _setFilters(status: key),
        ),
      const SizedBox(width: 8),
      Tooltip(
        message: 'Category',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _category,
              isDense: true,
              style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
              padding: const EdgeInsets.symmetric(vertical: 10),
              items: [
                const DropdownMenuItem(child: Text('All categories')),
                for (final c in adminReportCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) {
                if (v != _category) _setFilters(category: () => v);
              },
            ),
          ),
        ),
      ),
      if (_loading)
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      else
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
    ],
  );

  Widget _buildList(AdminReportsPage data) {
    if (data.reports.isEmpty) {
      final filtered = _status != 'all' || _category != null;
      return _Card(
        child: _StateMessage(
          icon: Icons.flag_outlined,
          title: filtered
              ? 'No reports match these filters.'
              : 'No reports yet',
          message: filtered
              ? 'Try a different status or category.'
              : 'Reports sent by tutors and students will appear here.',
        ),
      );
    }
    final from = (data.page - 1) * data.pageSize + 1;
    final to = from + data.reports.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in data.reports) ...[
          _ReportCard(report: r),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                'Showing $from-$to of ${data.total}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            ),
            _Pagination(
              page: data.page,
              pageCount: data.pageCount,
              onPage: _loading ? null : _goToPage,
            ),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Reports',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AdminColors.textDark,
        ),
      ),
      SizedBox(height: 4),
      Text(
        'Problems reported by tutors and students.',
        style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
    ),
    child: child,
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final AdminReport report;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (report.status.toLowerCase()) {
      'resolved' => (_green, _greenBg),
      'under review' => (_amber, _amberBg),
      'open' => (_red, _redBg),
      _ => (AdminColors.textDark, _greyBg),
    };
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Pill(
                  label: report.status.isEmpty ? 'Unknown' : report.status,
                  color: fg,
                  background: bg,
                ),
                _Pill(
                  label: report.category ?? 'Uncategorised',
                  color: AdminColors.textDark,
                  background: _greyBg,
                ),
                Text(
                  _date(report.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
                Text(
                  report.bookingId == null
                      ? 'No booking'
                      : 'Booking #${report.bookingId}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              report.description.isEmpty
                  ? 'No description provided.'
                  : report.description,
              style: const TextStyle(fontSize: 14, color: AdminColors.textDark),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 32,
              runSpacing: 8,
              children: [
                _PersonBlock(
                  heading: 'Reported by',
                  person: report.reporter,
                  fallback: 'Unknown reporter',
                ),
                _PersonBlock(
                  heading: 'About',
                  person: report.reportedUser,
                  fallback: 'No user named',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonBlock extends StatelessWidget {
  const _PersonBlock({
    required this.heading,
    required this.person,
    required this.fallback,
  });

  final String heading;
  final AdminReportPerson? person;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final details = [
      if (p?.role != null) p!.role!,
      if (p?.email != null) p!.email!,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(fontSize: 11, color: AdminColors.textMuted),
        ),
        Text(
          p?.name ?? fallback,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AdminColors.textDark,
          ),
        ),
        if (details.isNotEmpty)
          Text(
            details,
            style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
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
  Widget build(BuildContext context) => Material(
    color: active ? AdminColors.primary : _greyBg,
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AdminColors.textDark,
          ),
        ),
      ),
    ),
  );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: AdminColors.textMuted),
        const SizedBox(height: 12),
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
          style: const TextStyle(fontSize: 13, color: AdminColors.textMuted),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: _redBg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: _red, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 13, color: _red),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.pageCount,
    required this.onPage,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, int target, String tooltip) => IconButton(
      tooltip: tooltip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      onPressed: onPage == null || target < 1 || target > pageCount
          ? null
          : () => onPage!(target),
      icon: Icon(icon),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.chevron_left, page - 1, 'Previous page'),
        Text(
          'Page $page of $pageCount',
          style: const TextStyle(fontSize: 12, color: AdminColors.textDark),
        ),
        arrow(Icons.chevron_right, page + 1, 'Next page'),
      ],
    );
  }
}
