import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'tutor_theme.dart';

// ---------------------------------------------------------------------------
// AVAILABILITY CALENDAR (tutor Profile page)
// The weekly grid repeats every week; this month view lets the tutor change
// single dates: take the day off or set other hours. Students see the change
// straight away on the booking calendar (the backend applies it).
// ---------------------------------------------------------------------------

/// The hours of each weekly grid row (same as the backend).
const tutorPeriodHours = {
  'Morning': (start: 8, end: 12),
  'Afternoon': (start: 12, end: 17),
  'Evening': (start: 17, end: 20),
};

/// Hours a lesson can start at when the tutor sets their own hours on a
/// date (06:00 to 21:00, so the last lesson ends at 22:00).
const dateHourChoices = [
  6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, //
];

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

const _blue = Color(0xFF2563EB);
const _red = Color(0xFFDC2626);

// Light colours, or the dark ones when the tutor turned on Dark Mode
mixin _CalendarColors<T extends StatefulWidget> on State<T> {
  bool get _dk => context.tutorDark;
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _blueText => _dk ? TutorDark.blueText : _blue;
  Color get _blueLight => _dk ? TutorDark.blueTint : const Color(0xFFE8F0FE);
  Color get _amber => _dk ? TutorDark.amberText : const Color(0xFFB45309);
  Color get _amberLight => _dk ? TutorDark.amberTint : const Color(0xFFFEF3C7);
  Color get _offFill => _dk ? TutorDark.cardAlt : const Color(0xFFF1F4F9);
  Color get _dark => _dk ? TutorDark.text : const Color(0xFF111827);
  Color get _grey => _dk ? TutorDark.textMuted : const Color(0xFF6B7280);
  Color get _muted => _dk ? TutorDark.textFaint : const Color(0xFF9CA3AF);
  Color get _faint => _dk ? TutorDark.border : const Color(0xFFD1D5DB);
  Color get _border => _dk ? TutorDark.border : const Color(0xFFE5E7EB);
}

/// "2026-11-13"
String dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

/// 9 -> "09:00"
String hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}:00';

/// [8, 9, 10, 14] -> "08:00–11:00, 14:00–15:00"
String describeHours(List<int> hours) =>
    hoursToTimes(hours).map((t) => '${t['startTime']}–${t['endTime']}').join(
      ', ',
    );

/// Starting hours -> the time ranges the backend takes:
/// [9, 10, 14] -> [{09:00-11:00}, {14:00-15:00}]
List<Map<String, String>> hoursToTimes(List<int> hours) {
  final sorted = hours.toSet().toList()..sort();
  final times = <Map<String, String>>[];
  for (var i = 0; i < sorted.length; i++) {
    final start = sorted[i];
    while (i + 1 < sorted.length && sorted[i + 1] == sorted[i] + 1) {
      i++;
    }
    times.add({
      'startTime': hourLabel(start),
      'endTime': hourLabel(sorted[i] + 1),
    });
  }
  return times;
}

/// The starting hours the weekly grid gives [date], e.g. Monday Morning ->
/// [8, 9, 10, 11]. [weekly] is day -> ticked rows, as saved.
List<int> usualHoursOn(DateTime date, Map<String, Set<String>> weekly) {
  final ticked = weekly[_weekdayNames[date.weekday - 1]] ?? const {};
  return [
    for (final period in tutorPeriodHours.entries)
      if (ticked.contains(period.key))
        for (var h = period.value.start; h < period.value.end; h++) h,
  ];
}

// "14:30" -> 870
int _minutes(String time) {
  final parts = time.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// The calendar part of GET /TutorLandingpage/Profile.
class AvailabilityCalendarData {
  const AvailabilityCalendarData({
    required this.today,
    required this.lastDate,
    required this.changes,
    required this.booked,
  });

  /// Today and the last date students can book (Johannesburg time).
  final DateTime today;
  final DateTime lastDate;

  /// Dates with their own hours: "2026-11-13" -> starting hours.
  /// An empty list is a day off.
  final Map<String, List<int>> changes;

  /// Lessons booked: "2026-11-13" -> the hours they take up.
  final Map<String, List<int>> booked;

  factory AvailabilityCalendarData.fromJson(Map<String, dynamic> json) {
    final changes = <String, List<int>>{};
    for (final c in (json['dateChanges'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()) {
      changes[c['date'] as String] = [
        for (final t in (c['times'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>())
          for (
            var h = _minutes(t['startTime'] as String) ~/ 60;
            h * 60 < _minutes(t['endTime'] as String);
            h++
          )
            h,
      ];
    }

    final booked = <String, List<int>>{};
    for (final b in (json['bookings'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()) {
      final start = _minutes(b['startTime'] as String);
      final end = _minutes(b['endTime'] as String);
      final hours = booked.putIfAbsent(b['date'] as String, () => []);
      // every hour the lesson touches: 14:00-15:30 -> 14 and 15
      for (var h = start ~/ 60; h * 60 < end; h++) {
        if (!hours.contains(h)) hours.add(h);
      }
    }

    return AvailabilityCalendarData(
      today: DateTime.parse(json['today'] as String),
      lastDate: DateTime.parse(json['lastDate'] as String),
      changes: changes,
      booked: booked,
    );
  }

  /// True for dates the tutor can still change (today to [lastDate]).
  bool canChange(DateTime date) =>
      !date.isBefore(today) && !date.isAfter(lastDate);
}

/// How a date looks in the calendar.
enum CalendarDayKind {
  /// The weekly hours apply.
  usual,

  /// The tutor set other hours for this date.
  changed,

  /// The tutor took the day off.
  off,

  /// No weekly hours and no change: students cannot book.
  closed,

  /// In the past or beyond the booking window.
  outside,
}

/// What the calendar shows for [date].
CalendarDayKind calendarDayKind(
  DateTime date,
  AvailabilityCalendarData data,
  Map<String, Set<String>> weekly,
) {
  if (!data.canChange(date)) return CalendarDayKind.outside;
  final change = data.changes[dateKey(date)];
  if (change != null) {
    return change.isEmpty ? CalendarDayKind.off : CalendarDayKind.changed;
  }
  return usualHoursOn(date, weekly).isEmpty
      ? CalendarDayKind.closed
      : CalendarDayKind.usual;
}

/// The month calendar under the weekly grid. Tapping a date calls
/// [onDateTap].
class AvailabilityCalendar extends StatefulWidget {
  const AvailabilityCalendar({
    super.key,
    required this.data,
    required this.weekly,
    required this.onDateTap,
  });

  final AvailabilityCalendarData data;

  /// The SAVED weekly grid: day -> ticked rows.
  final Map<String, Set<String>> weekly;
  final ValueChanged<DateTime> onDateTap;

  @override
  State<AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<AvailabilityCalendar>
    with _CalendarColors {
  late DateTime _month = DateTime(
    widget.data.today.year,
    widget.data.today.month,
  );

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final firstMonth = DateTime(data.today.year, data.today.month);
    final lastMonth = DateTime(data.lastDate.year, data.lastDate.month);
    final canGoBack = _month.isAfter(firstMonth);
    final canGoForward = _month.isBefore(lastMonth);

    // Monday-first grid, like the weekly grid above it
    final leadingBlanks = DateTime(_month.year, _month.month).weekday - 1;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _dayCell(DateTime(_month.year, _month.month, day)),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    var openDays = 0;
    var changedDays = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final kind = calendarDayKind(date, data, widget.weekly);
      if (kind == CalendarDayKind.usual || kind == CalendarDayKind.changed) {
        openDays++;
      }
      if (kind == CalendarDayKind.changed || kind == CalendarDayKind.off) {
        changedDays++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: canGoBack
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
              color: _dark,
              disabledColor: _faint,
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM y').format(_month),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _dark,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: canGoForward
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
              color: _dark,
              disabledColor: _faint,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < cells.length ~/ 7; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (final cell in cells.sublist(row * 7, row * 7 + 7))
                  Expanded(child: SizedBox(height: 44, child: cell)),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          '$openDays ${openDays == 1 ? 'day' : 'days'} open for booking'
          '${changedDays == 0 ? '' : ' · $changedDays changed'}',
          style: TextStyle(color: _grey, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _LegendItem(fill: _blueLight, label: 'Usual hours', color: _grey),
            _LegendItem(
              fill: _amberLight,
              label: 'Changed hours',
              color: _grey,
            ),
            _LegendItem(fill: _offFill, label: 'Day off', color: _grey),
            _LegendItem(icon: Icons.lock, label: 'Has a lesson', color: _grey),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(DateTime date) {
    final data = widget.data;
    final kind = calendarDayKind(date, data, widget.weekly);
    final isToday = DateUtils.isSameDay(date, data.today);
    final hasLesson =
        kind != CalendarDayKind.outside &&
        (data.booked[dateKey(date)]?.isNotEmpty ?? false);

    final (fill, textColor, label) = switch (kind) {
      CalendarDayKind.usual => (_blueLight, _blueText, 'usual hours'),
      CalendarDayKind.changed => (_amberLight, _amber, 'changed hours'),
      CalendarDayKind.off => (_offFill, _grey, 'day off'),
      CalendarDayKind.closed => (_surface, _dark, 'no hours'),
      CalendarDayKind.outside => (Colors.transparent, _faint, 'not bookable'),
    };
    final enabled = kind != CalendarDayKind.outside;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: enabled,
        label:
            '${DateFormat('EEEE d MMMM').format(date)}, $label'
            '${hasLesson ? ', has a lesson' : ''}',
        excludeSemantics: true,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isToday
                ? const BorderSide(color: _blue, width: 1.5)
                : kind == CalendarDayKind.closed
                ? BorderSide(color: _border)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? () => widget.onDateTap(date) : null,
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: kind == CalendarDayKind.outside
                          ? FontWeight.w400
                          : FontWeight.w600,
                      decoration: kind == CalendarDayKind.off
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                if (hasLesson)
                  Positioned(
                    top: 3,
                    right: 4,
                    child: Icon(Icons.lock, size: 10, color: textColor),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.color,
    this.fill,
    this.icon,
  });

  final String label;
  final Color color; // label and icon
  final Color? fill;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 12, color: color)
        else
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

// ── DATE SHEET ───────────────────────────────────────────────────────────────

/// What the tutor picks for one date in the sheet.
enum DateHoursMode {
  usual('usual'),
  off('off'),
  custom('custom');

  const DateHoursMode(this.apiName);

  /// The `mode` value the backend takes.
  final String apiName;
}

/// Saves the tutor's choice; throws with a message to show if it fails.
typedef SaveDateHours = Future<void> Function(DateHoursMode mode, List<int> hours);

/// Opens the sheet for [date]. Resolves to true once the change is saved.
Future<bool?> showDateHoursSheet(
  BuildContext context, {
  required DateTime date,
  required AvailabilityCalendarData data,
  required Map<String, Set<String>> weekly,
  required SaveDateHours onSave,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.tutorDark ? TutorDark.card : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DateHoursSheet(
      date: date,
      usualHours: usualHoursOn(date, weekly),
      currentChange: data.changes[dateKey(date)],
      bookedHours: data.booked[dateKey(date)] ?? const [],
      onSave: onSave,
    ),
  );
}

/// Day off / Custom hours for one date. Custom hours that match the weekly
/// grid put the date back to its usual hours.
class DateHoursSheet extends StatefulWidget {
  const DateHoursSheet({
    super.key,
    required this.date,
    required this.usualHours,
    required this.currentChange,
    required this.bookedHours,
    required this.onSave,
  });

  final DateTime date;

  /// The weekly grid's hours for this weekday.
  final List<int> usualHours;

  /// This date's own hours, if it has any (empty = day off).
  final List<int>? currentChange;

  /// Hours taken by booked lessons: they cannot be closed.
  final List<int> bookedHours;
  final SaveDateHours onSave;

  @override
  State<DateHoursSheet> createState() => _DateHoursSheetState();
}

class _DateHoursSheetState extends State<DateHoursSheet>
    with _CalendarColors {
  // Nothing is picked on a date that still has its usual hours.
  late DateHoursMode? _mode = switch (widget.currentChange) {
    null => null,
    final change when change.isEmpty => DateHoursMode.off,
    _ => DateHoursMode.custom,
  };

  // Custom starts from this date's hours, so the tutor edits what is there.
  late final Set<int> _hours = {
    ...?widget.currentChange,
    if (widget.currentChange == null || widget.currentChange!.isEmpty)
      ...widget.usualHours,
    ...widget.bookedHours,
  };

  bool _saving = false;
  String? _error;

  bool get _hasLesson => widget.bookedHours.isNotEmpty;

  String get _weekday => _weekdayNames[widget.date.weekday - 1];

  /// Why the picked option cannot be saved, or null.
  String? get _problem {
    switch (_mode) {
      case DateHoursMode.off:
        if (_hasLesson) return 'You have a lesson that day.';
      case DateHoursMode.custom:
        if (_hours.isEmpty) {
          return 'Pick at least one hour, or choose Day off.';
        }
      case null || DateHoursMode.usual:
        break;
    }
    return null;
  }

  Future<void> _save() async {
    var mode = _mode!;
    final hours = _hours.toList()..sort();
    // The same hours as the weekly grid is just "usual" again
    if (mode == DateHoursMode.custom &&
        hours.length == widget.usualHours.length &&
        hours.every(widget.usualHours.contains)) {
      mode = DateHoursMode.usual;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(mode, mode == DateHoursMode.custom ? hours : []);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                DateFormat('EEEE, d MMMM').format(widget.date),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.usualHours.isEmpty
                    ? 'You have no usual hours on ${_weekday}s.'
                    : 'Usual $_weekday hours: '
                          '${describeHours(widget.usualHours)}',
                style: TextStyle(color: _grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<DateHoursMode>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  // Same colours as the calendar: grey day off, yellow custom
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: _mode == DateHoursMode.off
                        ? _offFill
                        : _amberLight,
                    selectedForegroundColor: _mode == DateHoursMode.off
                        ? _dark
                        : _amber,
                  ),
                  segments: [
                    ButtonSegment(
                      value: DateHoursMode.off,
                      label: const Text('Day off'),
                      enabled: !_hasLesson,
                    ),
                    const ButtonSegment(
                      value: DateHoursMode.custom,
                      label: Text('Custom hours'),
                    ),
                  ],
                  selected: {?_mode},
                  onSelectionChanged: _saving
                      ? null
                      : (selected) => setState(() {
                          _mode = selected.firstOrNull;
                          _error = null;
                        }),
                ),
              ),
              const SizedBox(height: 16),
              ..._modeBody(),
              if (_hasLesson) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.lock, size: 14, color: _grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Lesson booked at '
                        '${(widget.bookedHours.toList()..sort()).map(hourLabel).join(', ')}. '
                        'That time stays open.',
                        style: TextStyle(color: _grey, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              if (problem != null || _error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error ?? problem!,
                  style: const TextStyle(color: _red, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _grey,
                        side: BorderSide(color: _faint),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _mode != null && problem == null && !_saving
                          ? _save
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _modeBody() {
    final style = TextStyle(color: _dark, fontSize: 14, height: 1.4);
    switch (_mode) {
      case null || DateHoursMode.usual:
        return [
          Text(
            widget.usualHours.isEmpty
                ? 'Closed. Choose Custom hours to open this day.'
                : 'Students can book ${describeHours(widget.usualHours)}. '
                      'Choose Day off or Custom hours to change it.',
            style: style,
          ),
        ];
      case DateHoursMode.off:
        return [
          Text('Students will not see any times on this day.', style: style),
        ];
      case DateHoursMode.custom:
        return [
          Text(
            'Tap the hours you are free. Each one is a 1-hour lesson.',
            style: style,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2,
            children: [for (final h in dateHourChoices) _hourChip(h)],
          ),
        ];
    }
  }

  Widget _hourChip(int hour) {
    final booked = widget.bookedHours.contains(hour);
    final on = booked || _hours.contains(hour);
    return Semantics(
      button: true,
      toggled: on,
      label: '${hourLabel(hour)}${booked ? ', booked lesson' : ''}',
      excludeSemantics: true,
      child: Material(
        color: on ? _blue : _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: on ? _blue : (_dk ? TutorDark.border : const Color(0xFFCBD5E1)),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: booked || _saving
              ? null
              : () => setState(() {
                  _hours.contains(hour)
                      ? _hours.remove(hour)
                      : _hours.add(hour);
                  _error = null;
                }),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (booked) ...[
                const Icon(Icons.lock, size: 11, color: Colors.white),
                const SizedBox(width: 3),
              ],
              Text(
                hourLabel(hour),
                style: TextStyle(
                  color: on ? Colors.white : _dark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
