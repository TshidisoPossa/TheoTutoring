import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Tutor/tutor_theme.dart';
import 'student_lessons_api.dart';
import 'student_review.dart';

/// The Lessons tab's colours: light, or dark while dark mode is on.
class _LessonColors {
  const _LessonColors(this._dk);

  final bool _dk;

  Color get background => _dk ? TutorDark.background : const Color(0xFFF0F4FA);
  Color get surface => _dk ? TutorDark.card : Colors.white;
  Color get primary => const Color(0xFF2A6BB2); // fills: tabs, buttons
  Color get accent => _dk ? TutorDark.blueText : primary; // blue text
  Color get textDark => _dk ? TutorDark.text : const Color(0xFF1E293B);
  Color get textGrey => _dk ? TutorDark.textMuted : const Color(0xFF64748B);
  Color get border => _dk ? TutorDark.border : const Color(0xFFE2E8F0);
  Color get cancelBg => _dk ? TutorDark.cardAlt : const Color(0xFFF1F5F9);
  Color get confirmedBg => _dk ? TutorDark.greenTint : const Color(0xFFDCFCE7);
  Color get confirmedText =>
      _dk ? TutorDark.greenText : const Color(0xFF16A34A);
  Color get cancelledBg => _dk ? TutorDark.redTint : const Color(0xFFFEE2E2);
  Color get cancelledText => _dk ? TutorDark.redText : const Color(0xFFDC2626);
  Color get pendingBg => _dk ? TutorDark.amberTint : const Color(0xFFFEF3C7);
  Color get pendingText => _dk ? TutorDark.amberText : const Color(0xFFB45309);
  Color get completedBg => _dk ? TutorDark.blueTint : const Color(0xFFE4ECFF);
  Color get completedText => accent;
  Color get star => const Color(0xFFFFB347);
}

extension on BuildContext {
  _LessonColors get lessonColors => _LessonColors(tutorDark);
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
  final String? cancellationReason;

  /// The student's own stars for a Completed lesson, null until reviewed.
  final int? myRating;

  // Completed lessons only, for the Leave a Review header
  final double? tutorRating; // null until the tutor's first review
  final int tutorReviewCount;
  final bool tutorVerified;
  final String? tutorSubjects; // "Mathematics, Physics"

  const Lesson({
    required this.bookingId,
    required this.tutorName,
    required this.subject,
    required this.start,
    required this.end,
    required this.status,
    this.avatarUrl,
    this.cancellationReason,
    this.myRating,
    this.tutorRating,
    this.tutorReviewCount = 0,
    this.tutorVerified = false,
    this.tutorSubjects,
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
      cancellationReason: optional(json['cancellationReason']),
      myRating: json['myRating'] is int ? json['myRating'] as int : null,
      tutorRating: json['tutorRating'] is num
          ? (json['tutorRating'] as num).toDouble()
          : null,
      tutorReviewCount: json['tutorReviewCount'] is int
          ? json['tutorReviewCount'] as int
          : 0,
      tutorVerified: json['tutorVerified'] == true,
      tutorSubjects: optional(json['tutorSubjects']),
    );
  }

  bool get isConfirmed => status == 'Confirmed';

  /// Start session is enabled for paid lessons the student can join. The
  /// server still checks the time window and payment when it is tapped.
  bool get canStart => status == 'Confirmed' || status == 'Postponed';

  bool get isCompleted => status == 'Completed';

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
  const StudentLessonsPage({super.key, this.api});

  /// Tests pass a fake; the app uses the real backend.
  final StudentLessonsApi? api;

  @override
  State<StudentLessonsPage> createState() => _StudentLessonsPageState();
}

class _StudentLessonsPageState extends State<StudentLessonsPage> {
  int _tabIndex = 0; // 0 = Upcoming, 1 = Completed, 2 = Cancelled

  late final StudentLessonsApi _api = widget.api ?? StudentLessonsApi();
  bool _joining = false; // waiting for the join route; ignores double taps
  List<Lesson> _upcoming = [];
  List<Lesson> _completed = [];
  List<Lesson> _cancelled = [];
  ReviewStudent? _me; // for the Leave a Review header
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
        _completed = _readLessons(data['completed'] as List? ?? const []);
        _cancelled = _readLessons(data['cancelled'] as List);
        final me = data['student'];
        _me = me is Map<String, dynamic> ? ReviewStudent.fromJson(me) : null;
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

  Future<void> _reviewLesson(Lesson lesson) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LeaveReviewScreen(lesson: lesson, student: _me),
      ),
    );
    if (saved == true && mounted) await _loadLessons();
  }

  void _showSoon(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature will be connected soon.')));
  }

  // Two taps (Google Meet design, section 6): this first tap asks the server
  // for the link, which checks the lesson and the 15-minute window. Meet
  // then opens from a fresh tap on Open Google Meet, because Safari can
  // block a tab opened after waiting for the server.
  Future<void> _startSession(Lesson lesson) async {
    if (_joining) return;
    _joining = true;
    final messenger = ScaffoldMessenger.of(context);
    String link;
    try {
      link = await _api.join(lesson.bookingId);
    } catch (error) {
      // The server's message (e.g. "This session opens 15 minutes before it
      // starts."), or a plain one for a timeout or no connection.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is StudentLessonsException
                ? error.message
                : 'Could not reach the server. Please try again.',
          ),
        ),
      );
      return;
    } finally {
      _joining = false;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your session is ready'),
        content: Text(
          'Open Google Meet and ask to join. ${lesson.tutorName} will let '
          'you in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              final opened = await launchUrl(
                Uri.parse(link),
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              );
              if (!opened) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Google Meet could not be opened.'),
                  ),
                );
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Open Google Meet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.lessonColors.background,
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
    if (_loading &&
        _upcoming.isEmpty &&
        _completed.isEmpty &&
        _cancelled.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) return [_buildError()];

    final lessons = switch (_tabIndex) {
      0 => _upcoming,
      1 => _completed,
      _ => _cancelled,
    };
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
            onStart: lesson.canStart ? () => _startSession(lesson) : null,
            onReview: lesson.isCompleted && lesson.myRating == null
                ? () => _reviewLesson(lesson)
                : null,
          ),
        ),
    ];
  }

  Widget _buildHeader() {
    return Container(
      color: context.lessonColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
            icon: Icon(Icons.menu, color: context.lessonColors.textDark),
            tooltip: 'Open menu',
          ),
          const SizedBox(width: 8),
          Text(
            'My Schedule',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.lessonColors.textDark,
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
        const SizedBox(width: 8),
        Expanded(child: _tabButton('Completed', 1)),
        const SizedBox(width: 8),
        Expanded(child: _tabButton('Cancelled', 2)),
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
          color: selected
              ? context.lessonColors.primary
              : context.lessonColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? context.lessonColors.primary
                : context.lessonColors.border,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.lessonColors.textGrey,
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
          switch (_tabIndex) {
            0 => 'No upcoming lessons',
            1 => 'No completed lessons yet',
            _ => 'No cancelled lessons',
          },
          style: TextStyle(color: context.lessonColors.textGrey, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 42,
            color: context.lessonColors.textGrey,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.lessonColors.textGrey),
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

  /// Null unless the lesson is Confirmed or Postponed ([Lesson.canStart]),
  /// which disables the button. The server checks the rest when tapped.
  final VoidCallback? onStart;

  /// "Leave a review" on a Completed lesson the student has not reviewed.
  final VoidCallback? onReview;

  const LessonCard({
    super.key,
    required this.lesson,
    required this.onCancel,
    required this.onReschedule,
    required this.onReport,
    required this.onStart,
    this.onReview,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final avatarUrl = lesson.avatarUrl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.lessonColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.lessonColors.border),
      ),
      child: Column(
        children: [
          // Tutor row
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: context.lessonColors.cancelBg,
                child: avatarUrl == null
                    ? Icon(Icons.person, color: context.lessonColors.textGrey)
                    : ClipOval(
                        child: Image.network(
                          avatarUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.person,
                            color: context.lessonColors.textGrey,
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.lessonColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            lesson.subject,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.lessonColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·',
                          style: TextStyle(
                            color: context.lessonColors.textGrey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          lesson.duration,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.lessonColors.textGrey,
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
          Divider(height: 1, color: context.lessonColors.border),

          // Date row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: context.lessonColors.textGrey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    lesson.dateTime,
                    style: TextStyle(
                      fontSize: 16,
                      color: context.lessonColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.lessonColors.border),

          if (lesson.cancellationReason != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Cancellation reason: ${lesson.cancellationReason}',
                style: TextStyle(
                  fontSize: 14,
                  color: context.lessonColors.textGrey,
                ),
              ),
            ),
          ],

          if (lesson.isCompleted) ...[
            const SizedBox(height: 14),
            if (lesson.myRating != null)
              _MyRating(rating: lesson.myRating!)
            else
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: _ActionButton(
                    label: 'Leave a review',
                    background: context.lessonColors.primary,
                    foreground: Colors.white,
                    onTap: onReview,
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
                  background: context.lessonColors.primary,
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
      'Confirmed' => (
        context.lessonColors.confirmedBg,
        context.lessonColors.confirmedText,
      ),
      'Cancelled' => (
        context.lessonColors.cancelledBg,
        context.lessonColors.cancelledText,
      ),
      'Completed' => (
        context.lessonColors.completedBg,
        context.lessonColors.completedText,
      ),
      _ => (context.lessonColors.pendingBg, context.lessonColors.pendingText),
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

/// "Your rating ★★★★☆" on a Completed lesson the student has reviewed.
class _MyRating extends StatelessWidget {
  final int rating;
  const _MyRating({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Your rating',
          style: TextStyle(fontSize: 14, color: context.lessonColors.textGrey),
        ),
        const SizedBox(width: 8),
        for (var star = 1; star <= 5; star++)
          Icon(
            star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 22,
            color: star <= rating
                ? context.lessonColors.star
                : context.lessonColors.border,
          ),
      ],
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
      icon: Icon(Icons.menu, color: context.lessonColors.textGrey),
      tooltip: 'Lesson options',
      color: context.lessonColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (action) => switch (action) {
        _LessonAction.cancel => onCancel(),
        _LessonAction.reschedule => onReschedule(),
        _LessonAction.report => onReport(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _LessonAction.cancel,
          child: _MenuRow(
            icon: Icons.cancel_outlined,
            label: 'Cancel',
            color: context.lessonColors.cancelledText,
          ),
        ),
        PopupMenuItem(
          value: _LessonAction.reschedule,
          child: _MenuRow(
            icon: Icons.event_repeat_outlined,
            label: 'Reschedule',
            color: context.lessonColors.textDark,
          ),
        ),
        PopupMenuItem(
          value: _LessonAction.report,
          child: _MenuRow(
            icon: Icons.flag_outlined,
            label: 'Report',
            color: context.lessonColors.textDark,
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
      // Scrolls when the phone keyboard leaves too little room, so the
      // buttons are never pushed off screen
      scrollable: true,
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
                style: TextStyle(
                  fontSize: 14,
                  color: context.lessonColors.textGrey,
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
