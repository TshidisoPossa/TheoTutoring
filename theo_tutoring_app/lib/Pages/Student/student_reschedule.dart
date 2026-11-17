import 'package:flutter/material.dart';

import '../Booking/booking_api.dart';
import '../Tutor/tutor_theme.dart';
import 'student_lesson.dart';
import 'student_lessons_api.dart';

/// Reschedule in My Schedule's lesson menu: moves a paid lesson to another
/// free hour with the same tutor and subject. The payment stays with the
/// lesson, so nothing is charged or refunded
/// (`POST /students/lessons/{id}/reschedule`).
///
/// Free hours come from GET /StudentlandingPage/availability, the same list
/// the booking pages use. Pops `true` once the lesson has moved.
class StudentReschedulePage extends StatefulWidget {
  const StudentReschedulePage({
    required this.lesson,
    required this.lessonsApi,
    this.availabilityApi,
    this.today,
    super.key,
  });

  final Lesson lesson;
  final StudentLessonsApi lessonsApi;

  /// Loads the tutor's free hours; tests pass a fake.
  final BookingFlowApi? availabilityApi;

  /// Today's date; tests pass a fixed one.
  final DateTime? today;

  /// How far ahead the page offers times (the server allows 90 days).
  static const daysAhead = 28;

  @override
  State<StudentReschedulePage> createState() => _StudentReschedulePageState();
}

class _StudentReschedulePageState extends State<StudentReschedulePage> {
  late final BookingFlowApi _availability =
      widget.availabilityApi ?? HttpBookingFlowApi();

  /// Free hours by date ("2026-11-20"), dates in order.
  Map<String, List<AvailableBookingSlot>> _byDate = {};
  String? _day;
  AvailableBookingSlot? _slot;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Light colours, or the dark ones while dark mode is on
  bool get _dk => context.tutorDark;
  Color get _bg => _dk ? TutorDark.background : const Color(0xFFF0F4FA);
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _text => _dk ? TutorDark.text : const Color(0xFF1E293B);
  Color get _muted => _dk ? TutorDark.textMuted : const Color(0xFF64748B);
  Color get _border => _dk ? TutorDark.border : const Color(0xFFE2E8F0);
  Color get _accent => _dk ? TutorDark.blueText : _blue;
  static const _blue = Color(0xFF2A6BB2);

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final now = widget.today ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      final result = await _availability.availability(
        tutorId: widget.lesson.tutorId!,
        subjectId: widget.lesson.subjectId!,
        from: _iso(today),
        through: _iso(
          today.add(const Duration(days: StudentReschedulePage.daysAhead)),
        ),
      );
      final byDate = <String, List<AvailableBookingSlot>>{};
      for (final slot in result.slots) {
        (byDate[slot.date] ??= []).add(slot);
      }
      final dates = byDate.keys.toList()..sort();
      if (!mounted) return;
      setState(() {
        _byDate = {for (final d in dates) d: byDate[d]!};
        _day = dates.contains(_day) ? _day : dates.firstOrNull;
        _slot = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final slot = _slot;
    if (slot == null || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.lessonsApi.reschedule(
        widget.lesson.bookingId,
        date: slot.date,
        startTime: slot.startTime,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Lesson moved to ${_dayLabel(slot.date)}, ${slot.startTime}. '
            '${widget.lesson.tutorName} has been told.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
      await _load(); // that time may have just been taken
    }
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "2026-11-20" -> "Fri 20 Nov"
  static String _dayLabel(String iso) {
    final d = DateTime.parse(iso);
    return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Reschedule lesson'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${lesson.subject} with ${lesson.tutorName}',
                    style: TextStyle(
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Now: ${_dayLabel(_iso(lesson.start))}, '
                    '${_clock(lesson.start)}–${_clock(lesson.end)}',
                    style: TextStyle(color: _muted, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.verified_outlined, size: 18, color: _accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Your payment stays with this lesson. Nothing extra '
                          'is charged.',
                          style: TextStyle(color: _accent, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ..._buildPicker(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _slot == null || _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              _saving
                  ? 'Moving lesson…'
                  : _slot == null
                  ? 'Choose a new time'
                  : 'Move to ${_dayLabel(_slot!.date)}, ${_slot!.startTime}',
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPicker() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        Text(_error!, style: TextStyle(color: _muted)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ),
      ];
    }
    if (_byDate.isEmpty) {
      return [
        Text(
          '${widget.lesson.tutorName} has no free times in the next '
          '${StudentReschedulePage.daysAhead ~/ 7} weeks.',
          style: TextStyle(color: _muted),
        ),
      ];
    }
    final slots = _byDate[_day] ?? const <AvailableBookingSlot>[];
    return [
      _heading('Pick a day'),
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _byDate.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final date = _byDate.keys.elementAt(index);
            return _chip(
              _dayLabel(date),
              selected: date == _day,
              onTap: () => setState(() {
                _day = date;
                _slot = null;
              }),
            );
          },
        ),
      ),
      const SizedBox(height: 20),
      _heading('Pick a time'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final slot in slots)
            _chip(
              '${slot.startTime}–${slot.endTime}',
              selected: identical(slot, _slot),
              onTap: () => setState(() => _slot = slot),
            ),
        ],
      ),
    ];
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: child,
  );

  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => Material(
    color: selected ? _blue : _surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: selected ? _blue : _border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _saving ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _text,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}
