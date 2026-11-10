// Reviews: what students say about their tutors (documentation: the admin
// can "view reviews and user reports"). Summary figures, the rating
// breakdown, tutors needing attention, a filterable paginated table and a
// details dialog with the booking and any reports on it. Read-only: the
// admin acts on a tutor from the Tutors page, never by changing a review.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'Services/admin_reviews_service.dart';
import 'admin_shell.dart';
import 'models/admin_review_models.dart';

const _surface2 = Color(0xFFF8F9FB);
const _star = Color(0xFFF5A524);
const _starOff = Color(0xFFD9DDE4);
const _green = Color(0xFF1B7F3A);
const _greenBg = Color(0xFFD9F5E0);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFDEBD0);
const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDE2E2);
const _greyBg = Color(0xFFE8EAEE);

final _count = NumberFormat('#,##0');

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

class AdminReviewsScreen extends StatefulWidget {
  const AdminReviewsScreen({super.key, this.service, this.pageSize = 10});

  final AdminReviewsService? service;
  final int pageSize;

  @override
  State<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends State<AdminReviewsScreen> {
  static const _ranges = <(String, String)>[
    ('All time', 'all'),
    ('Last 7 days', '7d'),
    ('Last 30 days', '30d'),
    ('Last 90 days', '90d'),
  ];
  static const _sorts = <(String, String)>[
    ('Newest first', 'newest'),
    ('Oldest first', 'oldest'),
    ('Lowest rating', 'lowest'),
    ('Highest rating', 'highest'),
  ];

  late final AdminReviewsService _service;
  late final bool _ownsService;
  final _search = TextEditingController();
  Timer? _searchDebounce;

  AdminReviewFilters _filters = const AdminReviewFilters();
  int _page = 1;
  AdminReviewsPage? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminReviewsService();
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
      final data = await _service.fetchReviews(
        filters: _filters,
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

  void _setFilters(AdminReviewFilters filters) {
    setState(() {
      _filters = filters;
      _page = 1;
    });
    _load();
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _setFilters(_filters.copyWith(search: text)),
    );
  }

  void _goToPage(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    _load();
  }

  void _openReview(AdminReview review) {
    showDialog<void>(
      context: context,
      builder: (_) => _ReviewDialog(review: review, service: _service),
    );
  }

  void _openTutors() => Navigator.of(context).pushNamed(AdminRoutes.tutors);

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AdminShell(
      currentRoute: AdminRoutes.reviews,
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
                    child: _error is AdminReviewsUnavailable
                        ? const _StateMessage(
                            icon: Icons.cloud_off_outlined,
                            title: 'Reviews are not available yet.',
                            message:
                                'This server does not provide the Admin '
                                'review endpoints yet.',
                          )
                        : _StateMessage(
                            icon: Icons.error_outline,
                            title: 'Could not load reviews.',
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
                      message: 'Could not refresh reviews: ${_msg(_error!)}',
                      onRetry: _load,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildStats(data!.summary),
                  const SizedBox(height: 20),
                  _buildInsights(data),
                  const SizedBox(height: 20),
                  _buildFilters(),
                  const SizedBox(height: 12),
                  _buildTable(data),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStats(ReviewSummary s) {
    final stats = [
      _StatCard(label: 'Total Reviews', value: _count.format(s.totalReviews)),
      _StatCard(
        label: 'Average Rating',
        value: s.totalReviews == 0 ? '—' : s.averageRating.toStringAsFixed(2),
        trailing: s.totalReviews == 0
            ? null
            : const Icon(Icons.star_rounded, color: _star, size: 28),
      ),
      _StatCard(
        label: 'Low Ratings (30 days)',
        value: _count.format(s.lowRatingsLast30Days),
        hint: '1–2 stars',
        valueColor: s.lowRatingsLast30Days > 0 ? _red : null,
      ),
      _StatCard(
        label: 'Reviews This Month',
        value: _count.format(s.reviewsThisMonth),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final perRow = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in stats) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _buildInsights(AdminReviewsPage data) {
    final breakdown = _BreakdownCard(
      distribution: data.distribution,
      total: data.summary.totalReviews,
      selected: _filters.rating,
      onSelect: (stars) => _setFilters(
        _filters.copyWith(
          rating: () => _filters.rating == stars ? null : stars,
        ),
      ),
    );
    final attention = _AttentionCard(
      tutors: data.needsAttention,
      onOpenTutors: _openTutors,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: breakdown),
                const SizedBox(width: 14),
                Expanded(child: attention),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [breakdown, const SizedBox(height: 14), attention],
        );
      },
    );
  }

  Widget _buildFilters() {
    final f = _filters;
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              // The keyboard's Search key searches now and closes it
              textInputAction: TextInputAction.search,
              onSubmitted: (text) {
                _searchDebounce?.cancel();
                if (text != _filters.search) {
                  _setFilters(_filters.copyWith(search: text));
                }
              },
              style: const TextStyle(fontSize: 13),
              decoration: _inputDecoration(
                hint: 'Search tutor, student or subject...',
                icon: Icons.search,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _FilterChip(
                label: 'All',
                active: f.rating == null,
                onTap: () => _setFilters(f.copyWith(rating: () => null)),
              ),
              for (var stars = 5; stars >= 1; stars--)
                _FilterChip(
                  label: '$stars★',
                  active: f.rating == stars,
                  onTap: () => _setFilters(f.copyWith(rating: () => stars)),
                ),
            ],
          ),
          _Dropdown(
            tooltip: 'Date range',
            value: f.range,
            items: _ranges,
            onChanged: (range) => _setFilters(f.copyWith(range: range)),
          ),
          _Dropdown(
            tooltip: 'Sort reviews',
            value: f.sort,
            items: _sorts,
            onChanged: (sort) => _setFilters(f.copyWith(sort: sort)),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _setFilters(f.copyWith(withComment: !f.withComment)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: f.withComment,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) =>
                      _setFilters(f.copyWith(withComment: v ?? false)),
                ),
                const Text(
                  'With a comment',
                  style: TextStyle(fontSize: 13, color: AdminColors.textDark),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(AdminReviewsPage data) {
    final reviews = data.reviews;
    final first = data.total == 0 ? 0 : (data.page - 1) * data.pageSize + 1;
    final last = first == 0 ? 0 : first + reviews.length - 1;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MinWidthScroll(
            minWidth: 900,
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
                      SizedBox(width: 100, child: _TableHeader('Date')),
                      Expanded(flex: 3, child: _TableHeader('Student')),
                      Expanded(flex: 3, child: _TableHeader('Tutor')),
                      Expanded(flex: 2, child: _TableHeader('Subject')),
                      SizedBox(width: 104, child: _TableHeader('Rating')),
                      Expanded(flex: 4, child: _TableHeader('Comment')),
                      SizedBox(
                        width: 64,
                        child: _TableHeader('View', alignEnd: true),
                      ),
                    ],
                  ),
                ),
                for (final review in reviews) ...[
                  const Divider(height: 1, color: AdminColors.border),
                  _ReviewRow(review: review, onOpen: () => _openReview(review)),
                ],
              ],
            ),
          ),
          if (reviews.isEmpty) ...[
            const Divider(height: 1, color: AdminColors.border),
            _filters.isDefault
                ? const _StateMessage(
                    icon: Icons.rate_review_outlined,
                    title: 'No reviews yet',
                    message:
                        'Reviews appear here once students rate a completed '
                        'lesson.',
                  )
                : const _StateMessage(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'No reviews match',
                    message: 'Try another rating, date range or search term.',
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
                  '${data.total == 1 ? 'review' : 'reviews'}',
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

InputDecoration _inputDecoration({required String hint, IconData? icon}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13),
      prefixIcon: icon == null ? null : Icon(icon, size: 18),
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AdminColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AdminColors.border),
      ),
    );

// ------------------------------------------------------------ widgets

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Reviews',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AdminColors.textDark,
        ),
      ),
      SizedBox(height: 4),
      Text(
        'What students say about their tutors after completed lessons. '
        'Reviews are read-only.',
        style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
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

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: AdminColors.textDark,
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
    this.hint,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;
  final String? hint;

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AdminColors.textDark,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            if (hint != null) ...[
              const SizedBox(width: 8),
              Text(
                hint!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class _Stars extends StatelessWidget {
  const _Stars(this.rating, {this.size = 16});
  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$rating out of 5 stars',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            Icon(
              star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: star <= rating ? _star : _starOff,
            ),
        ],
      ),
    ),
  );
}

/// 5★ to 1★ bars; tapping a bar filters the table to that rating.
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.distribution,
    required this.total,
    required this.selected,
    required this.onSelect,
  });

  final Map<int, int> distribution;
  final int total;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CardTitle('Rating breakdown'),
        const SizedBox(height: 4),
        const Text(
          'Tap a row to show only those reviews.',
          style: TextStyle(fontSize: 12, color: AdminColors.textMuted),
        ),
        const SizedBox(height: 12),
        for (var stars = 5; stars >= 1; stars--)
          _breakdownRow(stars, distribution[stars] ?? 0),
      ],
    ),
  );

  Widget _breakdownRow(int stars, int count) {
    final share = total == 0 ? 0.0 : count / total;
    final active = selected == stars;
    return InkWell(
      key: ValueKey('breakdown-$stars'),
      borderRadius: BorderRadius.circular(6),
      onTap: () => onSelect(stars),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AdminColors.selected : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '$stars★',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.textDark,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 8,
                  backgroundColor: _greyBg,
                  color: stars <= 2 ? _red : AdminColors.accent,
                ),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                '${_count.format(count)}  ${(share * 100).round()}%',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tutors averaging below 3 stars over at least 3 reviews.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.tutors, required this.onOpenTutors});

  final List<TutorNeedingAttention> tutors;
  final VoidCallback onOpenTutors;

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _CardTitle('Tutors needing attention')),
            TextButton(
              onPressed: onOpenTutors,
              child: const Text('Open Tutors'),
            ),
          ],
        ),
        const Text(
          'Average below 3★ from at least 3 reviews. Suspend or contact them '
          'from the Tutors page.',
          style: TextStyle(fontSize: 12, color: AdminColors.textMuted),
        ),
        const SizedBox(height: 12),
        if (tutors.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: _green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No tutors need attention right now.',
                    style: TextStyle(fontSize: 13, color: AdminColors.textDark),
                  ),
                ),
              ],
            ),
          )
        else
          for (final tutor in tutors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _Avatar(
                    name: tutor.name,
                    initials: tutor.initials,
                    photoUrl: tutor.photoUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tutor.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.textDark,
                          ),
                        ),
                        Text(
                          '${tutor.reviewCount} reviews'
                          '${tutor.status == null ? '' : ' · ${tutor.status}'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.star_rounded, color: _star, size: 18),
                  const SizedBox(width: 2),
                  Text(
                    tutor.averageRating.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _red,
                    ),
                  ),
                ],
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

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.tooltip,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String tooltip;
  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
          padding: const EdgeInsets.symmetric(vertical: 10),
          items: [
            for (final (label, key) in items)
              DropdownMenuItem(value: key, child: Text(label)),
          ],
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.initials, this.photoUrl});

  static const radius = 16.0;

  final String name;
  final String initials;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AdminColors.selected,
      foregroundImage: photo == null ? null : NetworkImage(photo),
      onForegroundImageError: photo == null ? null : (_, _) {},
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w700,
          color: AdminColors.primary,
        ),
      ),
    );
  }
}

class _PersonCell extends StatelessWidget {
  const _PersonCell({required this.person});
  final ReviewPerson person;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _Avatar(
        name: person.name,
        initials: person.initials,
        photoUrl: person.photoUrl,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          person.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AdminColors.textDark,
          ),
        ),
      ),
    ],
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review, required this.onOpen});

  final AdminReview review;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: Container(
      color: review.rating <= 2 ? const Color(0xFFFDF4F4) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              review.dateLabel,
              style: const TextStyle(fontSize: 12, color: AdminColors.textDark),
            ),
          ),
          Expanded(flex: 3, child: _PersonCell(person: review.student)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _PersonCell(person: review.tutor)),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              review.subject ?? '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
            ),
          ),
          SizedBox(width: 104, child: _Stars(review.rating)),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    review.comment ?? 'No comment',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: review.comment == null
                          ? AdminColors.textMuted
                          : AdminColors.textDark,
                      fontStyle: review.comment == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
                if (review.reportCount > 0)
                  Tooltip(
                    message:
                        '${review.reportCount} '
                        '${review.reportCount == 1 ? 'report' : 'reports'} '
                        'on this lesson',
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.flag, size: 18, color: _red),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'View review',
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: onOpen,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The full review, the lesson, both people and any reports on the lesson.
class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.review, required this.service});

  final AdminReview review;
  final AdminReviewsService service;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late Future<AdminReview> _details;

  @override
  void initState() {
    super.initState();
    _details = widget.service.fetchReview(widget.review.reviewId);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
    title: Row(
      children: [
        Expanded(child: Text('Review #${widget.review.reviewId}')),
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
    content: SizedBox(
      width: 560,
      child: FutureBuilder<AdminReview>(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.error_outline,
              title: 'Could not load this review.',
              message: _msg(snapshot.error!),
              action: ElevatedButton(
                onPressed: () => setState(() {
                  _details = widget.service.fetchReview(widget.review.reviewId);
                }),
                child: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return SingleChildScrollView(child: _buildDetails(snapshot.data!));
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          Navigator.of(context)
            ..pop()
            ..pushNamed(AdminRoutes.tutors);
        },
        child: const Text('Open Tutors page'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        style: FilledButton.styleFrom(backgroundColor: AdminColors.primary),
        child: const Text('Close'),
      ),
    ],
  );

  Widget _buildDetails(AdminReview r) {
    final booking = r.booking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Stars(r.rating, size: 24),
            const SizedBox(width: 10),
            Text(
              '${r.rating}/5 · ${r.dateLabel}',
              style: const TextStyle(
                fontSize: 13,
                color: AdminColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminColors.border),
          ),
          child: SelectableText(
            r.comment ?? 'The student left a rating without a comment.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: r.comment == null
                  ? AdminColors.textMuted
                  : AdminColors.textDark,
              fontStyle: r.comment == null
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
        ),
        if (r.highlights.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'What made it great',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AdminColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final highlight in r.highlights)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AdminColors.selected,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    highlight,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (r.privateNote != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _amberBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: _amber),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Private note to platform support (the tutor '
                        'cannot see this)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _amber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  r.privateNote!,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AdminColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        _Section(
          title: 'Lesson',
          rows: [
            ('Subject', r.subject ?? '—'),
            if (booking != null) ...[
              ('Booking', '#${booking.bookingId}'),
              ('When', booking.label),
              ('Status', booking.status ?? '—'),
            ],
          ],
        ),
        _Section(
          title: 'Tutor',
          rows: [
            ('Name', r.tutor.name),
            ('Email', r.tutor.email ?? '—'),
            ('Account', r.tutor.status ?? '—'),
            if (r.tutor.averageRating != null)
              (
                'Average',
                '${r.tutor.averageRating!.toStringAsFixed(2)}★ from '
                    '${r.tutor.reviewCount ?? 0} reviews',
              ),
          ],
        ),
        _Section(
          title: 'Student',
          rows: [
            ('Name', r.student.name),
            ('Email', r.student.email ?? '—'),
            ('University', r.student.institution ?? '—'),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Reports on this lesson (${r.reports.length})',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        if (r.reports.isEmpty)
          const Text(
            'Nobody has reported this lesson.',
            style: TextStyle(fontSize: 13, color: AdminColors.textMuted),
          )
        else
          for (final report in r.reports) _ReportTile(report: report),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});
  final ReviewReport report;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (report.status) {
      'Resolved' => (_green, _greenBg),
      'Under review' => (_amber, _amberBg),
      _ => (_red, _redBg),
    };
    final who = [
      report.reporterName,
      if (report.reporterRole != null) '(${report.reporterRole})',
    ].whereType<String>().join(' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Report #${report.reportId}'
                  '${report.category == null ? '' : ' · ${report.category}'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.textDark,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  report.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          if (who.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'By $who',
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            report.reason,
            style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
          ),
        ],
      ),
    );
  }
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

/// Scrolls the table sideways on narrow screens instead of squashing it.
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
