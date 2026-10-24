import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_purchase.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 0, 52);

  Map<String, Object?> manual({
    String type = 'Single',
    String key = 'test-key',
    List<Map<String, String>>? lessons,
  }) => {
    'tutorId': 6,
    'subjectId': 12,
    'purchaseType': type,
    'schedulingMode': 'manual',
    'idempotencyKey': key,
    'lessons':
        lessons ??
        [
          {
            'date': '2026-10-19',
            'startTime': '05:00',
            'endTime': '06:00',
          },
        ],
  };

  test('parses a single and a manually scheduled package', () {
    final single = CreateBookingPurchaseCommand.parse(
      manual(),
      nowUtc: now,
    );
    final package = CreateBookingPurchaseCommand.parse(
      manual(
        type: 'Package',
        lessons: [
          {
            'date': '2026-10-19',
            'startTime': '05:00',
            'endTime': '06:00',
          },
          {
            'date': '2026-10-19',
            'startTime': '06:00',
            'endTime': '07:00',
          },
        ],
      ),
      nowUtc: now,
    );

    expect(single.lessons, hasLength(1));
    expect(package.lessons, hasLength(2));
    expect(package.lessons.first.startTime, '05:00');
  });

  test('generates recurring package lessons on the same weekday and time', () {
    final command = CreateBookingPurchaseCommand.parse(
      {
        'tutorId': 6,
        'subjectId': 12,
        'purchaseType': 'Package',
        'schedulingMode': 'weekly',
        'idempotencyKey': 'weekly-key',
        'recurrence': {
          'firstDate': '2026-10-19',
          'startTime': '05:00',
          'lessonCount': 3,
        },
      },
      nowUtc: now,
    );

    expect(
      command.lessons.map((lesson) => '${lesson.date.iso} ${lesson.startTime}'),
      ['2026-10-19 05:00', '2026-10-26 05:00', '2026-11-02 05:00'],
    );
  });

  test(
    'rejects malformed input, invalid duration, duplicates and overlaps',
    () {
      expect(
        () => CreateBookingPurchaseCommand.parse('not an object', nowUtc: now),
        throwsA(isA<BookingPurchaseRequestException>()),
      );
      expect(
        () => CreateBookingPurchaseCommand.parse(
          manual(
            lessons: [
              {
                'date': '2026-10-19',
                'startTime': '05:00',
                'endTime': '06:01',
              },
            ],
          ),
          nowUtc: now,
        ),
        throwsFormatException,
      );
      expect(
        () => CreateBookingPurchaseCommand.parse(
          manual(
            type: 'Package',
            lessons: [
              {
                'date': '2026-10-19',
                'startTime': '05:00',
                'endTime': '06:00',
              },
              {
                'date': '2026-10-19',
                'startTime': '05:00',
                'endTime': '06:00',
              },
            ],
          ),
          nowUtc: now,
        ),
        throwsA(isA<BookingPurchaseRequestException>()),
      );
      expect(
        () => CreateBookingPurchaseCommand.parse(
          manual(
            type: 'Package',
            lessons: [
              {
                'date': '2026-10-19',
                'startTime': '05:00',
                'endTime': '06:00',
              },
              {
                'date': '2026-10-19',
                'startTime': '05:30',
                'endTime': '06:30',
              },
            ],
          ),
          nowUtc: now,
        ),
        throwsA(isA<BookingPurchaseRequestException>()),
      );
      expect(
        () => CreateBookingPurchaseCommand.parse(
          manual(
            lessons: [
              {
                'date': '2026-02-30',
                'startTime': '05:00',
                'endTime': '06:00',
              },
            ],
          ),
          nowUtc: now,
        ),
        throwsA(isA<BookingPurchaseRequestException>()),
      );
    },
  );

  test('rejects the exact cutoff, accepts just over it', () {
    expect(
      () => CreateBookingPurchaseCommand.parse(
        manual(
          lessons: [
            {
              'date': '2026-10-19',
              'startTime': '04:52',
              'endTime': '05:52',
            },
          ],
        ),
        nowUtc: now,
      ),
      throwsFormatException,
    );
    expect(
      CreateBookingPurchaseCommand.parse(
        manual(
          lessons: [
            {
              'date': '2026-10-19',
              'startTime': '04:53',
              'endTime': '05:53',
            },
          ],
        ),
        nowUtc: now,
      ).lessons,
      hasLength(1),
    );
  });

  test('accepts the inclusive 90th day and rejects the 91st', () {
    final date90 = '2027-01-17';
    final date91 = '2027-01-18';
    expect(
      CreateBookingPurchaseCommand.parse(
        manual(
          lessons: [
            {'date': date90, 'startTime': '05:00', 'endTime': '06:00'},
          ],
        ),
        nowUtc: now,
      ).lessons,
      hasLength(1),
    );
    expect(
      () => CreateBookingPurchaseCommand.parse(
        manual(
          lessons: [
            {'date': date91, 'startTime': '05:00', 'endTime': '06:00'},
          ],
        ),
        nowUtc: now,
      ),
      throwsFormatException,
    );
  });

  test('canonical request fingerprint is stable', () {
    final first = CreateBookingPurchaseCommand.parse(
      manual(
        type: 'Package',
        lessons: [
          {'date': '2026-10-26', 'startTime': '06:00', 'endTime': '07:00'},
          {'date': '2026-10-19', 'startTime': '05:00', 'endTime': '06:00'},
        ],
      ),
      nowUtc: now,
    );
    final same = CreateBookingPurchaseCommand.parse(
      manual(
        type: 'Package',
        lessons: [
          {'date': '2026-10-19', 'startTime': '05:00', 'endTime': '06:00'},
          {'date': '2026-10-26', 'startTime': '06:00', 'endTime': '07:00'},
        ],
      ),
      nowUtc: now,
    );
    expect(first.fingerprint, same.fingerprint);
  });

  test('accepts an optional trimmed note for the tutor', () {
    final withoutNote = CreateBookingPurchaseCommand.parse(
      manual(),
      nowUtc: now,
    );
    final withNote = CreateBookingPurchaseCommand.parse(
      {...manual(), 'note': '  Focus on integration by parts.  '},
      nowUtc: now,
    );
    final blankNote = CreateBookingPurchaseCommand.parse(
      {...manual(), 'note': '   '},
      nowUtc: now,
    );

    expect(withoutNote.note, isNull);
    expect(withNote.note, 'Focus on integration by parts.');
    expect(blankNote.note, isNull);
    // A note is part of the request, so reusing a key with a different note
    // is a different request; a blank note is the same as none.
    expect(withNote.fingerprint, isNot(withoutNote.fingerprint));
    expect(blankNote.fingerprint, withoutNote.fingerprint);
  });

  test('rejects a note that is not text or is too long', () {
    expect(
      () => CreateBookingPurchaseCommand.parse(
        {...manual(), 'note': 42},
        nowUtc: now,
      ),
      throwsA(isA<BookingPurchaseRequestException>()),
    );
    expect(
      () => CreateBookingPurchaseCommand.parse(
        {...manual(), 'note': 'a' * (maximumBookingNoteLength + 1)},
        nowUtc: now,
      ),
      throwsA(isA<BookingPurchaseRequestException>()),
    );
    expect(
      () => CreateBookingPurchaseCommand.parse(
        {...manual(), 'comment': 'not a documented field'},
        nowUtc: now,
      ),
      throwsA(isA<BookingPurchaseRequestException>()),
    );
  });
}
