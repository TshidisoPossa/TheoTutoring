import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/subject_model.dart';
import 'Services/admin_subject_service.dart';
import 'admin_shell.dart';

const _pageSize = 5;

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

class AdminSubjectsScreen extends StatefulWidget {
  const AdminSubjectsScreen({super.key});

  @override
  State<AdminSubjectsScreen> createState() => _AdminSubjectsScreenState();
}

class _AdminSubjectsScreenState extends State<AdminSubjectsScreen> {
  final _service = AdminSubjectsService();
  Timer? _debounce;

  SubjectSummary? _summary;
  List<Subject> _subjects = [];
  List<String> _categories = [];
  int _total = 0;
  int _page = 1;
  String? _category; // null = all categories
  String _status = 'all';
  String _query = '';
  final Set<String> _selected = {};

  bool _loading = true;
  bool _tableLoading = false;
  bool _busy = false;
  String? _error;
  String? _tableError;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ loading

  void _applyPage(SubjectPage page) {
    _subjects = page.subjects;
    _total = page.total;
    _categories = page.categories;
  }

  Future<SubjectPage> _fetchPage() => _service.fetchSubjects(
    page: _page,
    pageSize: _pageSize,
    category: _category,
    status: _status,
    query: _query,
  );

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _service.fetchSummary(),
        _fetchPage(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as SubjectSummary;
        _applyPage(results[1] as SubjectPage);
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

  Future<void> _loadTable() async {
    setState(() {
      _tableLoading = true;
      _tableError = null;
    });
    try {
      final page = await _fetchPage();
      if (!mounted) return;
      final pages = max(1, (page.total / _pageSize).ceil());
      if (_page > pages) {
        _page = pages;
        return _loadTable();
      }
      setState(() {
        _applyPage(page);
        _selected.retainAll(_subjects.map((s) => s.id));
        _tableLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tableError = _msg(e);
        _tableLoading = false;
      });
    }
  }

  Future<void> _loadSummaryQuiet() async {
    try {
      final summary = await _service.fetchSummary();
      if (mounted) setState(() => _summary = summary);
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadTable(), _loadSummaryQuiet()]);
  }

  // ------------------------------------------------------------ filters

  void _setCategory(String? category) {
    if (category == _category) return;
    _category = category;
    _page = 1;
    _selected.clear();
    _loadTable();
  }

  void _setStatus(String status) {
    if (status == _status) return;
    _status = status;
    _page = 1;
    _selected.clear();
    _loadTable();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value.trim();
      _page = 1;
      _selected.clear();
      _loadTable();
    });
  }

  void _goToPage(int page) {
    if (page == _page) return;
    _page = page;
    _selected.clear();
    _loadTable();
  }

  // ------------------------------------------------------------ actions

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      _snack(success);
      await _refreshAll();
      return true;
    } catch (e) {
      _snack(_msg(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openForm([Subject? subject]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SubjectFormDialog(
        categories: _categories,
        initial: subject,
        onSave: (input) => subject == null
            ? _service.createSubject(input)
            : _service.updateSubject(subject.id, input),
      ),
    );
    if (saved == true) {
      _snack(subject == null ? 'Subject added.' : 'Subject updated.');
      await _refreshAll();
    }
  }

  void _openDetails(Subject subject) {
    showDialog<void>(
      context: context,
      builder: (_) => _SubjectDetailsDialog(subject: subject),
    );
  }

  Future<bool> _confirmDelete(String title, String message) async {
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
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _delete(Subject subject) async {
    final ok = await _confirmDelete(
      'Delete subject',
      'Delete ${subject.name} (${subject.code})?',
    );
    if (!ok) return;
    await _run(() => _service.deleteSubject(subject.id), 'Subject deleted.');
  }

  Future<void> _toggleActive(Subject subject) => _run(
    () => _service.setActive(subject.id, !subject.isActive),
    subject.isActive ? 'Subject deactivated.' : 'Subject activated.',
  );

  Future<void> _bulk(String action) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final noun = ids.length == 1 ? 'subject' : 'subjects';
    if (action == 'delete') {
      final ok = await _confirmDelete(
        'Delete subjects',
        'Delete ${ids.length} selected $noun?',
      );
      if (!ok) return;
    }
    final done = action == 'delete'
        ? 'deleted'
        : action == 'activate'
        ? 'activated'
        : 'deactivated';
    final ok = await _run(
      () => _service.bulk(ids, action),
      '${ids.length} $noun $done.',
    );
    if (ok && mounted) setState(() => _selected.clear());
  }

  bool? get _allSelected {
    if (_subjects.isEmpty) return false;
    final n = _subjects.where((s) => _selected.contains(s.id)).length;
    if (n == 0) return false;
    if (n == _subjects.length) return true;
    return null;
  }

  void _toggleAll(bool? value) {
    setState(() {
      final ids = _subjects.map((s) => s.id);
      if (value == true) {
        _selected.addAll(ids);
      } else {
        _selected.removeAll(ids);
      }
    });
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.subjects,
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
              const Text('Could not load the subject directory.'),
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
              ElevatedButton(
                onPressed: _loadInitial,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final count = NumberFormat.decimalPattern();
    final cards = [
      _TrendCard(
        label: 'TOTAL SUBJECTS',
        value: count.format(summary.totalSubjects),
        change: summary.totalSubjectsChange,
        trend: summary.totalSubjectsTrend,
        icon: Icons.menu_book_outlined,
        iconBg: const Color(0xFFDCE8FF),
        iconFg: AdminColors.primary,
        lineColor: AdminColors.accent,
        fillColor: const Color(0x1A0052D4),
      ),
      _TrendCard(
        label: 'ACTIVE TUTORS',
        value: count.format(summary.activeTutors),
        change: summary.activeTutorsChange,
        trend: summary.activeTutorsTrend,
        icon: Icons.groups_outlined,
        iconBg: const Color(0xFFE5E7EB),
        iconFg: const Color(0xFF4B5563),
        lineColor: const Color(0xFF6B7280),
        fillColor: const Color(0x146B7280),
      ),
      _RatingCard(
        rating: summary.avgRating,
        target: summary.ratingTarget,
        satisfaction: summary.satisfaction,
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
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 12,
                children: [
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subject Directory',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.textDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage academic disciplines, faculty assignment, and track platform coverage.',
                        style: TextStyle(
                          fontSize: 14,
                          color: AdminColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : () => _openForm(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Subject'),
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
              _buildTableCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableCard() {
    final pages = max(1, (_total / _pageSize).ceil());
    final from = _total == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final to = min(_page * _pageSize, _total);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CategoryChip(
                      label: 'All Categories',
                      selected: _category == null,
                      onTap: () => _setCategory(null),
                    ),
                    for (final c in _categories)
                      _CategoryChip(
                        label: c,
                        selected: _category == c,
                        onTap: () => _setCategory(c),
                      ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 260,
                      child: TextField(
                        onChanged: _onSearch,
                        decoration: InputDecoration(
                          hintText: 'Search subjects, codes...',
                          hintStyle: const TextStyle(fontSize: 13),
                          suffixIcon: const Icon(Icons.search, size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF0F1F5),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Filter by status',
                      initialValue: _status,
                      onSelected: _setStatus,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'all',
                          child: Text('All statuses'),
                        ),
                        PopupMenuItem(value: 'active', child: Text('Active')),
                        PopupMenuItem(
                          value: 'inactive',
                          child: Text('Inactive'),
                        ),
                      ],
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F1F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.tune,
                          size: 20,
                          color: _status == 'all'
                              ? AdminColors.textDark
                              : AdminColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Container(
              color: AdminColors.selected,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : () => _bulk('activate'),
                    child: const Text('Activate'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _bulk('deactivate'),
                    child: const Text('Deactivate'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _bulk('delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                    ),
                    child: const Text('Delete'),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          if (_tableLoading || _busy)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          _buildTable(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              children: [
                Text(
                  _total == 0
                      ? 'No entries'
                      : 'Showing $from to $to of $_total entries',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _PageButton(
                      icon: Icons.chevron_left,
                      selected: false,
                      onTap: _page > 1 ? () => _goToPage(_page - 1) : null,
                    ),
                    for (final p in _pageItems(_page, pages))
                      if (p == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '...',
                            style: TextStyle(color: AdminColors.textMuted),
                          ),
                        )
                      else
                        _PageButton(
                          label: '$p',
                          selected: p == _page,
                          onTap: () => _goToPage(p),
                        ),
                    _PageButton(
                      icon: Icons.chevron_right,
                      selected: false,
                      onTap: _page < pages ? () => _goToPage(_page + 1) : null,
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

  static const _headerStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: AdminColors.textMuted,
  );

  Widget _cell(Widget child, {Alignment align = Alignment.centerLeft}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Align(alignment: align, child: child),
      );

  Widget _buildTable() {
    if (_tableError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load subjects.'),
              const SizedBox(height: 4),
              Text(
                _tableError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
              TextButton(onPressed: _loadTable, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_subjects.isEmpty && !_tableLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No subjects found.',
            style: TextStyle(color: AdminColors.textMuted),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = max(constraints.maxWidth, 900.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(48),
                1: FlexColumnWidth(3.4),
                2: FlexColumnWidth(1.5),
                3: FlexColumnWidth(1.2),
                4: FlexColumnWidth(1.1),
                5: FlexColumnWidth(1.2),
                6: FixedColumnWidth(150),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: const TableBorder(
                top: BorderSide(color: AdminColors.border),
                horizontalInside: BorderSide(color: AdminColors.border),
              ),
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFF8F9FB)),
                  children: [
                    _cell(
                      Checkbox(
                        tristate: true,
                        value: _allSelected,
                        onChanged: _toggleAll,
                      ),
                      align: Alignment.center,
                    ),
                    _cell(
                      const Text('SUBJECT NAME & CODE', style: _headerStyle),
                    ),
                    _cell(const Text('CATEGORY', style: _headerStyle)),
                    _cell(const Text('ACTIVE TUTORS', style: _headerStyle)),
                    _cell(const Text('AVG RATING', style: _headerStyle)),
                    _cell(const Text('STATUS', style: _headerStyle)),
                    _cell(
                      const Text('ACTIONS', style: _headerStyle),
                      align: Alignment.centerRight,
                    ),
                  ],
                ),
                for (final s in _subjects) _row(s),
              ],
            ),
          ),
        );
      },
    );
  }

  TableRow _row(Subject s) {
    final style = _CatStyle.of(s.category);
    final subtitle = s.department.isEmpty
        ? s.code
        : '${s.code} \u2022 Dept. ${s.department}';

    return TableRow(
      children: [
        _cell(
          Checkbox(
            value: _selected.contains(s.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(s.id);
              } else {
                _selected.remove(s.id);
              }
            }),
          ),
          align: Alignment.center,
        ),
        _cell(
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(style.icon, size: 20, color: style.fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textDark,
                      ),
                    ),
                    Text(
                      subtitle,
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
        ),
        _cell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF0F3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              s.category.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: Color(0xFF4B5563),
              ),
            ),
          ),
        ),
        _cell(
          Text(
            '${s.activeTutors}',
            style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
          ),
        ),
        _cell(
          s.avgRating == null
              ? const Text('-', style: TextStyle(color: AdminColors.textMuted))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 14, color: Color(0xFFB7791F)),
                    const SizedBox(width: 4),
                    Text(
                      s.avgRating!.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.textDark,
                      ),
                    ),
                  ],
                ),
        ),
        _cell(_StatusPill(active: s.isActive)),
        _cell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: AdminColors.textDark,
                onPressed: _busy ? null : () => _openForm(s),
              ),
              IconButton(
                tooltip: 'View',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                color: AdminColors.textDark,
                onPressed: () => _openDetails(s),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert, size: 18),
                enabled: !_busy,
                onSelected: (v) {
                  if (v == 'toggle') _toggleActive(s);
                  if (v == 'delete') _delete(s);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(s.isActive ? 'Deactivate' : 'Activate'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: Color(0xFFC62828)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          align: Alignment.centerRight,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- helpers

List<int?> _pageItems(int current, int total) {
  if (total <= 5) return [for (var i = 1; i <= total; i++) i];
  final set = <int>{1, total, current - 1, current, current + 1};
  if (current <= 2) set.addAll([2, 3]);
  if (current >= total - 1) set.addAll([total - 2, total - 1]);
  final sorted = set.where((p) => p >= 1 && p <= total).toList()..sort();
  final items = <int?>[];
  for (var i = 0; i < sorted.length; i++) {
    if (i > 0) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap == 2) {
        items.add(sorted[i] - 1);
      } else if (gap > 2) {
        items.add(null);
      }
    }
    items.add(sorted[i]);
  }
  return items;
}

class _CatStyle {
  const _CatStyle(this.icon, this.bg, this.fg);
  final IconData icon;
  final Color bg;
  final Color fg;

  static _CatStyle of(String category) {
    switch (category.toLowerCase()) {
      case 'stem':
        return const _CatStyle(
          Icons.functions,
          Color(0xFFDCE8FF),
          Color(0xFF0A3FA6),
        );
      case 'humanities':
        return const _CatStyle(
          Icons.account_balance_outlined,
          Color(0xFFDDE4FF),
          Color(0xFF1E3A8A),
        );
      case 'social sciences':
        return const _CatStyle(
          Icons.trending_up,
          Color(0xFFFDE7E2),
          Color(0xFFD9480F),
        );
      case 'languages':
        return const _CatStyle(
          Icons.translate,
          Color(0xFFE9E3F7),
          Color(0xFF5B2D91),
        );
      default:
        return const _CatStyle(
          Icons.menu_book_outlined,
          Color(0xFFE8EAEE),
          Color(0xFF4B5563),
        );
    }
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AdminColors.accent : const Color(0xFFF0F1F5),
          borderRadius: BorderRadius.circular(20),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = active ? const Color(0xFF1B7F3A) : const Color(0xFF4B5563);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFD9F5E0) : const Color(0xFFE8EAEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'Active' : 'Inactive',
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

class _PageButton extends StatelessWidget {
  const _PageButton({
    this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });
  final String? label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AdminColors.accent : const Color(0xFFF0F1F5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: icon != null
            ? Icon(
                icon,
                size: 18,
                color: disabled
                    ? const Color(0xFFB0B5BF)
                    : AdminColors.textDark,
              )
            : Text(
                label!,
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

// ---------------------------------------------------------------- summary cards

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: AdminColors.border),
);

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.bg, required this.fg});
  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.label,
    required this.value,
    required this.change,
    required this.trend,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.lineColor,
    required this.fillColor,
  });
  final String label;
  final String value;
  final double? change;
  final List<double> trend;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final Color lineColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    final c = change;
    final up = (c ?? 0) >= 0;
    final changeColor = up ? const Color(0xFF1B7F3A) : const Color(0xFFC62828);
    final abs = c?.abs() ?? 0;

    return Container(
      height: 160,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: AdminColors.textMuted,
                  ),
                ),
              ),
              _IconChip(icon: icon, bg: iconBg, fg: iconFg),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.textDark,
                ),
              ),
              if (c != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        up ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 12,
                        color: changeColor,
                      ),
                      Text(
                        '${abs.toStringAsFixed(abs == abs.roundToDouble() ? 0 : 1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: changeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 48,
            child: _Sparkline(values: trend, line: lineColor, fill: fillColor),
          ),
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({
    required this.values,
    required this.line,
    required this.fill,
  });
  final List<double> values;
  final Color line;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    var minY = values.reduce(min);
    var maxY = values.reduce(max);
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (values.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            color: line,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: fill),
          ),
        ],
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({
    required this.rating,
    required this.target,
    required this.satisfaction,
  });
  final double rating;
  final double? target;
  final double? satisfaction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'AVG SUBJECT RATING',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: AdminColors.textMuted,
                  ),
                ),
              ),
              const _IconChip(
                icon: Icons.star,
                bg: Color(0xFFF3E7C9),
                fg: Color(0xFF5A4A1E),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.textDark,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'out of 5.0',
                  style: TextStyle(fontSize: 12, color: AdminColors.textMuted),
                ),
              ),
            ],
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (rating / 5).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              color: const Color(0xFFB7791F),
              backgroundColor: const Color(0xFFEDEDED),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                target == null
                    ? ''
                    : 'Target baseline: ${target!.toStringAsFixed(1)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AdminColors.textMuted,
                ),
              ),
              Text(
                satisfaction == null
                    ? ''
                    : '${satisfaction!.toStringAsFixed(0)}% Satisfaction',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- dialogs

class _SubjectFormDialog extends StatefulWidget {
  const _SubjectFormDialog({
    required this.categories,
    required this.onSave,
    this.initial,
  });
  final List<String> categories;
  final Subject? initial;
  final Future<void> Function(SubjectInput input) onSave;

  @override
  State<_SubjectFormDialog> createState() => _SubjectFormDialogState();
}

class _SubjectFormDialogState extends State<_SubjectFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _code = TextEditingController(text: widget.initial?.code);
  late final _department = TextEditingController(
    text: widget.initial?.department,
  );
  late final _category = TextEditingController(text: widget.initial?.category);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _department.dispose();
    _category.dispose();
    super.dispose();
  }

  String? _required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? '$label is required' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        SubjectInput(
          name: _name.text.trim(),
          code: _code.text.trim().toUpperCase(),
          department: _department.text.trim(),
          category: _category.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
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
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Edit Subject' : 'Add Subject'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Subject name'),
                  validator: (v) => _required(v, 'Subject name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Course code',
                    hintText: 'e.g. MATH-401',
                  ),
                  validator: (v) => _required(v, 'Course code'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _department,
                  decoration: const InputDecoration(
                    labelText: 'Department (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: (v) => _required(v, 'Category'),
                ),
                if (widget.categories.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final c in widget.categories)
                          ActionChip(
                            label: Text(
                              c,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () => _category.text = c,
                          ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(editing ? 'Save changes' : 'Add subject'),
        ),
      ],
    );
  }
}

class _SubjectDetailsDialog extends StatelessWidget {
  const _SubjectDetailsDialog({required this.subject});
  final Subject subject;

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AdminColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AdminColors.textDark,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(subject.name),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Course code', subject.code),
            _row(
              'Department',
              subject.department.isEmpty ? '-' : subject.department,
            ),
            _row('Category', subject.category),
            _row('Status', subject.isActive ? 'Active' : 'Inactive'),
            _row('Active tutors', '${subject.activeTutors}'),
            _row(
              'Avg rating',
              subject.avgRating == null
                  ? '-'
                  : subject.avgRating!.toStringAsFixed(1),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
