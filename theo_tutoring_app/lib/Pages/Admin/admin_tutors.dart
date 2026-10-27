// Tutors (Tutor Roster): summary figures, status filter and search, a
// paginated roster, and a per-tutor dialog to view details and change the
// account status (Active / Suspended / Removed). Built like the Students
// page; tutors still in review are approved on the Applications page.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'Services/admin_tutors_service.dart';
import 'admin_shell.dart';
import 'models/admin_tutor_models.dart';

const _surface2 = Color(0xFFF8F9FB);
const _green = Color(0xFF1B7F3A);
const _greenBg = Color(0xFFD9F5E0);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFDEBD0);
const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDE2E2);
const _suspendedRowBg = Color(0xFFFDF4F4);
const _greyBg = Color(0xFFE8EAEE);

final _count = NumberFormat('#,##0');

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

class AdminTutorsScreen extends StatefulWidget {
  const AdminTutorsScreen({super.key, this.service, this.pageSize = 10});

  final AdminTutorsService? service;
  final int pageSize;

  @override
  State<AdminTutorsScreen> createState() => _AdminTutorsScreenState();
}

class _AdminTutorsScreenState extends State<AdminTutorsScreen> {
  static const _filters = <(String, String)>[
    ('All Tutors', 'all'),
    ('Active', 'active'),
    ('Suspended', 'suspended'),
    ('Pending', 'pending'),
  ];

  late final AdminTutorsService _service;
  late final bool _ownsService;
  final _search = TextEditingController();
  Timer? _searchDebounce;

  String _status = 'all';
  int _page = 1;
  AdminTutorsPage? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminTutorsService();
    _ownsService = widget.service == null;
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchTutors(
        status: _status,
        search: _search.text,
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

  void _setStatus(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _page = 1;
    });
    _load();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _page = 1);
      _load();
    });
  }

  void _goToPage(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    _load();
  }

  // Add Tutor / Export CSV are not built yet.
  void _notAvailableYet(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature is not available yet.')));
  }

  Future<void> _openTutor(AdminTutor tutor) async {
    final updated = await showDialog<AdminTutor>(
      context: context,
      builder: (_) => _TutorDialog(tutor: tutor, service: _service),
    );
    if (updated == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${updated.name} is now ${updated.statusLabel}.')),
    );
    _load();
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AdminShell(
      currentRoute: AdminRoutes.tutors,
      adminName: data?.adminName,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(onUnavailable: _notAvailableYet),
                const SizedBox(height: 20),
                if (_loading && data == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null && data == null)
                  _Card(
                    child: _error is AdminTutorsUnavailable
                        ? const _StateMessage(
                            icon: Icons.cloud_off_outlined,
                            title: 'Tutor management is not available yet.',
                            message:
                                'This server does not provide the Admin '
                                'tutor endpoints yet, so no tutors can be '
                                'shown.',
                          )
                        : _StateMessage(
                            icon: Icons.error_outline,
                            title: 'Could not load tutors.',
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
                      message: 'Could not refresh tutors: ${_msg(_error!)}',
                      onRetry: _load,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildTopRow(data!.summary),
                  const SizedBox(height: 20),
                  _buildRoster(data),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopRow(TutorSummary s) {
    final stats = [
      _StatCard(
        label: 'Total Tutors',
        value: s.totalTutors == null ? null : _count.format(s.totalTutors),
      ),
      _StatCard(
        label: 'Active This Month',
        value: s.activeThisMonth == null
            ? null
            : _count.format(s.activeThisMonth),
      ),
      _StatCard(
        label: 'Avg Lessons/Tutor',
        value: s.avgLessonsPerTutor?.toStringAsFixed(1),
      ),
      _StatCard(
        label: 'Suspended Accounts',
        value: s.suspendedAccounts == null
            ? null
            : _count.format(s.suspendedAccounts),
        valueColor: (s.suspendedAccounts ?? 0) > 0 ? _red : null,
      ),
    ];
    final filter = _FilterCard(
      filters: _filters,
      selected: _status,
      onSelected: _setStatus,
      search: _search,
      onSearchChanged: _onSearchChanged,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        if (constraints.maxWidth >= 1000) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final card in stats) ...[
                  Expanded(child: card),
                  const SizedBox(width: gap),
                ],
                SizedBox(width: 260, child: filter),
              ],
            ),
          );
        }
        final perRow = constraints.maxWidth >= 520 ? 2 : 1;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in stats) SizedBox(width: width, child: card),
              ],
            ),
            const SizedBox(height: gap),
            filter,
          ],
        );
      },
    );
  }

  Widget _buildRoster(AdminTutorsPage data) {
    final tutors = data.tutors;
    final maxLessons = tutors.fold<int>(
      0,
      (max, s) => s.totalLessons > max ? s.totalLessons : max,
    );
    final first = data.total == 0 ? 0 : (data.page - 1) * data.pageSize + 1;
    final last = first == 0 ? 0 : first + tutors.length - 1;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MinWidthScroll(
            minWidth: 860,
            child: Column(
              children: [
                Container(
                  color: _surface2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 3, child: _TableHeader('Tutor Name')),
                      Expanded(flex: 3, child: _TableHeader('Contact Info')),
                      Expanded(flex: 2, child: _TableHeader('Total Lessons')),
                      Expanded(flex: 2, child: _TableHeader('Joined Date')),
                      Expanded(flex: 2, child: _TableHeader('Status')),
                      SizedBox(
                        width: 64,
                        child: _TableHeader('Actions', alignEnd: true),
                      ),
                    ],
                  ),
                ),
                for (final tutor in tutors) ...[
                  const Divider(height: 1, color: AdminColors.border),
                  _TutorRow(
                    tutor: tutor,
                    maxLessons: maxLessons,
                    onActions: () => _openTutor(tutor),
                  ),
                ],
              ],
            ),
          ),
          if (tutors.isEmpty) ...[
            const Divider(height: 1, color: AdminColors.border),
            _status == 'all' && _search.text.trim().isEmpty
                ? const _StateMessage(
                    icon: Icons.school_outlined,
                    title: 'No tutors yet',
                    message:
                        'Tutors appear here once they register on '
                        'TheoTutoring.',
                  )
                : const _StateMessage(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'No tutors match',
                    message: 'Try another status or search term.',
                  ),
          ],
          const Divider(height: 1, color: AdminColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'Showing $first–$last of ${_count.format(data.total)} '
                  '${data.total == 1 ? 'tutor' : 'tutors'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
                _Pagination(
                  page: data.page,
                  pageCount: data.pageCount,
                  onPage: _loading ? null : _goToPage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ widgets

class _Header extends StatelessWidget {
  const _Header({required this.onUnavailable});

  final ValueChanged<String> onUnavailable;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 16,
    runSpacing: 12,
    children: [
      const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tutor Roster',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AdminColors.textDark,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Manage and monitor tutor accounts, lesson history, and system '
            'access.',
            style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
          ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: () => onUnavailable('Adding a tutor'),
            style: FilledButton.styleFrom(
              backgroundColor: AdminColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Tutor'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => onUnavailable('Export to CSV'),
            style: FilledButton.styleFrom(
              backgroundColor: _greyBg,
              foregroundColor: AdminColors.textDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Export CSV'),
          ),
        ],
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
    ),
    child: child,
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.valueColor});

  final String label;
  final String? value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 2,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: AdminColors.textMuted,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          value ?? '—',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AdminColors.textDark,
          ),
        ),
      ],
    ),
  );
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.filters,
    required this.selected,
    required this.onSelected,
    required this.search,
    required this.onSearchChanged,
  });

  final List<(String, String)> filters;
  final String selected;
  final ValueChanged<String> onSelected;
  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'FILTER BY STATUS',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: AdminColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, value) in filters)
              _FilterChip(
                label: label,
                active: value == selected,
                onTap: () => onSelected(value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: search,
          onChanged: onSearchChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search by name or email...',
            hintStyle: const TextStyle(fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 18),
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AdminColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AdminColors.border),
            ),
          ),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AdminColors.textDark,
          ),
        ),
      ),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.label, {this.alignEnd = false});
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    textAlign: alignEnd ? TextAlign.end : TextAlign.start,
    style: const TextStyle(
      fontSize: 11,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w600,
      color: AdminColors.textMuted,
    ),
  );
}

class _TutorAvatar extends StatelessWidget {
  const _TutorAvatar({required this.tutor, this.radius = 18});
  final AdminTutor tutor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = tutor.photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AdminColors.selected,
      foregroundImage: photo == null ? null : NetworkImage(photo),
      onForegroundImageError: photo == null ? null : (_, _) {},
      child: Text(
        tutor.initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w700,
          color: AdminColors.primary,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.tutor});
  final AdminTutor tutor;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = switch (tutor.status) {
      'Active' => (_green, _greenBg, Icons.circle),
      'Suspended' => (_red, _redBg, Icons.warning_amber_rounded),
      'Pending' => (_amber, _amberBg, Icons.circle),
      _ => (AdminColors.textMuted, _greyBg, Icons.circle),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: icon == Icons.circle ? 6 : 12, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                tutor.statusLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorRow extends StatelessWidget {
  const _TutorRow({
    required this.tutor,
    required this.maxLessons,
    required this.onActions,
  });

  final AdminTutor tutor;
  final int maxLessons;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final muted = tutor.isSuspended || tutor.isRemoved;
    final textColor = muted ? AdminColors.textMuted : AdminColors.textDark;
    return Container(
      color: tutor.isSuspended ? _suspendedRowBg : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _TutorAvatar(tutor: tutor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tutor.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                          decoration: muted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(
                        'ID: ${tutor.reference}',
                        style: TextStyle(
                          fontSize: 11,
                          color: tutor.isSuspended
                              ? _red
                              : AdminColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tutor.email,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: textColor),
                ),
                Text(
                  tutor.phone ?? 'No phone number',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    _count.format(tutor.totalLessons),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: maxLessons == 0
                          ? 0
                          : tutor.totalLessons / maxLessons,
                      minHeight: 4,
                      backgroundColor: _greyBg,
                      color: muted ? AdminColors.textMuted : AdminColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              tutor.joinedLabel,
              style: TextStyle(fontSize: 13, color: textColor),
            ),
          ),
          Expanded(flex: 2, child: _StatusPill(tutor: tutor)),
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Tutor actions',
                icon: Icon(
                  Icons.more_vert,
                  color: tutor.isSuspended ? _red : AdminColors.textDark,
                ),
                onPressed: onActions,
              ),
            ),
          ),
        ],
      ),
    );
  }
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

  List<int?> get _pages {
    if (pageCount <= 5) return [for (var p = 1; p <= pageCount; p++) p];
    final window = {
      1,
      page - 1,
      page,
      page + 1,
      pageCount,
    }.where((p) => p >= 1 && p <= pageCount).toList()..sort();
    final result = <int?>[];
    for (final p in window) {
      if (result.isNotEmpty && p - result.last! > 1) result.add(null);
      result.add(p);
    }
    return result;
  }

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
        for (final p in _pages)
          if (p == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('…', style: TextStyle(color: AdminColors.textMuted)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: p == page ? AdminColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onPage == null ? null : () => onPage!(p),
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: Text(
                        '$p',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: p == page
                              ? Colors.white
                              : AdminColors.textDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        arrow(Icons.chevron_right, page + 1, 'Next page'),
      ],
    );
  }
}

class _TutorDialog extends StatefulWidget {
  const _TutorDialog({required this.tutor, required this.service});

  final AdminTutor tutor;
  final AdminTutorsService service;

  @override
  State<_TutorDialog> createState() => _TutorDialogState();
}

class _TutorDialogState extends State<_TutorDialog> {
  late TutorStatusChange? _selected = _current;
  bool _saving = false;
  String? _error;

  TutorStatusChange? get _current {
    for (final option in TutorStatusChange.values) {
      if (option.apiValue == widget.tutor.status) return option;
    }
    return null;
  }

  Future<void> _save() async {
    final target = _selected;
    if (target == null || target == _current) return;
    if (target == TutorStatusChange.removed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Remove ${widget.tutor.name}?'),
          content: const Text(
            'Removing sets this account\'s status to Deactivated. '
            'No records are deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _red),
              child: const Text('Remove tutor'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.service.updateStatus(
        widget.tutor.tutorId,
        target,
      );
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.tutor;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          _TutorAvatar(tutor: s, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'ID: ${s.reference}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoRow('Email', s.email),
              _InfoRow('Phone', s.phone ?? 'No phone number'),
              _InfoRow('Subjects', s.subjects ?? 'No subjects yet'),
              if (s.experience != null)
                _InfoRow('Experience', '${s.experience} years'),
              _InfoRow('Verification', s.verification ?? 'Unknown'),
              _InfoRow('Rating', s.ratingLabel),
              _InfoRow('Total lessons', _count.format(s.totalLessons)),
              _InfoRow('Joined', s.joinedLabel),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 130,
                      child: Text(
                        'Current status',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textMuted,
                        ),
                      ),
                    ),
                    Expanded(child: _StatusPill(tutor: s)),
                  ],
                ),
              ),
              const Divider(height: 28, color: AdminColors.border),
              if (s.isInReview)
                const Text(
                  'This tutor has not been approved yet. Approve or reject '
                  'them on the Applications page.',
                  style: TextStyle(fontSize: 13, color: AdminColors.textMuted),
                )
              else ...[
                const Text(
                  'Change status',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in TutorStatusChange.values)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: _selected == option,
                        showCheckmark: false,
                        selectedColor: option == TutorStatusChange.active
                            ? _greenBg
                            : _redBg,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _selected = option),
                      ),
                  ],
                ),
                if (_selected == TutorStatusChange.removed) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Removed sets the account status to Deactivated. No '
                    'records are deleted.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textMuted,
                    ),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: _red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _saving || _selected == null || _selected == _current
              ? null
              : _save,
          style: FilledButton.styleFrom(backgroundColor: AdminColors.primary),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save status'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
          ),
        ),
      ],
    ),
  );
}

class _MinWidthScroll extends StatelessWidget {
  const _MinWidthScroll({required this.minWidth, required this.child});
  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= minWidth) return child;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: minWidth, child: child),
      );
    },
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
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AdminColors.textMuted),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AdminColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.textMuted,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
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
            message,
            style: const TextStyle(fontSize: 13, color: _red),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
