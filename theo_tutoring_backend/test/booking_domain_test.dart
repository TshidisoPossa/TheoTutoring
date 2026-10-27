import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 0, 52);
  final monday = BookingDate(2026, 10, 19);
  final availability = [
    const WeeklyAvailability(
      weekday: DateTime.monday,
      startMinutes: 4 * 60,
      endMinutes: 9 * 60,
    ),
  ];

  group('Johannesburg lesson rules', () {
    test('accepts a 60-minute slot strictly more than two hours ahead', () {
      expect(
        () => validateLessonSlot(
          slot: LessonInterval(
            date: monday,
            startMinutes: 4 * 60 + 53,
            endMinutes: 5 * 60 + 53,
          ),
          nowUtc: now,
          availability: availability,
        ),
        returnsNormally,
      );
    });

    test('rejects a slot exactly two hours ahead', () {
      expect(
        () => validateLessonSlot(
          slot: LessonInterval(
            date: monday,
            startMinutes: 4 * 60 + 52,
            endMinutes: 5 * 60 + 52,
          ),
          nowUtc: now,
          availability: availability,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('more than two hours'),
          ),
        ),
      );
    });

    test('requires exactly one hour and availability containment', () {
      expect(
        () => validateLessonSlot(
          slot: LessonInterval(
            date: monday,
            startMinutes: 5 * 60,
            endMinutes: 6 * 60 + 1,
          ),
          nowUtc: now,
          availability: availability,
        ),
        throwsFormatException,
      );
      expect(
        () => validateLessonSlot(
          slot: LessonInterval(
            date: monday,
            startMinutes: 9 * 60,
            endMinutes: 10 * 60,
          ),
          nowUtc: now,
          availability: availability,
        ),
        throwsFormatException,
      );
    });

    test('enforces the 90-day booking window', () {
      for (final date in [monday.addDays(-1), monday.addDays(91)]) {
        expect(
          () => validateLessonSlot(
            slot: LessonInterval(
              date: date,
              startMinutes: 8 * 60,
              endMinutes: 9 * 60,
            ),
            nowUtc: now,
            availability: availability,
          ),
          throwsFormatException,
        );
      }
    });

    test('includes the calendar date 90 days ahead', () {
      final date = monday.addDays(90);
      expect(
        () => validateLessonSlot(
          slot: LessonInterval(
            date: date,
            startMinutes: 5 * 60,
            endMinutes: 6 * 60,
          ),
          nowUtc: now,
          availability: [
            WeeklyAvailability(
              weekday: date.weekday,
              startMinutes: 4 * 60,
              endMinutes: 9 * 60,
            ),
          ],
        ),
        returnsNormally,
      );
    });

    test('uses the IANA Johannesburg calendar date', () {
      expect(
        johannesburgDate(DateTime.utc(2026, 10, 18, 22, 30)),
        BookingDate(2026, 10, 19),
      );
    });

    test('generates eligible hourly slots and excludes overlaps', () {
      final slots = findAvailableLessons(
        from: monday,
        through: monday,
        nowUtc: now,
        availability: availability,
        busyIntervals: [
          LessonInterval(
            date: monday,
            startMinutes: 6 * 60,
            endMinutes: 7 * 60,
          ),
        ],
      );

      expect(
        slots.map((slot) => '${slot.date} ${slot.startTime}'),
        ['2026-10-19 05:00', '2026-10-19 07:00', '2026-10-19 08:00'],
      );
    });

    test('uses half-open overlap so adjacent lessons do not conflict', () {
      final slot = LessonInterval(
        date: monday,
        startMinutes: 7 * 60,
        endMinutes: 8 * 60,
      );
      final adjacent = LessonInterval(
        date: monday,
        startMinutes: 8 * 60,
        endMinutes: 9 * 60,
      );
      final overlapping = LessonInterval(
        date: monday,
        startMinutes: 7 * 60 + 30,
        endMinutes: 8 * 60 + 30,
      );

      expect(slot.overlaps(adjacent), isFalse);
      expect(slot.overlaps(overlapping), isTrue);
    });

    test('validates ISO calendar dates and clock times', () {
      expect(
        () => BookingDate.parse('2026-02-30'),
        throwsFormatException,
      );
      expect(parseClockTime('08:30:00'), 510);
      expect(() => parseClockTime('25:00'), throwsFormatException);
      expect(() => parseClockTime('08:30:01'), throwsFormatException);
    });
  });

  group('one-off date changes', () {
    final nextMonday = monday.addDays(7);
    final weekly = [
      const WeeklyAvailability(
        weekday: DateTime.monday,
        startMinutes: 8 * 60,
        endMinutes: 12 * 60,
      ),
    ];
    final sunday = monday.addDays(6);

    List<String> slotsOn(
      BookingDate date,
      List<AvailabilityOverride> overrides,
    ) => findAvailableLessons(
      from: date,
      through: date,
      nowUtc: now,
      availability: weekly,
      busyIntervals: const [],
      overrides: overrides,
    ).map((slot) => slot.startTime).toList();

    test('a date without changes keeps its weekly hours', () {
      expect(availabilityWindowsOn(nextMonday, weekly: weekly), [
        (startMinutes: 8 * 60, endMinutes: 12 * 60),
      ]);
      expect(slotsOn(nextMonday, const []), [
        '08:00',
        '09:00',
        '10:00',
        '11:00',
      ]);
    });

    test('a day off removes every slot on that date only', () {
      final off = [AvailabilityOverride(date: nextMonday)];
      expect(availabilityWindowsOn(nextMonday, weekly: weekly, overrides: off),
          isEmpty);
      expect(slotsOn(nextMonday, off), isEmpty);
      // The Monday after still has its weekly hours.
      expect(slotsOn(nextMonday.addDays(7), off), hasLength(4));
    });

    test('custom hours replace the weekly hours on that date', () {
      final custom = [
        AvailabilityOverride(
          date: nextMonday,
          startMinutes: 14 * 60,
          endMinutes: 16 * 60,
        ),
        AvailabilityOverride(
          date: nextMonday,
          startMinutes: 18 * 60,
          endMinutes: 19 * 60,
        ),
      ];
      expect(slotsOn(nextMonday, custom), ['14:00', '15:00', '18:00']);
    });

    test('extra hours open a day with no weekly hours', () {
      final extra = [
        AvailabilityOverride(
          date: sunday,
          startMinutes: 10 * 60,
          endMinutes: 12 * 60,
        ),
      ];
      expect(slotsOn(sunday, const []), isEmpty);
      expect(slotsOn(sunday, extra), ['10:00', '11:00']);
    });

    test('booking validation follows the date change', () {
      void book(BookingDate date, int hour, List<AvailabilityOverride> o) =>
          validateLessonSlot(
            slot: LessonInterval(
              date: date,
              startMinutes: hour * 60,
              endMinutes: (hour + 1) * 60,
            ),
            nowUtc: now,
            availability: weekly,
            overrides: o,
          );

      final off = [AvailabilityOverride(date: nextMonday)];
      expect(
        () => book(nextMonday, 9, off),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains("outside the tutor's availability"),
          ),
        ),
      );
      expect(() => book(nextMonday, 9, const []), returnsNormally);

      final extra = [
        AvailabilityOverride(
          date: sunday,
          startMinutes: 10 * 60,
          endMinutes: 12 * 60,
        ),
      ];
      expect(() => book(sunday, 10, extra), returnsNormally);
      expect(() => book(sunday, 12, extra), throwsFormatException);
    });
  });

  group('server-side price calculation', () {
    test('applies no discount below ten package lessons', () {
      final price = calculateBookingPrice(
        platformRate: '125.50',
        purchaseType: 'Package',
        lessonCount: 9,
      );

      expect(price.subtotal, '1129.50');
      expect(price.discountPercent, 0);
      expect(price.discount, '0.00');
      expect(price.total, '1129.50');
    });

    test('applies ten percent and allocates exact cents for ten lessons', () {
      final price = calculateBookingPrice(
        platformRate: '99.99',
        purchaseType: 'Package',
        lessonCount: 10,
      );
      final allocations = price.allocateLessonCents();

      expect(price.subtotal, '999.90');
      expect(price.discountPercent, 10);
      expect(price.discount, '99.99');
      expect(price.total, '899.91');
      expect(allocations.reduce((a, b) => a + b), price.totalCents);
      expect(
        allocations,
        [9000, 8999, 8999, 8999, 8999, 8999, 8999, 8999, 8999, 8999],
      );
    });

    test('requires valid counts, types and decimal rates', () {
      expect(
        () => calculateBookingPrice(
          platformRate: '1.239',
          purchaseType: 'Single',
          lessonCount: 1,
        ),
        throwsFormatException,
      );
      expect(
        () => calculateBookingPrice(
          platformRate: '10.00',
          purchaseType: 'Single',
          lessonCount: 2,
        ),
        throwsFormatException,
      );
      expect(
        () => calculateBookingPrice(
          platformRate: '10.00',
          purchaseType: 'Package',
          lessonCount: 1,
        ),
        throwsFormatException,
      );
    });
  });
}
