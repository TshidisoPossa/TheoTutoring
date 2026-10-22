import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_purchase.dart';
import 'package:theo_tutoring_backend/demo_payment_config.dart';

import '../../../routes/StudentlandingPage/booking-purchases/[purchaseId]/payment-attempts.dart'
    as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _FakePaymentRepository implements BookingPurchaseRepository {
  _FakePaymentRepository({
    List<String>? bookingStatuses,
    this.lessonCount = 1,
    this.bookingCount = 1,
    this.holdCount = 1,
    this.bookingHoldLinksMatch = true,
    List<String>? unrelatedBookingStatuses,
  }) : bookingStatuses = bookingStatuses ?? ['Pending'],
       unrelatedBookingStatuses = unrelatedBookingStatuses ?? [];

  final attempts =
      <
        String,
        ({String method, String outcome, PaymentAttemptReceipt receipt})
      >{};
  bool holdsValid = true;
  String purchaseStatus = 'Held';
  final List<String> bookingStatuses;
  final int lessonCount;
  final int bookingCount;
  final int holdCount;
  final bool bookingHoldLinksMatch;
  final List<String> unrelatedBookingStatuses;
  int _nextAttemptId = 1;

  void _expirePurchase() {
    purchaseStatus = 'Expired';
    for (var index = 0; index < bookingStatuses.length; index++) {
      if (bookingStatuses[index] == 'Pending') {
        bookingStatuses[index] = 'Cancelled';
      }
    }
  }

  bool get _hasCompleteActiveHoldSet =>
      holdsValid &&
      bookingHoldLinksMatch &&
      bookingCount == lessonCount &&
      holdCount == lessonCount &&
      bookingStatuses.length == bookingCount &&
      bookingStatuses.every((status) => status == 'Pending');

  BookingPurchaseConflict _expireForInvalidSet() {
    final expired = !holdsValid;
    _expirePurchase();
    return BookingPurchaseConflict(
      expired ? 'hold_expired' : 'incomplete_hold_set',
      expired
          ? 'One or more lesson holds have expired.'
          : 'The purchase does not have all required lesson holds.',
    );
  }

  @override
  Future<BookingPurchaseReceipt> create(
    int studentId,
    CreateBookingPurchaseCommand command,
  ) => throw UnimplementedError();

  @override
  Future<PaymentAttemptReceipt> createPaymentAttempt(
    int studentId,
    int purchaseId,
    CreatePaymentAttemptCommand command,
  ) async {
    final old = attempts[command.idempotencyKey];
    if (old != null) {
      if (old.method != command.paymentMethod ||
          old.outcome != command.simulatedOutcome) {
        throw const BookingPurchaseConflict(
          'idempotency_key_reused',
          'The idempotency key was already used for a different request.',
        );
      }
      if (purchaseStatus == 'Held' && !_hasCompleteActiveHoldSet) {
        throw _expireForInvalidSet();
      }
      return PaymentAttemptReceipt(
        paymentAttemptId: old.receipt.paymentAttemptId,
        attemptNumber: old.receipt.attemptNumber,
        paymentStatus: old.receipt.paymentStatus,
        purchaseStatus: purchaseStatus,
        replayed: true,
        settled: old.receipt.settled,
      );
    }
    if (!_hasCompleteActiveHoldSet ||
        bookingStatuses.any((status) => status != 'Pending')) {
      throw _expireForInvalidSet();
    }
    if (purchaseStatus != 'Held' ||
        attempts.values.any((item) => item.receipt.paymentStatus != 'Failed')) {
      throw const BookingPurchaseConflict(
        'purchase_not_payable',
        'This purchase is no longer available for payment.',
      );
    }
    final succeeded = command.simulatedOutcome == 'success';
    final receipt = PaymentAttemptReceipt(
      paymentAttemptId: _nextAttemptId++,
      attemptNumber: attempts.length + 1,
      paymentStatus: succeeded ? 'Successful' : 'Failed',
      purchaseStatus: succeeded ? 'Paid' : 'Held',
      replayed: false,
      settled: succeeded,
    );
    if (succeeded) purchaseStatus = 'Paid';
    attempts[command.idempotencyKey] = (
      method: command.paymentMethod,
      outcome: command.simulatedOutcome,
      receipt: receipt,
    );
    return receipt;
  }
}

void main() {
  late RequestContext context;
  late Request request;
  final enabled = DemoPaymentConfig.fromSources(
    processEnvironment: const {'APP_ENV': 'development'},
    enabledValue: 'true',
  );
  final disabled = DemoPaymentConfig.fromSources(
    processEnvironment: const {'APP_ENV': 'production'},
    enabledValue: 'true',
  );

  Map<String, Object?> body({
    String key = 'payment-1',
    String outcome = 'success',
    String method = 'CreditDebitCard',
  }) => {
    'idempotencyKey': key,
    'paymentMethod': method,
    'simulatedOutcome': outcome,
  };

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.post);
    when(() => request.uri).thenReturn(
      Uri.parse('/StudentlandingPage/booking-purchases/27/payment-attempts'),
    );
    when(() => request.headers).thenReturn({'Authorization': '******'});
    when(() => request.json()).thenAnswer((_) async => body());
  });

  Future<Response> submit(
    _FakePaymentRepository repository, {
    required DemoPaymentConfig config,
  }) => route.handleCreatePaymentAttempt(
    context,
    repositoryFactory: () async => repository,
    studentIdResolver: (_) async => 19,
    paymentConfig: config,
  );

  test(
    'rejects payments when disabled, including production with flag true',
    () async {
      final response = await route.handleCreatePaymentAttempt(
        context,
        paymentConfig: disabled,
      );
      expect(response.statusCode, HttpStatus.forbidden);
      verifyNever(() => request.json());
    },
  );

  test('uses the Dart Frog [purchaseId] route parameter', () async {
    final repository = _FakePaymentRepository();
    final ok = await route.handleCreatePaymentAttempt(
      context,
      routePurchaseId: '27',
      repositoryFactory: () async => repository,
      studentIdResolver: (_) async => 19,
      paymentConfig: enabled,
    );
    expect(ok.statusCode, HttpStatus.created);

    // The route parameter wins over whatever the raw URI contains.
    when(() => request.uri).thenReturn(
      Uri.parse('/StudentlandingPage/booking-purchases/not-a-number/payment-attempts'),
    );
    final precedence = await route.handleCreatePaymentAttempt(
      context,
      routePurchaseId: '27',
      repositoryFactory: () async => _FakePaymentRepository(),
      studentIdResolver: (_) async => 19,
      paymentConfig: enabled,
    );
    expect(precedence.statusCode, HttpStatus.created);

    for (final bad in ['abc', '0', '-3']) {
      final rejected = await route.handleCreatePaymentAttempt(
        context,
        routePurchaseId: bad,
        paymentConfig: enabled,
      );
      expect(rejected.statusCode, HttpStatus.badRequest, reason: bad);
    }
  });

  test('creates an attempt and replays the same key and payload', () async {
    final repository = _FakePaymentRepository();
    final first = await submit(repository, config: enabled);
    final firstBody = jsonDecode(await first.body()) as Map<String, dynamic>;
    expect(first.statusCode, HttpStatus.created);
    expect(firstBody['paymentStatus'], 'Successful');
    expect(firstBody['purchaseStatus'], 'Paid');
    expect(firstBody['settled'], isTrue);

    final replay = await submit(repository, config: enabled);
    final replayBody = jsonDecode(await replay.body()) as Map<String, dynamic>;
    expect(replay.statusCode, HttpStatus.ok);
    expect(replayBody['replayed'], isTrue);
    expect(repository.attempts, hasLength(1));
  });

  test(
    'rejects changed payload and permits new-key retry after failure',
    () async {
      final repository = _FakePaymentRepository();
      when(() => request.json()).thenAnswer(
        (_) async => body(key: 'failed-key', outcome: 'failure'),
      );
      final failed = await submit(repository, config: enabled);
      expect(failed.statusCode, HttpStatus.created);

      when(() => request.json()).thenAnswer(
        (_) async => body(key: 'failed-key', outcome: 'success'),
      );
      final changed = await submit(repository, config: enabled);
      expect(changed.statusCode, HttpStatus.conflict);

      when(() => request.json()).thenAnswer(
        (_) async => body(key: 'retry-key', outcome: 'success'),
      );
      final retried = await submit(repository, config: enabled);
      final result = jsonDecode(await retried.body()) as Map<String, dynamic>;
      expect(retried.statusCode, HttpStatus.created);
      expect(result['attemptNumber'], 2);
      expect(result['settled'], isTrue);
    },
  );

  test('failed-attempt replay reconciles newly expired holds', () async {
    final repository = _FakePaymentRepository();
    when(() => request.json()).thenAnswer(
      (_) async => body(key: 'failed-key', outcome: 'failure'),
    );
    final failed = await submit(repository, config: enabled);
    expect(failed.statusCode, HttpStatus.created);

    repository.holdsValid = false;
    final replay = await submit(repository, config: enabled);
    expect(replay.statusCode, HttpStatus.conflict);
    expect(repository.purchaseStatus, 'Expired');
    expect(repository.bookingStatuses, ['Cancelled']);
  });

  test(
    'missing holds expire the purchase and cancel its pending bookings',
    () async {
      final repository = _FakePaymentRepository(holdCount: 0);
      final response = await submit(repository, config: enabled);
      expect(response.statusCode, HttpStatus.conflict);
      expect(repository.attempts, isEmpty);
      expect(repository.purchaseStatus, 'Expired');
      expect(repository.bookingStatuses, ['Cancelled']);
    },
  );

  test('mismatched booking and hold counts reconcile expiry', () async {
    final repository = _FakePaymentRepository(
      lessonCount: 2,
      bookingStatuses: ['Pending', 'Pending'],
      bookingCount: 2,
      holdCount: 1,
    );
    final response = await submit(repository, config: enabled);
    expect(response.statusCode, HttpStatus.conflict);
    expect(repository.purchaseStatus, 'Expired');
    expect(repository.bookingStatuses, ['Cancelled', 'Cancelled']);
  });

  test(
    'incomplete linked set preserves confirmed and unrelated bookings',
    () async {
      final repository = _FakePaymentRepository(
        bookingStatuses: ['Confirmed', 'Pending'],
        bookingCount: 2,
        holdCount: 2,
        bookingHoldLinksMatch: false,
        unrelatedBookingStatuses: ['Pending', 'Confirmed'],
      );
      final response = await submit(repository, config: enabled);
      expect(response.statusCode, HttpStatus.conflict);
      expect(repository.purchaseStatus, 'Expired');
      expect(repository.bookingStatuses, ['Confirmed', 'Cancelled']);
      expect(repository.unrelatedBookingStatuses, ['Pending', 'Confirmed']);
    },
  );
}
