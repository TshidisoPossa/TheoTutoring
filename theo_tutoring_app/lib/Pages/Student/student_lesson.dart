import 'package:flutter/material.dart';

import 'student_lessons_api.dart';

class _LessonColors {
  static const background = Color(0xFFF0F4FA);
  static const primary = Color(0xFF2A6BB2);
  static const textDark = Color(0xFF1E293B);
  static const textGrey = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const cancelBg = Color(0xFFF1F5F9);
  static const confirmedBg = Color(0xFFDCFCE7);
  static const confirmedText = Color(0xFF16A34A);
  static const cancelledBg = Color(0xFFFEE2E2);
  static const cancelledText = Color(0xFFDC2626);
  static const pendingBg = Color(0xFFFEF3C7);
  static const pendingText = Color(0xFFB45309);
}

/// One booking from GET /students/lessons: the tutor, subject and time come
/// from the tutor's booking record.
class Lesson {
  final int bookingId;
  final String tutorName;
  final String subject;
  final DateTime start;
  final DateTime end;
  final String status;
  final String? avatarUrl;
  final String? link;
  final String? cancellationReason;

  const Lesson({
    required this.bookingId,
    required this.tutorName,
    required this.subject,
    required this.start,
    required this.end,
    required this.status,
    this.avatarUrl,
    this.link,
    this.cancellationReason,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    final date = '${json['date']}';
    final start = DateTime.tryParse('${date}T${json['startTime']}');
    final end = DateTime.tryParse('${date}T${json['endTime']}');
    if (json['bookingId'] is! int || start == null || end == null) {
      throw const FormatException('Lesson is missing its booking or time.');
    }
    String? optional(Object? value) {
      final text = (value as String?)?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return Lesson(
      bookingId: json['bookingId'] as int,
      tutorName: optional(json['tutorName']) ?? 'Tutor',
      subject: optional(json['subject']) ?? 'Tutoring session',
      start: start,
      end: end,
      status: optional(json['status']) ?? 'Pending',
      avatarUrl: optional(json['tutorPhoto']),
      link: optional(json['link']),
      cancellationReason: optional(json['cancellationReason']),
    );
  }

  bool get isConfirmed => status == 'Confirmed';

  /// e.g. "2 hrs", "1 hr", "1 hr 30 min".
  String get duration {
    final minutes = end.difference(start).inMinutes;
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$rest min';
    final hourLabel = hours == 1 ? '1 hr' : '$hours hrs';
    return rest == 0 ? hourLabel : '$hourLabel $rest min';
  }

  /// e.g. "Friday, Jan 17 • 11:30 AM".
  String get dateTime {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = start.hour % 12 == 0 ? 12 : start.hour % 12;
    final minute = start.minute.toString().padLeft(2, '0');
    final period = start.hour < 12 ? 'AM' : 'PM';
    return '${weekdays[start.weekday - 1]}, ${months[start.month - 1]} '
        '${start.day} • $hour:$minute $period';
  }
}

/// The student's Lessons tab ("My Schedule"), shown inside the dashboard's
/// Scaffold so the menu button opens the dashboard drawer.
class StudentLessonsPage extends StatefulWidget {
  const StudentLessonsPage({super.key});

  @override
  State<StudentLessonsPage> createState() => _StudentLessonsPageState();
}

class _StudentLessonsPageState extends State<StudentLessonsPage> {
  int _tabIndex = 0; // 0 = Upcoming, 1 = Cancelled

  final StudentLessonsApi _api = StudentLessonsApi();
  List<Lesson> _upcoming = [];
  List<Lesson> _cancelled = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _loadLessons() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetch();
      if (!mounted) return;
      setState(() {
        _upcoming = _readLessons(data['upcoming'] as List);
        _cancelled = _readLessons(data['cancelled'] as List);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Lesson> _readLessons(List items) {
    final lessons = <Lesson>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      try {
        lessons.add(Lesson.fromJson(item));
      } on FormatException {
        // skip a booking the app cannot read rather than failing the page
      }
    }
    return lessons;
  }

  Future<void> _cancelLesson(Lesson lesson) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonDialog(
        title: 'Cancel lesson?',
        label: 'Why are you cancelling?',
        dismissLabel: 'Keep lesson',
        submitLabel: 'Cancel lesson',
      ),
    );
    if (reason == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final result = await _api.cancel(lesson.bookingId, reason);
      final percent = result['refundPercentage'];
      message = percent == null
          ? 'Lesson cancelled.'
          : percent == 0
          ? 'Lesson cancelled. Lessons cancelled less than 24 hours '
                'before they start are not refunded.'
          : 'Lesson cancelled. You will be refunded '
                'R${result['refundAmount']} ($percent%).';
    } catch (error) {
      message = error.toString();
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (mounted) await _loadLessons();
  }

  Future<void> _reportLesson(Lesson lesson) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Report ${lesson.tutorName}?',
        message:
            'Your report goes to the TheoTutoring administrator, who will '
            'look into it.',
        label: 'What went wrong?',
        dismissLabel: 'Close',
        submitLabel: 'Send report',
      ),
    );
    if (reason == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.report(lesson.bookingId, reason);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Report sent. An administrator will review it.'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showSoon(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature will be connected soon.')));
  }

  void _startSession(Lesson lesson) {
    final link = lesson.link;
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your tutor has not added a session link yet.'),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session link'),
        content: SelectableText(link),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _LessonColors.background,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadLessons,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildTabs(),
                    const SizedBox(height: 20),
                    ..._buildLessons(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLessons() {
    if (_loading && _upcoming.isEmpty && _cancelled.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) return [_buildError()];

    final lessons = _tabIndex == 0 ? _upcoming : _cancelled;
    if (lessons.isEmpty) return [_buildEmptyState()];
    return [
      for (final lesson in lessons)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: LessonCard(
            lesson: lesson,
            showActions: _tabIndex == 0,
            onCancel: () => _cancelLesson(lesson),
            // TODO: connect rescheduling to the backend
            onReschedule: () => _showSoon('Rescheduling'),
            onReport: () => _reportLesson(lesson),
            onStart: lesson.isConfirmed ? () => _startSession(lesson) : null,
          ),
        ),
    ];
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
            icon: const Icon(Icons.menu, color: _LessonColors.textDark),
            tooltip: 'Open menu',
          ),
          const SizedBox(width: 8),
          const Text(
            'My Schedule',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _LessonColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        Expanded(child: _tabButton('Upcoming', 0)),
        const SizedBox(width: 12),
        Expanded(child: _tabButton('Cancelled', 1)),
      ],
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _LessonColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? _LessonColors.primary : _LessonColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : _LessonColors.textGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: Text(
          _tabIndex == 0 ? 'No upcoming lessons' : 'No cancelled lessons',
          style: const TextStyle(color: _LessonColors.textGrey, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 42,
            color: _LessonColors.textGrey,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _LessonColors.textGrey),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _loadLessons, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class LessonCard extends StatelessWidget {
  final Lesson lesson;
  final bool showActions;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onReport;

  /// Null until the lesson is Confirmed (paid), which disables the button.
  final VoidCallback? onStart;

  const LessonCard({
    super.key,
    required this.lesson,
    required this.onCancel,
    required this.onReschedule,
    required this.onReport,
    required this.onStart,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final avatarUrl = lesson.avatarUrl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _LessonColors.border),
      ),
      child: Column(
        children: [
          // Tutor row
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _LessonColors.cancelBg,
                child: avatarUrl == null
                    ? const Icon(Icons.person, color: _LessonColors.textGrey)
                    : ClipOval(
                        child: Image.network(
                          avatarUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.person,
                            color: _LessonColors.textGrey,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.tutorName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _LessonColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            lesson.subject,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _LessonColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '·',
                          style: TextStyle(color: _LessonColors.textGrey),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          lesson.duration,
                          style: const TextStyle(
                            fontSize: 16,
                            color: _LessonColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: lesson.status),
              if (showActions)
                _LessonMenu(
                  onCancel: onCancel,
                  onReschedule: onReschedule,
                  onReport: onReport,
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _LessonColors.border),

          // Date row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: _LessonColors.textGrey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    lesson.dateTime,
                    style: const TextStyle(
                      fontSize: 16,
                      color: _LessonColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _LessonColors.border),

          if (lesson.cancellationReason != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Cancellation reason: ${lesson.cancellationReason}',
                style: const TextStyle(
                  fontSize: 14,
                  color: _LessonColors.textGrey,
                ),
              ),
            ),
          ],

          if (showActions) ...[
            const SizedBox(height: 14),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: _ActionButton(
                  label: 'Start session',
                  background: _LessonColors.primary,
                  foreground: Colors.white,
                  onTap: onStart,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      'Confirmed' => (_LessonColors.confirmedBg, _LessonColors.confirmedText),
      'Cancelled' => (_LessonColors.cancelledBg, _LessonColors.cancelledText),
      _ => (_LessonColors.pendingBg, _LessonColors.pendingText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

enum _LessonAction { cancel, reschedule, report }

/// The three-line button beside the status badge with the lesson's options.
class _LessonMenu extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onReport;

  const _LessonMenu({
    required this.onCancel,
    required this.onReschedule,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_LessonAction>(
      icon: const Icon(Icons.menu, color: _LessonColors.textGrey),
      tooltip: 'Lesson options',
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (action) => switch (action) {
        _LessonAction.cancel => onCancel(),
        _LessonAction.reschedule => onReschedule(),
        _LessonAction.report => onReport(),
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _LessonAction.cancel,
          child: _MenuRow(
            icon: Icons.cancel_outlined,
            label: 'Cancel',
            color: _LessonColors.cancelledText,
          ),
        ),
        PopupMenuItem(
          value: _LessonAction.reschedule,
          child: _MenuRow(
            icon: Icons.event_repeat_outlined,
            label: 'Reschedule',
            color: _LessonColors.textDark,
          ),
        ),
        PopupMenuItem(
          value: _LessonAction.report,
          child: _MenuRow(
            icon: Icons.flag_outlined,
            label: 'Report',
            color: _LessonColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 15, color: color)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks why the student is cancelling or reporting a lesson; pops the
/// trimmed reason (5-500 characters), or null when dismissed.
class ReasonDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String label;
  final String dismissLabel;
  final String submitLabel;

  const ReasonDialog({
    super.key,
    required this.title,
    required this.label,
    required this.dismissLabel,
    required this.submitLabel,
    this.message,
  });

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
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
    final message = widget.message;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  color: _LessonColors.textGrey,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: widget.label,
                border: const OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().length < 5
                  ? 'Please enter at least 5 characters.'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.dismissLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}
