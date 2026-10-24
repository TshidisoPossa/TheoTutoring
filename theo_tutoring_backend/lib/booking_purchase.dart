import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'booking_domain.dart';

class BookingPurchaseRequestException implements Exception {
  const BookingPurchaseRequestException(this.message);

  final String message;
}

class BookingPurchaseConflict implements Exception {
  const BookingPurchaseConflict(this.code, this.message);

  final String code;
  final String message;
}

class BookingPurchaseNotFound implements Exception {
  const BookingPurchaseNotFound();
}

class BookingPurchaseUnavailable implements Exception {
  const BookingPurchaseUnavailable();
}

class BookingPurchaseServiceUnavailable implements Exception {
  const BookingPurchaseServiceUnavailable();
}

class PurchaseLesson {
  const PurchaseLesson({
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
  });

  final BookingDate date;
  final int startMinutes;
  final int endMinutes;

  LessonInterval get interval => LessonInterval(
    date: date,
    startMinutes: startMinutes,
    endMinutes: endMinutes,
  );

  String get startTime => formatClockTime(startMinutes);
  String get endTime => formatClockTime(endMinutes);
}

class CreateBookingPurchaseCommand {
  const CreateBookingPurchaseCommand({
    required this.tutorId,
    required this.subjectId,
    required this.purchaseType,
    required this.schedulingMode,
    required this.idempotencyKey,
    required this.lessons,
    this.note,
  });

  final int tutorId;
  final int subjectId;
  final String purchaseType;
  final String schedulingMode;
  final String idempotencyKey;
  final List<PurchaseLesson> lessons;

  /// The student's optional message to the tutor, saved on every lesson
  /// (Booking.Note).
  final String? note;

  String get fingerprint {
    final canonical = jsonEncode({
      'tutorId': tutorId,
      'subjectId': subjectId,
      'purchaseType': purchaseType,
      'schedulingMode': schedulingMode,
      'lessons': [
        for (final lesson in lessons)
          {
            'date': lesson.date.iso,
            'startTime': lesson.startTime,
            'endTime': lesson.endTime,
          },
      ],
      // Only added when present, so requests without a note keep the
      // fingerprint they had before notes existed.
      if (note != null) 'note': note,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  factory CreateBookingPurchaseCommand.parse(
    Object? input, {
    required DateTime nowUtc,
  }) {
    if (input is! Map<String, dynamic>) {
      throw const BookingPurchaseRequestException(
        'The request body must be a JSON object.',
      );
    }
    final tutorId = _positiveId(input['tutorId']);
    final subjectId = _positiveId(input['subjectId']);
    final purchaseType = input['purchaseType'];
    final schedulingMode = input['schedulingMode'];
    final idempotencyKey = input['idempotencyKey'];
    if (tutorId == null ||
        subjectId == null ||
        purchaseType is! String ||
        schedulingMode is! String ||
        (purchaseType != 'Single' && purchaseType != 'Package') ||
        (schedulingMode != 'manual' && schedulingMode != 'weekly') ||
        idempotencyKey is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(idempotencyKey)) {
      throw const BookingPurchaseRequestException(
        'Provide valid tutorId, subjectId, purchaseType, schedulingMode, '
        'and idempotencyKey fields.',
      );
    }
    final hasNote = input.containsKey('note');
    final note = _parseNote(input['note']);

    late final List<PurchaseLesson> lessons;
    if (schedulingMode == 'manual') {
      if (!_hasExactlyKeys(input, {
        'tutorId',
        'subjectId',
        'purchaseType',
        'schedulingMode',
        'idempotencyKey',
        'lessons',
        if (hasNote) 'note',
      })) {
        throw const BookingPurchaseRequestException(
          'Manual requests must contain only the documented fields.',
        );
      }
      final rawLessons = input['lessons'];
      if (rawLessons is! List || rawLessons.isEmpty) {
        throw const BookingPurchaseRequestException(
          'lessons must contain every scheduled lesson.',
        );
      }
      lessons = [
        for (final raw in rawLessons) _parseManualLesson(raw, nowUtc: nowUtc),
      ];
    } else {
      if (purchaseType != 'Package' ||
          !_hasExactlyKeys(input, {
            'tutorId',
            'subjectId',
            'purchaseType',
            'schedulingMode',
            'idempotencyKey',
            'recurrence',
            if (hasNote) 'note',
          })) {
        throw const BookingPurchaseRequestException(
          'Weekly scheduling is available only for a package and requires '
          'a recurrence object.',
        );
      }
      final recurrence = input['recurrence'];
      if (recurrence is! Map<String, dynamic> ||
          !_hasExactlyKeys(recurrence, {
            'firstDate',
            'startTime',
            'lessonCount',
          })) {
        throw const BookingPurchaseRequestException(
          'recurrence must contain firstDate, startTime, and lessonCount.',
        );
      }
      final count = recurrence['lessonCount'];
      if (count is! int || count < 2 || count > 65535) {
        throw const BookingPurchaseRequestException(
          'A package must contain between 2 and 65,535 lessons.',
        );
      }
      final firstDate = _parseDate(recurrence['firstDate']);
      final start = _parseTime(recurrence['startTime']);
      if (start + lessonDurationMinutes > 24 * 60) {
        throw const BookingPurchaseRequestException(
          'A lesson cannot extend past midnight.',
        );
      }
      lessons = [
        for (var index = 0; index < count; index++)
          PurchaseLesson(
            date: firstDate.addDays(index * 7),
            startMinutes: start,
            endMinutes: start + lessonDurationMinutes,
          ),
      ];
    }

    if (purchaseType == 'Single' && lessons.length != 1) {
      throw const BookingPurchaseRequestException(
        'A single purchase must contain exactly one lesson.',
      );
    }
    if (purchaseType == 'Package' &&
        (lessons.length < 2 || lessons.length > 65535)) {
      throw const BookingPurchaseRequestException(
        'A package must contain between 2 and 65,535 scheduled lessons.',
      );
    }

    lessons.sort((a, b) {
      final day = b.date.daysUntil(a.date);
      return day == 0 ? a.startMinutes.compareTo(b.startMinutes) : day;
    });
    for (var index = 0; index < lessons.length; index++) {
      final lesson = lessons[index];
      validateLessonTiming(slot: lesson.interval, nowUtc: nowUtc);
      if (index > 0 && lessons[index - 1].interval.overlaps(lesson.interval)) {
        throw const BookingPurchaseRequestException(
          'A purchase cannot contain duplicate or overlapping lessons.',
        );
      }
    }

    return CreateBookingPurchaseCommand(
      tutorId: tutorId,
      subjectId: subjectId,
      purchaseType: purchaseType,
      schedulingMode: schedulingMode,
      idempotencyKey: idempotencyKey,
      lessons: List.unmodifiable(lessons),
      note: note,
    );
  }
}

const maximumBookingNoteLength = 500;

/// A blank note is treated as no note.
String? _parseNote(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const BookingPurchaseRequestException('note must be text.');
  }
  final note = value.trim();
  if (note.length > maximumBookingNoteLength) {
    throw const BookingPurchaseRequestException(
      'note must be $maximumBookingNoteLength characters or fewer.',
    );
  }
  return note.isEmpty ? null : note;
}

class CreatePaymentAttemptCommand {
  const CreatePaymentAttemptCommand({
    required this.idempotencyKey,
    required this.paymentMethod,
    required this.simulatedOutcome,
  });

  final String idempotencyKey;
  final String paymentMethod;
  final String simulatedOutcome;

  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'paymentMethod': paymentMethod,
            'simulatedOutcome': simulatedOutcome,
          }),
        ),
      )
      .toString();

  factory CreatePaymentAttemptCommand.parse(Object? input) {
    if (input is! Map<String, dynamic> ||
        !_hasExactlyKeys(input, {
          'idempotencyKey',
          'paymentMethod',
          'simulatedOutcome',
        })) {
      throw const BookingPurchaseRequestException(
        'Provide only idempotencyKey, paymentMethod, and simulatedOutcome.',
      );
    }
    final key = input['idempotencyKey'];
    final method = input['paymentMethod'];
    final outcome = input['simulatedOutcome'];
    if (key is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(key) ||
        method is! String ||
        !const {'CreditDebitCard', 'PayPal', 'EFT'}.contains(method) ||
        outcome is! String ||
        !const {'success', 'failure'}.contains(outcome)) {
      throw const BookingPurchaseRequestException(
        'Provide a valid idempotencyKey, paymentMethod, and simulatedOutcome.',
      );
    }
    return CreatePaymentAttemptCommand(
      idempotencyKey: key,
      paymentMethod: method,
      simulatedOutcome: outcome,
    );
  }
}

class PaymentAttemptReceipt {
  const PaymentAttemptReceipt({
    required this.paymentAttemptId,
    required this.attemptNumber,
    required this.paymentStatus,
    required this.purchaseStatus,
    required this.replayed,
    required this.settled,
  });

  final int paymentAttemptId;
  final int attemptNumber;
  final String paymentStatus;
  final String purchaseStatus;
  final bool replayed;
  final bool settled;

  Map<String, Object> toJson() => {
    'paymentAttemptId': paymentAttemptId,
    'attemptNumber': attemptNumber,
    'paymentStatus': paymentStatus,
    'purchaseStatus': purchaseStatus,
    'replayed': replayed,
    'settled': settled,
  };
}

class PurchaseLessonReceipt {
  const PurchaseLessonReceipt({
    required this.bookingId,
    required this.lessonNumber,
    required this.lesson,
    required this.holdStatus,
  });

  final int bookingId;
  final int lessonNumber;
  final PurchaseLesson lesson;
  final String holdStatus;

  Map<String, Object> toJson() => {
    'bookingId': bookingId,
    'lessonNumber': lessonNumber,
    'date': lesson.date.iso,
    'startTime': lesson.startTime,
    'endTime': lesson.endTime,
    'holdStatus': holdStatus,
  };
}

class BookingPurchaseReceipt {
  const BookingPurchaseReceipt({
    required this.purchaseId,
    required this.purchaseStatus,
    required this.holdExpiresAtUtc,
    required this.tutorId,
    required this.subjectId,
    required this.rate,
    required this.lessonCount,
    required this.subtotal,
    required this.discountPercent,
    required this.discount,
    required this.total,
    required this.lessons,
    required this.replayed,
  });

  final int purchaseId;
  final String purchaseStatus;
  final DateTime holdExpiresAtUtc;
  final int tutorId;
  final int subjectId;
  final String rate;
  final int lessonCount;
  final String subtotal;
  final int discountPercent;
  final String discount;
  final String total;
  final List<PurchaseLessonReceipt> lessons;
  final bool replayed;

  Map<String, Object> toJson() => {
    'purchaseId': purchaseId,
    'purchaseStatus': purchaseStatus,
    'holdExpiresAt': holdExpiresAtUtc.toUtc().toIso8601String(),
    'timeZone': 'Africa/Johannesburg',
    'tutorId': tutorId,
    'subjectId': subjectId,
    'baseRatePerLesson': rate,
    'lessonCount': lessonCount,
    'subtotal': subtotal,
    'discountPercent': discountPercent,
    'discountAmount': discount,
    'totalAmount': total,
    'paymentOccurred': false,
    'lessonsConfirmed': false,
    'lessons': [for (final lesson in lessons) lesson.toJson()],
  };
}

abstract interface class BookingPurchaseRepository {
  Future<BookingPurchaseReceipt> create(
    int studentId,
    CreateBookingPurchaseCommand command,
  );

  Future<PaymentAttemptReceipt> createPaymentAttempt(
    int studentId,
    int purchaseId,
    CreatePaymentAttemptCommand command,
  );
}

int? _positiveId(Object? value) =>
    value is int && value > 0 && value <= 2147483647 ? value : null;

bool _hasExactlyKeys(Map<String, dynamic> map, Set<String> keys) =>
    map.length == keys.length && map.keys.toSet().containsAll(keys);

PurchaseLesson _parseManualLesson(
  Object? input, {
  required DateTime nowUtc,
}) {
  if (input is! Map<String, dynamic> ||
      !_hasExactlyKeys(input, {'date', 'startTime', 'endTime'})) {
    throw const BookingPurchaseRequestException(
      'Each manual lesson must contain date, startTime, and endTime.',
    );
  }
  final date = _parseDate(input['date']);
  final start = _parseTime(input['startTime']);
  final end = _parseTime(input['endTime']);
  final lesson = PurchaseLesson(
    date: date,
    startMinutes: start,
    endMinutes: end,
  );
  validateLessonTiming(slot: lesson.interval, nowUtc: nowUtc);
  return lesson;
}

BookingDate _parseDate(Object? value) {
  if (value is! String) {
    throw const BookingPurchaseRequestException(
      'Lesson dates must be strings.',
    );
  }
  try {
    return BookingDate.parse(value);
  } on FormatException {
    throw const BookingPurchaseRequestException(
      'Lesson dates must be valid YYYY-MM-DD calendar dates.',
    );
  }
}

int _parseTime(Object? value) {
  if (value is! String) {
    throw const BookingPurchaseRequestException(
      'Lesson times must be strings.',
    );
  }
  try {
    return parseClockTime(value);
  } on FormatException {
    throw const BookingPurchaseRequestException(
      'Lesson times must use valid whole-minute HH:mm values.',
    );
  }
}
