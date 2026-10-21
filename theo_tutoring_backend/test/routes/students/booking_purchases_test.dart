import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/booking_purchase.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/students/booking-purchases/index.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _HeldSlot {
  _HeldSlot({
    required this.studentId,
    required this.tutorId,
    required this.lesson,
    required this.expiresAtUtc,
    required this.purchaseId,
    required this.lessonNumber,
    required this.status,
  }) : bookingStatus = 'Pending';

  final int studentId;
  final int tutorId;
  final PurchaseLesson lesson;
  DateTime expiresAtUtc;
  final int purchaseId;
  final int lessonNumber;
  String status;
  String bookingStatus;
}

class _FakeRepository implements BookingPurchaseRepository {
  _FakeRepository({this.failOnLessonNumber});

  final int? failOnLessonNumber;
  DateTime nowUtc = DateTime.utc(2026, 10, 19, 0, 52);
  final records = <_HeldSlot>[];
  final purchases = <String, (String fingerprint, BookingPurchaseReceipt)>{};
  Future<void> _queue = Future<void>.value();
  int purchaseCount = 0;
  int _nextPurchaseId = 1;

  @override
  Future<BookingPurchaseReceipt> create(
    int studentId,
    CreateBookingPurchaseCommand command,
  ) async {
    final previous = _queue;
    final gate = Completer<void>();
    _queue = gate.future;
    await previous;
    try {
      final key = '$studentId:${command.idempotencyKey}';
      final existing = purchases[key];
      if (existing != null) {
        if (existing.$1 != command.fingerprint) {
          throw const BookingPurchaseConflict(
            'idempotency_key_reused',
            'The idempotency key was already used for a different request.',
          );
        }
        var old = existing.$2;
        if (old.purchaseStatus == 'Held') {
          final purchaseRecords = records
              .where((record) => record.purchaseId == old.purchaseId)
              .toList();
          final validLessonNumbers = {
            for (final record in purchaseRecords)
              if (record.status == 'Active' &&
                  record.expiresAtUtc.isAfter(nowUtc))
                record.lessonNumber,
          };
          final allLessonsHeld =
              validLessonNumbers.length == old.lessonCount &&
              List<bool>.generate(
                old.lessonCount,
                (index) => validLessonNumbers.contains(index + 1),
              ).every((isHeld) => isHeld);
          if (!allLessonsHeld) {
            for (final record in purchaseRecords) {
              if (record.status == 'Active') {
                record.status = record.expiresAtUtc.isAfter(nowUtc)
                    ? 'Released'
                    : 'Expired';
              }
              if (record.bookingStatus == 'Pending') {
                record.bookingStatus = 'Cancelled';
              }
            }
            String statusForLesson(int lessonNumber) {
              for (final record in purchaseRecords) {
                if (record.lessonNumber == lessonNumber) return record.status;
              }
              return 'Missing';
            }

            old = BookingPurchaseReceipt(
              purchaseId: old.purchaseId,
              purchaseStatus: 'Expired',
              holdExpiresAtUtc: old.holdExpiresAtUtc,
              tutorId: old.tutorId,
              subjectId: old.subjectId,
              rate: old.rate,
              lessonCount: old.lessonCount,
              subtotal: old.subtotal,
              discountPercent: old.discountPercent,
              discount: old.discount,
              total: old.total,
              lessons: [
                for (final lesson in old.lessons)
                  PurchaseLessonReceipt(
                    bookingId: lesson.bookingId,
                    lessonNumber: lesson.lessonNumber,
                    lesson: lesson.lesson,
                    holdStatus: statusForLesson(lesson.lessonNumber),
                  ),
              ],
              replayed: false,
            );
            purchases[key] = (existing.$1, old);
          }
        }
        return BookingPurchaseReceipt(
          purchaseId: old.purchaseId,
          purchaseStatus: old.purchaseStatus,
          holdExpiresAtUtc: old.holdExpiresAtUtc,
          tutorId: old.tutorId,
          subjectId: old.subjectId,
          rate: old.rate,
          lessonCount: old.lessonCount,
          subtotal: old.subtotal,
          discountPercent: old.discountPercent,
          discount: old.discount,
          total: old.total,
          lessons: old.lessons,
          replayed: true,
        );
      }

      const window = WeeklyAvailability(
        weekday: DateTime.monday,
        startMinutes: 4 * 60,
        endMinutes: 10 * 60,
      );
      for (final lesson in command.lessons) {
        validateLessonSlot(
          slot: lesson.interval,
          nowUtc: nowUtc,
          availability: [window],
        );
        final conflict = records.any((record) {
          return record.lesson.interval.overlaps(lesson.interval) &&
              (record.tutorId == command.tutorId ||
                  record.studentId == studentId) &&
              (record.status == 'Confirmed' ||
                  (record.status == 'Active' &&
                      record.expiresAtUtc.isAfter(nowUtc)));
        });
        if (conflict) throw const BookingPurchaseUnavailable();
      }

      if (failOnLessonNumber != null &&
          failOnLessonNumber! <= command.lessons.length) {
        throw const BookingPurchaseServiceUnavailable();
      }

      final price = calculateBookingPrice(
        platformRate: '99.99',
        purchaseType: command.purchaseType,
        lessonCount: command.lessons.length,
      );
      final purchaseId = _nextPurchaseId++;
      final expires = nowUtc.add(const Duration(minutes: 10));
      final receipt = BookingPurchaseReceipt(
        purchaseId: purchaseId,
        purchaseStatus: 'Held',
        holdExpiresAtUtc: expires,
        tutorId: command.tutorId,
        subjectId: command.subjectId,
        rate: price.rate,
        lessonCount: command.lessons.length,
        subtotal: price.subtotal,
        discountPercent: price.discountPercent,
        discount: price.discount,
        total: price.total,
        lessons: [
          for (var index = 0; index < command.lessons.length; index++)
            PurchaseLessonReceipt(
              bookingId: purchaseId * 100 + index,
              lessonNumber: index + 1,
              lesson: command.lessons[index],
              holdStatus: 'Active',
            ),
        ],
        replayed: false,
      );
      final staged = [
        for (var index = 0; index < command.lessons.length; index++)
          _HeldSlot(
            studentId: studentId,
            tutorId: command.tutorId,
            lesson: command.lessons[index],
            expiresAtUtc: expires,
            purchaseId: purchaseId,
            lessonNumber: index + 1,
            status: 'Active',
          ),
      ];
      records.addAll(staged);
      purchases[key] = (command.fingerprint, receipt);
      purchaseCount++;
      return receipt;
    } finally {
      gate.complete();
    }
  }

  @override
  Future<PaymentAttemptReceipt> createPaymentAttempt(
    int studentId,
    int purchaseId,
    CreatePaymentAttemptCommand command,
  ) => throw UnimplementedError('Payment attempts are tested separately.');
}

void main() {
  const now = '2026-10-19T00:52:00Z';
  final nowUtc = DateTime.parse(now);
  late RequestContext context;
  late Request request;

  Map<String, Object?> singleBody({String key = 'request-1'}) => {
    'tutorId': 6,
    'subjectId': 12,
    'purchaseType': 'Single',
    'schedulingMode': 'manual',
    'idempotencyKey': key,
    'lessons': [
      {'date': '2026-10-19', 'startTime': '05:00', 'endTime': '06:00'},
    ],
  };

  Map<String, Object?> packageBody() => {
    'tutorId': 6,
    'subjectId': 12,
    'purchaseType': 'Package',
    'schedulingMode': 'manual',
    'idempotencyKey': 'package-key',
    'lessons': [
      {'date': '2026-10-19', 'startTime': '05:00', 'endTime': '06:00'},
      {'date': '2026-10-19', 'startTime': '06:00', 'endTime': '07:00'},
    ],
  };

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.post);
    when(() => request.headers).thenReturn({'Authorization': 'Bearer test'});
    when(() => request.json()).thenAnswer((_) async => singleBody());
  });

  test(
    'creates single and manual package purchases with unpaid holds',
    () async {
      final singleRepository = _FakeRepository();
      final single = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => singleRepository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      expect(single.statusCode, HttpStatus.created);
      final singleJson =
          jsonDecode(await single.body()) as Map<String, dynamic>;
      expect(singleJson['purchaseStatus'], 'Held');
      expect(singleJson['paymentOccurred'], isFalse);
      expect(singleJson['lessonsConfirmed'], isFalse);
      expect(singleJson['holdExpiresAt'], endsWith('Z'));
      expect(singleJson['timeZone'], 'Africa/Johannesburg');
      expect(singleJson['lessons'], hasLength(1));

      when(() => request.json()).thenAnswer((_) async => packageBody());
      final package = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => _FakeRepository(),
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      final packageJson =
          jsonDecode(await package.body()) as Map<String, dynamic>;
      expect(package.statusCode, HttpStatus.created);
      expect(packageJson['lessonCount'], 2);
      expect(packageJson['lessons'], hasLength(2));
    },
  );

  test(
    'creates weekly recurring packages from server-generated dates',
    () async {
      when(() => request.json()).thenAnswer(
        (_) async => {
          'tutorId': 6,
          'subjectId': 12,
          'purchaseType': 'Package',
          'schedulingMode': 'weekly',
          'idempotencyKey': 'weekly-route-key',
          'recurrence': {
            'firstDate': '2026-10-19',
            'startTime': '05:00',
            'lessonCount': 2,
          },
        },
      );
      final response = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => _FakeRepository(),
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );

      expect(response.statusCode, HttpStatus.created);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      final lessons = body['lessons'] as List<dynamic>;
      expect((lessons.first as Map<String, dynamic>)['date'], '2026-10-19');
      expect((lessons.last as Map<String, dynamic>)['date'], '2026-10-26');
    },
  );

  test(
    'requires manual alternatives if a recurring slot is unavailable',
    () async {
      final repository = _FakeRepository();
      repository.records.add(
        _HeldSlot(
          studentId: 99,
          tutorId: 6,
          lesson: const PurchaseLesson(
            date: BookingDate(2026, 10, 26),
            startMinutes: 5 * 60,
            endMinutes: 6 * 60,
          ),
          expiresAtUtc: nowUtc.add(const Duration(minutes: 3)),
          purchaseId: 0,
          lessonNumber: 0,
          status: 'Active',
        ),
      );
      when(() => request.json()).thenAnswer(
        (_) async => {
          'tutorId': 6,
          'subjectId': 12,
          'purchaseType': 'Package',
          'schedulingMode': 'weekly',
          'idempotencyKey': 'weekly-conflict',
          'recurrence': {
            'firstDate': '2026-10-19',
            'startTime': '05:00',
            'lessonCount': 2,
          },
        },
      );

      final response = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(response.statusCode, HttpStatus.conflict);
      expect(body['code'], 'recurring_alternatives_required');
      expect(body['alternativesRequired'], isTrue);
      expect(repository.purchaseCount, 0);
    },
  );

  test('reports same-key retry and rejects conflicting key reuse', () async {
    final repository = _FakeRepository();
    Future<Response> submit(Object? body) async {
      when(() => request.json()).thenAnswer((_) async => body);
      return route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
    }

    final first = await submit(singleBody());
    final retry = await submit(singleBody());
    expect(first.statusCode, HttpStatus.created);
    expect(retry.statusCode, HttpStatus.ok);
    expect(repository.purchaseCount, 1);

    final changed = singleBody();
    changed['subjectId'] = 13;
    final conflict = await submit(changed);
    final body = jsonDecode(await conflict.body()) as Map<String, dynamic>;
    expect(conflict.statusCode, HttpStatus.conflict);
    expect(body['code'], 'idempotency_key_reused');
  });

  test(
    'same-key replay before expiry leaves purchase and holds active',
    () async {
      final repository = _FakeRepository();
      when(() => request.json()).thenAnswer((_) async => singleBody());

      final first = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      repository.nowUtc = nowUtc.add(const Duration(minutes: 9, seconds: 59));
      final retry = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );

      final body = jsonDecode(await retry.body()) as Map<String, dynamic>;
      expect(first.statusCode, HttpStatus.created);
      expect(retry.statusCode, HttpStatus.ok);
      expect(body['purchaseStatus'], 'Held');
      expect((body['lessons'] as List).single['holdStatus'], 'Active');
      expect(repository.records.single.status, 'Active');
      expect(repository.purchaseCount, 1);
    },
  );

  test(
    'same-key replay at expiry expires purchase and its holds once',
    () async {
      final repository = _FakeRepository();
      when(() => request.json()).thenAnswer((_) async => packageBody());

      final first = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      repository.nowUtc = nowUtc.add(const Duration(minutes: 10));
      final retry = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      final retryAgain = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );

      final body = jsonDecode(await retry.body()) as Map<String, dynamic>;
      expect(first.statusCode, HttpStatus.created);
      expect(retry.statusCode, HttpStatus.ok);
      expect(body['purchaseStatus'], 'Expired');
      expect(
        (body['lessons'] as List)
            .map((lesson) => (lesson as Map<String, dynamic>)['holdStatus'])
            .toSet(),
        {'Expired'},
      );
      expect(repository.records.map((record) => record.status).toSet(), {
        'Expired',
      });
      expect(
        repository.records.map((record) => record.bookingStatus).toSet(),
        {'Cancelled'},
      );
      expect(retryAgain.statusCode, HttpStatus.ok);
      expect(repository.purchaseCount, 1);
      expect(repository.records, hasLength(2));
    },
  );

  test('partial package expiry releases every remaining active hold', () async {
    final repository = _FakeRepository();
    when(() => request.json()).thenAnswer((_) async => packageBody());

    await route.handleCreateBookingPurchase(
      context,
      repositoryFactory: () async => repository,
      studentIdResolver: (_) async => 19,
      clock: () => nowUtc,
    );
    repository.nowUtc = nowUtc.add(const Duration(minutes: 10));
    repository.records.first.status = 'Expired';
    repository.records.last.expiresAtUtc = repository.nowUtc.add(
      const Duration(minutes: 1),
    );

    final retry = await route.handleCreateBookingPurchase(
      context,
      repositoryFactory: () async => repository,
      studentIdResolver: (_) async => 19,
      clock: () => nowUtc,
    );
    final body = jsonDecode(await retry.body()) as Map<String, dynamic>;

    expect(body['purchaseStatus'], 'Expired');
    expect(repository.records.map((record) => record.status).toSet(), {
      'Released',
      'Expired',
    });
    expect(repository.purchaseCount, 1);
  });

  test(
    'expiry cancels only pending bookings and preserves confirmed bookings',
    () async {
      final repository = _FakeRepository();
      when(() => request.json()).thenAnswer((_) async => packageBody());

      await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      final confirmedBooking = repository.records.first;
      confirmedBooking.bookingStatus = 'Confirmed';
      final pendingBooking = repository.records.last;
      final unrelatedBooking = _HeldSlot(
        studentId: 20,
        tutorId: 7,
        lesson: confirmedBooking.lesson,
        expiresAtUtc: nowUtc.add(const Duration(minutes: 10)),
        purchaseId: 999,
        lessonNumber: 1,
        status: 'Active',
      );
      repository.records.add(unrelatedBooking);
      repository.nowUtc = nowUtc.add(const Duration(minutes: 10));

      final retry = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );

      final body = jsonDecode(await retry.body()) as Map<String, dynamic>;
      expect(body['purchaseStatus'], 'Expired');
      expect(confirmedBooking.bookingStatus, 'Confirmed');
      expect(pendingBooking.bookingStatus, 'Cancelled');
      expect(unrelatedBooking.bookingStatus, 'Pending');
      expect(unrelatedBooking.status, 'Active');
    },
  );

  test(
    'missing package hold expires purchase and releases remaining holds',
    () async {
      final repository = _FakeRepository();
      when(() => request.json()).thenAnswer((_) async => packageBody());

      await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      repository.records.removeAt(1);

      final retry = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      final body = jsonDecode(await retry.body()) as Map<String, dynamic>;

      expect(body['purchaseStatus'], 'Expired');
      expect(body['lessons'].last['holdStatus'], 'Missing');
      expect(repository.records.single.status, 'Released');
      expect(repository.purchaseCount, 1);
    },
  );

  test('serializes concurrent duplicate-key submissions', () async {
    final repository = _FakeRepository();
    final responses = await Future.wait([
      route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      ),
      route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      ),
    ]);

    expect(responses.map((response) => response.statusCode).toSet(), {
      HttpStatus.created,
      HttpStatus.ok,
    });
    expect(repository.purchaseCount, 1);
  });

  test(
    'rejects concurrent tutor overlap and cross-tutor student overlap',
    () async {
      final repository = _FakeRepository();
      Future<Response> submit({
        required int studentId,
        required int tutorId,
        required String key,
      }) {
        final body = singleBody(key: key)..['tutorId'] = tutorId;
        when(() => request.json()).thenAnswer((_) async => body);
        return route.handleCreateBookingPurchase(
          context,
          repositoryFactory: () async => repository,
          studentIdResolver: (_) async => studentId,
          clock: () => nowUtc,
        );
      }

      final competing = await Future.wait([
        submit(studentId: 19, tutorId: 6, key: 'competing-a'),
        submit(studentId: 20, tutorId: 6, key: 'competing-b'),
      ]);
      expect(competing.map((response) => response.statusCode).toSet(), {
        HttpStatus.created,
        HttpStatus.conflict,
      });

      final otherTutor = await submit(
        studentId: 19,
        tutorId: 7,
        key: 'cross-tutor',
      );
      expect(otherTutor.statusCode, HttpStatus.conflict);
    },
  );

  test('accepts adjacent lessons and ignores expired holds', () async {
    final repository = _FakeRepository();
    repository.records.add(
      _HeldSlot(
        studentId: 19,
        tutorId: 99,
        lesson: const PurchaseLesson(
          date: BookingDate(2026, 10, 19),
          startMinutes: 5 * 60,
          endMinutes: 6 * 60,
        ),
        expiresAtUtc: nowUtc.subtract(const Duration(seconds: 1)),
        purchaseId: 0,
        lessonNumber: 0,
        status: 'Active',
      ),
    );
    when(() => request.json()).thenAnswer(
      (_) async => {
        ...packageBody(),
        'idempotencyKey': 'adjacent-key',
      },
    );

    final response = await route.handleCreateBookingPurchase(
      context,
      repositoryFactory: () async => repository,
      studentIdResolver: (_) async => 19,
      clock: () => nowUtc,
    );
    expect(response.statusCode, HttpStatus.created);
  });

  test(
    'rolls back a failed package without partial purchases or holds',
    () async {
      final repository = _FakeRepository(failOnLessonNumber: 2);
      when(() => request.json()).thenAnswer((_) async => packageBody());
      final response = await route.handleCreateBookingPurchase(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );
      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(repository.purchaseCount, 0);
      expect(repository.records, isEmpty);
    },
  );

  test('rejects invalid body, identity, and methods safely', () async {
    when(() => request.json()).thenAnswer(
      (_) async => {
        ...singleBody(),
        'studentId': 19,
        'price': '0.01',
      },
    );
    final malformed = await route.handleCreateBookingPurchase(context);
    expect(malformed.statusCode, HttpStatus.badRequest);

    when(() => request.json()).thenAnswer((_) async => singleBody());
    final unauthenticated = await route.handleCreateBookingPurchase(
      context,
      studentIdResolver: (_) =>
          throw const AuthTokenException('Invalid sign-in token.'),
      clock: () => nowUtc,
    );
    expect(unauthenticated.statusCode, HttpStatus.unauthorized);

    final forbidden = await route.handleCreateBookingPurchase(
      context,
      studentIdResolver: (_) => throw const route.PurchaseStudentException(
        HttpStatus.forbidden,
        'An active student account is required.',
      ),
      clock: () => nowUtc,
    );
    expect(forbidden.statusCode, HttpStatus.forbidden);

    when(() => request.method).thenReturn(HttpMethod.get);
    final wrongMethod = await route.handleCreateBookingPurchase(context);
    expect(wrongMethod.statusCode, HttpStatus.methodNotAllowed);
  });
}
