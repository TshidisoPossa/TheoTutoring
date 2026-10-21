import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const lessonDurationMinutes = 60;
const minimumBookingLeadTime = Duration(hours: 2);
const maximumBookingDays = 90;

late final tz.Location _johannesburg = _loadJohannesburg();

tz.Location _loadJohannesburg() {
  tz_data.initializeTimeZones();
  return tz.getLocation('Africa/Johannesburg');
}

class BookingDate {
  const BookingDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  factory BookingDate.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw const FormatException('Dates must use YYYY-MM-DD format.');
    }
    final date = BookingDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    if (date.year < 1000) {
      throw const FormatException('Date is outside the supported calendar.');
    }
    if (date.toUtcMidnight().year != date.year ||
        date.toUtcMidnight().month != date.month ||
        date.toUtcMidnight().day != date.day) {
      throw const FormatException('Date is not a valid calendar date.');
    }
    return date;
  }

  DateTime toUtcMidnight() => DateTime.utc(year, month, day);

  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  int get weekday => toUtcMidnight().weekday;

  BookingDate addDays(int days) {
    final date = toUtcMidnight().add(Duration(days: days));
    return BookingDate(date.year, date.month, date.day);
  }

  int daysUntil(BookingDate other) =>
      other.toUtcMidnight().difference(toUtcMidnight()).inDays;

  @override
  bool operator ==(Object other) =>
      other is BookingDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

class LessonInterval {
  const LessonInterval({
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
  });

  final BookingDate date;
  final int startMinutes;
  final int endMinutes;

  bool overlaps(LessonInterval other) =>
      date == other.date &&
      startMinutes < other.endMinutes &&
      endMinutes > other.startMinutes;
}

class WeeklyAvailability {
  const WeeklyAvailability({
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
  });

  final int weekday;
  final int startMinutes;
  final int endMinutes;

  bool contains(LessonInterval slot) =>
      slot.date.weekday == weekday &&
      startMinutes <= slot.startMinutes &&
      endMinutes >= slot.endMinutes;
}

class AvailableLesson {
  const AvailableLesson(this.interval);

  final LessonInterval interval;

  String get date => interval.date.iso;
  String get startTime => formatClockTime(interval.startMinutes);
  String get endTime => formatClockTime(interval.endMinutes);
}

class BookingPrice {
  const BookingPrice({
    required this.lessonCount,
    required this.rateCents,
    required this.subtotalCents,
    required this.discountPercent,
    required this.discountCents,
    required this.totalCents,
  });

  final int lessonCount;
  final int rateCents;
  final int subtotalCents;
  final int discountPercent;
  final int discountCents;
  final int totalCents;

  String get rate => formatMoney(rateCents);
  String get subtotal => formatMoney(subtotalCents);
  String get discount => formatMoney(discountCents);
  String get total => formatMoney(totalCents);

  List<int> allocateLessonCents() {
    final base = totalCents ~/ lessonCount;
    final remainder = totalCents % lessonCount;
    return List<int>.generate(
      lessonCount,
      (index) => base + (index < remainder ? 1 : 0),
      growable: false,
    );
  }
}

BookingDate johannesburgDate(DateTime nowUtc) {
  final local = tz.TZDateTime.from(nowUtc.toUtc(), _johannesburg);
  return BookingDate(local.year, local.month, local.day);
}

/// The 90-day horizon includes the calendar date exactly 90 days after today
/// in Africa/Johannesburg.
void validateLessonSlot({
  required LessonInterval slot,
  required DateTime nowUtc,
  required List<WeeklyAvailability> availability,
}) {
  validateLessonTiming(slot: slot, nowUtc: nowUtc);
  if (!availability.any((window) => window.contains(slot))) {
    throw const FormatException(
      "The lesson is outside the tutor's weekly availability.",
    );
  }
}

void validateLessonTiming({
  required LessonInterval slot,
  required DateTime nowUtc,
}) {
  if (slot.startMinutes < 0 ||
      slot.startMinutes >= 24 * 60 ||
      slot.endMinutes > 24 * 60 ||
      slot.endMinutes - slot.startMinutes != lessonDurationMinutes) {
    throw const FormatException('A lesson must be exactly 60 minutes.');
  }

  final today = johannesburgDate(nowUtc);
  final daysAhead = today.daysUntil(slot.date);
  if (daysAhead < 0 || daysAhead > maximumBookingDays) {
    throw const FormatException(
      'Lessons must be scheduled within the next 90 days.',
    );
  }

  final localStart = tz.TZDateTime(
    _johannesburg,
    slot.date.year,
    slot.date.month,
    slot.date.day,
    slot.startMinutes ~/ 60,
    slot.startMinutes % 60,
  );
  final utcStart = localStart.toUtc();
  if (!utcStart.isAfter(nowUtc.toUtc().add(minimumBookingLeadTime))) {
    throw const FormatException(
      'A lesson must start more than two hours from now.',
    );
  }
}

List<AvailableLesson> findAvailableLessons({
  required BookingDate from,
  required BookingDate through,
  required DateTime nowUtc,
  required List<WeeklyAvailability> availability,
  required List<LessonInterval> busyIntervals,
}) {
  final today = johannesburgDate(nowUtc);
  if (from.daysUntil(through) < 0 ||
      today.daysUntil(from) < 0 ||
      today.daysUntil(through) > maximumBookingDays) {
    throw const FormatException(
      'Availability dates must be within the next 90 days.',
    );
  }

  final slots = <AvailableLesson>[];
  final emitted = <String>{};
  for (var offset = 0; offset <= from.daysUntil(through); offset++) {
    final date = from.addDays(offset);
    for (final window in availability.where(
      (item) => item.weekday == date.weekday,
    )) {
      for (
        var start = window.startMinutes;
        start + lessonDurationMinutes <= window.endMinutes;
        start += lessonDurationMinutes
      ) {
        final interval = LessonInterval(
          date: date,
          startMinutes: start,
          endMinutes: start + lessonDurationMinutes,
        );
        try {
          validateLessonSlot(
            slot: interval,
            nowUtc: nowUtc,
            availability: [window],
          );
        } on FormatException {
          continue;
        }
        if (busyIntervals.any(interval.overlaps)) continue;
        final key = '${date.iso}:$start';
        if (emitted.add(key)) slots.add(AvailableLesson(interval));
      }
    }
  }
  return slots;
}

BookingPrice calculateBookingPrice({
  required String platformRate,
  required String purchaseType,
  required int lessonCount,
}) {
  final rateCents = parseMoney(platformRate);
  if (rateCents <= 0 || rateCents > 9999999999) {
    throw const FormatException('The administrator tutoring rate is invalid.');
  }

  if (purchaseType == 'Single' && lessonCount != 1) {
    throw const FormatException('A single purchase must contain one lesson.');
  }
  if (purchaseType == 'Package' && (lessonCount < 2 || lessonCount > 65535)) {
    throw const FormatException(
      'A package must contain between 2 and 65,535 lessons.',
    );
  }
  if (purchaseType != 'Single' && purchaseType != 'Package') {
    throw const FormatException('Purchase type must be Single or Package.');
  }

  final subtotalCents = rateCents * lessonCount;
  if (subtotalCents > 999999999999) {
    throw const FormatException('Purchase total exceeds the supported amount.');
  }
  final discountPercent = purchaseType == 'Package' && lessonCount >= 10
      ? 10
      : 0;
  final discountCents = discountPercent == 0 ? 0 : (subtotalCents + 5) ~/ 10;

  return BookingPrice(
    lessonCount: lessonCount,
    rateCents: rateCents,
    subtotalCents: subtotalCents,
    discountPercent: discountPercent,
    discountCents: discountCents,
    totalCents: subtotalCents - discountCents,
  );
}

int parseClockTime(String value) {
  final match = RegExp(
    r'^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$',
  ).firstMatch(value);
  if (match == null || (match.group(3) != null && match.group(3) != '00')) {
    throw const FormatException(
      'Times must be valid whole-minute HH:mm values.',
    );
  }
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

String formatClockTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

int parseMoney(String value) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value.trim());
  if (match == null) {
    throw const FormatException('The administrator tutoring rate is invalid.');
  }
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction.isEmpty ? '0' : fraction);
}

String formatMoney(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
