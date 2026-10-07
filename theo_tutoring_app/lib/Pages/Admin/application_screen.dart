import 'package:flutter/material.dart';

import 'models/Tutapplication.dart';

import 'Services/tutapplication_services.dart';
import 'admin_shell.dart';

enum _Sort { newest, oldest }

class AdminApplicationsScreen extends StatefulWidget {
  const AdminApplicationsScreen({super.key});

  @override
  State<AdminApplicationsScreen> createState() =>
      _AdminApplicationsScreenState();
}

class _AdminApplicationsScreenState extends State<AdminApplicationsScreen> {
  final _service = AdminApplicationsService();

  List<TutorApplication> _applications = [];
  String? _adminName;
  _Sort _sort = _Sort.newest;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _service.fetchApplications();
      if (!mounted) return;
      setState(() {
        _applications = result.applications;
        _adminName = result.adminName;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<TutorApplication> get _sorted {
    final list = [..._applications];
    list.sort(
      (a, b) => _sort == _Sort.newest
          ? b.appliedAt.compareTo(a.appliedAt)
          : a.appliedAt.compareTo(b.appliedAt),
    );
    return list;
  }

  Future<void> _review(TutorApplication application) async {
    await Navigator.pushNamed(
      context,
      AdminRoutes.applicationReview,
      arguments: application.id,
    );
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.applications,
      adminName: _adminName,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load tutor applications.'),
              const SizedBox(height: 8),
              Text(
                _error!,
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
                        'Tutor Applications',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.textDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Review and process new tutor onboarding requests.',
                        style: TextStyle(
                          fontSize: 14,
                          color: AdminColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  _SortDropdown(
                    value: _sort,
                    onChanged: (v) => setState(() => _sort = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_applications.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'No tutor applications to review.',
                      style: TextStyle(color: AdminColors.textMuted),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 680
                        ? 3
                        : constraints.maxWidth >= 440
                        ? 2
                        : 1;
                    const gap = 24.0;
                    final width =
                        (constraints.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final a in _sorted)
                          SizedBox(
                            width: width,
                            child: _ApplicationCard(
                              application: a,
                              onReview: () => _review(a),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- sort

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({required this.value, required this.onChanged});
  final _Sort value;
  final ValueChanged<_Sort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SORT BY:',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              color: AdminColors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<_Sort>(
            value: value,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 14, color: AdminColors.textDark),
            items: const [
              DropdownMenuItem(
                value: _Sort.newest,
                child: Text('Date Applied (Newest)'),
              ),
              DropdownMenuItem(
                value: _Sort.oldest,
                child: Text('Date Applied (Oldest)'),
              ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- card

class _StatusStyle {
  const _StatusStyle(this.label, this.accent, this.bg, this.fg);
  final String label;
  final Color accent;
  final Color bg;
  final Color fg;

  static _StatusStyle of(String status) {
    switch (status) {
      case 'pending_review':
        return const _StatusStyle(
          'PENDING REVIEW',
          Color(0xFF8A5A00),
          Color(0xFFFFF1C7),
          Color(0xFF8A5A00),
        );
      case 'background_check':
        return const _StatusStyle(
          'BACKGROUND CHECK',
          Color(0xFF1A73C8),
          Color(0xFFD6E9FF),
          Color(0xFF0B5CAD),
        );
      default:
        return _StatusStyle(
          status.replaceAll('_', ' ').toUpperCase(),
          const Color(0xFF6B7280),
          const Color(0xFFE8EAEE),
          const Color(0xFF4B5563),
        );
    }
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.application, required this.onReview});
  final TutorApplication application;
  final VoidCallback onReview;

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 10,
      letterSpacing: 1,
      color: AdminColors.textMuted,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final style = _StatusStyle.of(application.status);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: style.accent),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Avatar(application: application),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                application.fullName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: AdminColors.textDark,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: style.bg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  style.label,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color: style.fg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Applied ${formatApplied(application.appliedAt)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AdminColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _label('QUALIFICATIONS'),
                const SizedBox(height: 4),
                if (application.qualifications.isEmpty)
                  const Text(
                    'Not provided',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textMuted,
                    ),
                  )
                else
                  for (final q in application.qualifications)
                    Text(
                      q,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AdminColors.textDark,
                      ),
                    ),
                const SizedBox(height: 12),
                _label('REQUESTED SUBJECTS'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in application.subjects)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF0F3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminColors.textDark,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AdminColors.border),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: onReview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Review Application'),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 14),
                      ],
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
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.application});
  final TutorApplication application;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF0F4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        application.initials,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );

    final url = application.photoUrl;
    if (url == null || url.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
