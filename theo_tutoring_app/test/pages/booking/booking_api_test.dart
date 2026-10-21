import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Booking/booking_api.dart';

void main() {
  test(
    'payment request uses backend contract and authenticated purchase route',
    () async {
      late http.Request request;
      final client = MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode({
            'paymentAttemptId': 91,
            'attemptNumber': 1,
            'paymentStatus': 'Successful',
            'purchaseStatus': 'Paid',
            'replayed': false,
            'settled': true,
          }),
          201,
        );
      });
      final api = HttpBookingFlowApi(
        client: client,
        tokenProvider: () async => 'test-token',
      );

      final result = await api.createPaymentAttempt(
        purchaseId: 42,
        idempotencyKey: 'demo-payment-stable-key',
        paymentMethod: 'CreditDebitCard',
        simulatedOutcome: 'success',
      );

      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/students/booking-purchases/42/payment-attempts',
      );
      expect(request.headers['authorization'], 'Bearer test-token');
      expect(jsonDecode(request.body), {
        'idempotencyKey': 'demo-payment-stable-key',
        'paymentMethod': 'CreditDebitCard',
        'simulatedOutcome': 'success',
      });
      expect(result.isSuccessful, isTrue);
      api.close();
    },
  );

  test('every request sends the retrieved token without logging it', () async {
    const token = 'eyJ.actual-id-token.sig';
    final auths = <String?>[];
    final client = MockClient((incoming) async {
      auths.add(incoming.headers['authorization']);
      if (incoming.method == 'GET') return http.Response('{"slots":[]}', 200);
      return http.Response('{}', 500);
    });
    final api = HttpBookingFlowApi(
      client: client,
      tokenProvider: () async => token,
    );
    final logs = <String?>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message);
    try {
      await runZoned(
        () async {
          try {
            await api.availability(
              tutorId: 1,
              subjectId: 2,
              from: '2026-01-01',
              through: '2026-01-07',
            );
          } catch (_) {}
          try {
            await api.createPaymentAttempt(
              purchaseId: 1,
              idempotencyKey: 'k',
              paymentMethod: 'EFT',
              simulatedOutcome: 'success',
            );
          } catch (_) {}
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => logs.add(line),
        ),
      );
    } finally {
      debugPrint = original;
    }

    expect(auths, isNotEmpty);
    for (final auth in auths) {
      expect(auth, 'Bearer $token');
      expect(auth, isNot(contains('*')));
    }
    expect(logs.where((l) => l?.contains(token) ?? false), isEmpty);
    api.close();
  });

  test('payment errors preserve backend status and conflict code', () async {
    final api = HttpBookingFlowApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'One or more lesson holds have expired.',
            'code': 'hold_expired',
          }),
          409,
        ),
      ),
      tokenProvider: () async => 'test-token',
    );

    await expectLater(
      api.createPaymentAttempt(
        purchaseId: 42,
        idempotencyKey: 'demo-payment-key',
        paymentMethod: 'EFT',
        simulatedOutcome: 'success',
      ),
      throwsA(
        isA<BookingApiException>()
            .having((error) => error.message, 'message', contains('expired'))
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'hold_expired'),
      ),
    );
    api.close();
  });

  test('inconsistent success receipt cannot be treated as confirmation', () {
    expect(
      () => PaymentAttemptResult.fromJson({
        'paymentAttemptId': 91,
        'attemptNumber': 1,
        'paymentStatus': 'Successful',
        'purchaseStatus': 'Held',
        'replayed': false,
        'settled': false,
      }),
      throwsFormatException,
    );
  });
}
