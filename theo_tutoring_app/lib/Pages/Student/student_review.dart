import 'package:flutter/material.dart';

import '../Tutor/tutor_theme.dart';
import 'student_lesson.dart' show Lesson, ReasonDialog;
import 'student_lessons_api.dart';

/// The badges under "What made this session great?". Saved with the review
/// and shown only to the admin. Keep in sync with the backend's
/// reviewHighlights (lib/student_reviews.dart).
const reviewHighlights = <(String, IconData)>[
  ('Clear explanations', Icons.lightbulb_outline_rounded),
  ('Punctual & prepared', Icons.schedule_rounded),
  ('Patient with questions', Icons.forum_outlined),
  ('Great practice problems', Icons.edit_note_rounded),
  ('Encouraging atmosphere', Icons.rocket_launch_outlined),
  ('Helpful whiteboard notes', Icons.draw_outlined),
];

/// What the student filled in on the page.
class ReviewDraft {
  const ReviewDraft({
    required this.rating,
    this.comment,
    this.highlights = const [],
    this.privateNote,
  });

  final int rating;
  final String? comment; // public, on the tutor's profile
  final List<String> highlights; // admin only
  final String? privateNote; // admin only
}

/// Saves a review. Tests pass a fake.
typedef SubmitReview = Future<void> Function(int bookingId, ReviewDraft draft);

/// Sends "Need help with this session?" to the admin. Tests pass a fake.
typedef ReportLesson = Future<void> Function(int bookingId, String reason);

/// The reviewing student, for the "Lerato Dube (Year 2)" line.
class ReviewStudent {
  const ReviewStudent({this.name, this.year, this.institution});

  factory ReviewStudent.fromJson(Map<String, dynamic> json) => ReviewStudent(
    name: json['name'] as String?,
    year: json['year'] as String?,
    institution: json['institution'] as String?,
  );

  final String? name;
  final String? year; // "2" from registration, or older free text
  final String? institution;
}

/// "Leave a review" for a completed lesson (documentation 4.9). Stars are
/// required; the public review, the badges and the private note are
/// optional. Saved with `POST /students/lessons/{id}/review`; pops true once
/// it is saved, false on "Skip for now".
class LeaveReviewScreen extends StatefulWidget {
  const LeaveReviewScreen({
    super.key,
    required this.lesson,
    this.student,
    this.submit,
    this.report,
    this.now,
  });

  final Lesson lesson;
  final ReviewStudent? student;

  /// Null uses [StudentLessonsApi.review].
  final SubmitReview? submit;

  /// Null uses [StudentLessonsApi.report].
  final ReportLesson? report;

  /// "Today" / "Yesterday" in the date line; tests fix it.
  final DateTime Function()? now;

  @override
  State<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends State<LeaveReviewScreen> {
  static const _maxLength = 500;
  static const _labels = {
    1: 'Poor',
    2: 'Fair',
    3: 'Good',
    4: 'Great!',
    5: 'Outstanding!',
  };

  final _comment = TextEditingController();
  final _note = TextEditingController();
  StudentLessonsApi? _api;
  int _rating = 0;
  final _highlights = <String>{};
  bool _noteOpen = false;
  bool _saving = false;

  StudentLessonsApi get _client => _api ??= StudentLessonsApi();

  @override
  void initState() {
    super.initState();
    _comment.addListener(() => setState(() {})); // the "154 / 500" counter
  }

  @override
  void dispose() {
    _comment.dispose();
    _note.dispose();
    _api?.close();
    super.dispose();
  }

  /// "Dr. Elena Rostova" -> "Elena"; "Thabo Mokoena" -> "Thabo".
  String get _firstName {
    final parts = widget.lesson.tutorName.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts.first.endsWith('.')) return parts[1];
    return parts.first;
  }

  Future<void> _save() async {
    if (_rating == 0 || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final draft = ReviewDraft(
      rating: _rating,
      comment: text(_comment),
      highlights: [
        for (final (label, _) in reviewHighlights)
          if (_highlights.contains(label)) label,
      ],
      privateNote: text(_note),
    );
    try {
      final submit = widget.submit;
      if (submit != null) {
        await submit(widget.lesson.bookingId, draft);
      } else {
        await _client.review(
          widget.lesson.bookingId,
          rating: draft.rating,
          comment: draft.comment,
          highlights: draft.highlights,
          privateNote: draft.privateNote,
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Thank you! Your review was posted.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  // "Need help with this session?": the same report as on the lesson card
  Future<void> _needHelp() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Need help with this session?',
        message:
            'Tell the TheoTutoring team what went wrong. An administrator '
            'will look into it.',
        label: 'What happened?',
        dismissLabel: 'Close',
        submitLabel: 'Send',
      ),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = widget.report;
      if (report != null) {
        await report(widget.lesson.bookingId, reason);
      } else {
        await _client.report(widget.lesson.bookingId, reason);
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sent. An administrator will look into it.'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _ReviewColors(context.tutorDark);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Leave A Review',
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: c.text,
              child: Text(
                _initials(widget.student?.name ?? ''),
                style: TextStyle(
                  color: c.surface,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sessionCard(c),
                    const SizedBox(height: 14),
                    _ratingCard(c),
                    const SizedBox(height: 14),
                    _highlightsCard(c),
                    const SizedBox(height: 14),
                    _commentCard(c),
                    const SizedBox(height: 20),
                    _submitButton(c),
                    if (_rating == 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Choose a star rating to submit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: Text(
                            'Skip for now',
                            style: TextStyle(color: c.muted, fontSize: 13),
                          ),
                        ),
                        Flexible(
                          child: TextButton(
                            onPressed: _saving ? null : _needHelp,
                            child: Text(
                              'Need help with this session?',
                              textAlign: TextAlign.end,
                              style: TextStyle(color: c.muted, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(_ReviewColors c, {required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: c.border),
    ),
    child: child,
  );

  // ── Session ────────────────────────────────────────────────────────────

  Widget _sessionCard(_ReviewColors c) {
    final lesson = widget.lesson;
    final student = widget.student;
    final studentLine = student?.name == null
        ? null
        : student!.year == null || student.year!.trim().isEmpty
        ? student.name!
        : '${student.name} (${_yearLabel(student.year!)})';
    return _card(
      c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.tint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: c.accent,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Completed Session • ${lesson.subject}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.timer_outlined, size: 15, color: c.muted),
              const SizedBox(width: 4),
              Text(
                '${lesson.end.difference(lesson.start).inMinutes} mins',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.field,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _tutorPhoto(c),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.tutorName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (lesson.tutorSubjects != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${lesson.tutorSubjects} tutor',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star_rounded, size: 16, color: c.star),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              lesson.tutorReviewCount == 0 ||
                                      lesson.tutorRating == null
                                  ? 'New tutor'
                                  : '${lesson.tutorRating!.toStringAsFixed(1)} '
                                        '(${lesson.tutorReviewCount} '
                                        '${lesson.tutorReviewCount == 1 ? 'review' : 'reviews'})',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _when(lesson),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
              if (studentLine != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    studentLine,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _tutorPhoto(_ReviewColors c) {
    final photo = widget.lesson.avatarUrl;
    final fallback = Text(
      _initials(widget.lesson.tutorName),
      style: TextStyle(
        color: c.accent,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
    return Stack(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: c.tint,
          child: photo == null
              ? fallback
              : ClipOval(
                  child: Image.network(
                    photo,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(child: fallback),
                  ),
                ),
        ),
        if (widget.lesson.tutorVerified)
          Positioned(
            right: 0,
            bottom: 0,
            child: Tooltip(
              message: 'Verified tutor',
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: c.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.field, width: 2),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// "Today, 4:00 PM - 5:00 PM", "Yesterday, ..." or "Mon 17 Nov, ...".
  String _when(Lesson lesson) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String time(DateTime t) {
      final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
      final minute = t.minute.toString().padLeft(2, '0');
      return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
    }

    final now = (widget.now ?? DateTime.now)();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
      lesson.start.year,
      lesson.start.month,
      lesson.start.day,
    );
    final daysAgo = today.difference(day).inDays;
    final dayLabel = daysAgo == 0
        ? 'Today'
        : daysAgo == 1
        ? 'Yesterday'
        : '${weekdays[day.weekday - 1]} ${day.day} ${months[day.month - 1]}';
    return '$dayLabel, ${time(lesson.start)} - ${time(lesson.end)}';
  }

  // ── Stars ──────────────────────────────────────────────────────────────

  Widget _ratingCard(_ReviewColors c) => _card(
    c,
    child: Column(
      children: [
        Text(
          'How was your session with $_firstName?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your feedback helps tutors grow and guides fellow students.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        // Shrinks on very narrow phones instead of overflowing
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  key: ValueKey('review-star-$star'),
                  tooltip: '$star ${star == 1 ? 'star' : 'stars'}',
                  iconSize: 40,
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _rating = star),
                  icon: Icon(
                    star <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: star <= _rating ? c.star : c.starOff,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _rating == 0 ? c.field : c.tint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _labels[_rating] ?? 'Tap a star',
            style: TextStyle(
              color: _rating == 0 ? c.muted : c.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Badges ─────────────────────────────────────────────────────────────

  Widget _highlightsCard(_ReviewColors c) => _card(
    c,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _rating > 0 && _rating <= 3
                    ? 'What went well?'
                    : 'What made this session great?',
                style: TextStyle(
                  color: c.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Multi-select',
                style: TextStyle(
                  color: c.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tap the badges that applied to this '
          '${widget.lesson.subject} lesson.',
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, icon) in reviewHighlights)
              _badge(c, label, icon),
          ],
        ),
      ],
    ),
  );

  Widget _badge(_ReviewColors c, String label, IconData icon) {
    final selected = _highlights.contains(label);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.tint : c.field,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? c.accent : c.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          // Reads the current state, so two quick taps always toggle twice
          onTap: _saving
              ? null
              : () => setState(
                  () => _highlights.remove(label) || _highlights.add(label),
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.check_rounded : icon,
                  size: 16,
                  color: selected ? c.accent : c.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? c.accent : c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Public review + private note ───────────────────────────────────────

  Widget _commentCard(_ReviewColors c) => _card(
    c,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Public Review for $_firstName',
                style: TextStyle(
                  color: c.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.public_rounded, size: 20, color: c.muted),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'This review will be visible on $_firstName\'s public tutor '
          'profile.',
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('review-public'),
          controller: _comment,
          enabled: !_saving,
          minLines: 4,
          maxLines: 8,
          maxLength: _maxLength,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: c.text, fontSize: 14),
          buildCounter:
              (_, {required currentLength, required isFocused, maxLength}) =>
                  Text(
                    '$currentLength / $maxLength',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
          decoration: _fieldDecoration(c, 'What stood out in the session?'),
        ),
        const SizedBox(height: 8),
        // Private note: folded away until tapped
        Material(
          color: c.field,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _noteOpen = !_noteOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 18, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Private note for platform support',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _noteOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: c.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_noteOpen) ...[
          const SizedBox(height: 8),
          Text(
            'Only the TheoTutoring team reads this. $_firstName never sees '
            'it.',
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('review-private'),
            controller: _note,
            enabled: !_saving,
            minLines: 3,
            maxLines: 6,
            maxLength: _maxLength,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: c.text, fontSize: 14),
            decoration: _fieldDecoration(
              c,
              'Anything the team should know about this lesson?',
            ),
          ),
        ],
      ],
    ),
  );

  InputDecoration _fieldDecoration(_ReviewColors c, String hint) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.muted, fontSize: 13),
        filled: true,
        fillColor: c.field,
        counterStyle: TextStyle(color: c.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      );

  Widget _submitButton(_ReviewColors c) => SizedBox(
    height: 52,
    child: FilledButton(
      onPressed: _rating == 0 || _saving ? null : _save,
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        disabledBackgroundColor: c.primary.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      child: _saving
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Submit Review',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 8),
                Icon(Icons.send_rounded, size: 18),
              ],
            ),
    ),
  );

  // "Lerato Dube" -> "LD"
  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && !p.endsWith('.'))
        .take(2);
    final letters = parts.map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  // "2" -> "Year 2"; older free text ("2nd Year") as it is
  static String _yearLabel(String year) {
    final trimmed = year.trim();
    return int.tryParse(trimmed) != null ? 'Year $trimmed' : trimmed;
  }
}

/// Light colours, or the dark ones while dark mode is on.
class _ReviewColors {
  const _ReviewColors(this.dark);

  final bool dark;

  Color get background => dark ? TutorDark.background : const Color(0xFFF0F4FA);
  Color get surface => dark ? TutorDark.card : Colors.white;
  Color get field => dark ? TutorDark.cardAlt : const Color(0xFFF3F6FB);
  Color get border => dark ? TutorDark.border : const Color(0xFFE2E8F0);
  Color get text => dark ? TutorDark.text : const Color(0xFF1E293B);
  Color get muted => dark ? TutorDark.textMuted : const Color(0xFF64748B);
  Color get primary => const Color(0xFF2F6FE0);
  Color get accent => dark ? TutorDark.blueText : const Color(0xFF2A5FC4);
  Color get tint => dark ? TutorDark.blueTint : const Color(0xFFE3ECFD);
  Color get star => const Color(0xFFFFB020);
  Color get starOff => dark ? TutorDark.border : const Color(0xFFD5DAE5);
}
