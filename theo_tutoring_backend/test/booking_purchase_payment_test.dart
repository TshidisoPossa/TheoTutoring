import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_purchase.dart';
import 'package:theo_tutoring_backend/demo_payment_config.dart';

void main() {
  DemoPaymentConfig config(String? appEnv, String? flag) =>
      DemoPaymentConfig.fromSources(
        processEnvironment: {if (appEnv != null) 'APP_ENV': appEnv},
        enabledValue: flag,
      );

  test('demo payment configuration fails closed', () {
    expect(config('production', 'true').isEnabled, isFalse);
    expect(config(null, 'true').isEnabled, isFalse);
    expect(config('staging', 'true').isEnabled, isFalse);
    expect(config('development', null).isEnabled, isFalse);
    expect(config('test', 'yes').isEnabled, isFalse);
    expect(config('development', 'true').isEnabled, isTrue);
    expect(config('test', 'TRUE').isEnabled, isFalse);
    expect(config(' Development', 'true').isEnabled, isFalse);
  });

  test('payment request accepts only the documented fields and values', () {
    final command = CreatePaymentAttemptCommand.parse({
      'idempotencyKey': 'pay-1',
      'paymentMethod': 'PayPal',
      'simulatedOutcome': 'success',
    });
    expect(command.paymentMethod, 'PayPal');
    expect(command.fingerprint, isNotEmpty);
    expect(
      () => CreatePaymentAttemptCommand.parse({
        'idempotencyKey': 'pay-1',
        'paymentMethod': 'PayPal',
        'simulatedOutcome': 'success',
        'amount': 1,
      }),
      throwsA(isA<BookingPurchaseRequestException>()),
    );
    expect(
      () => CreatePaymentAttemptCommand.parse({
        'idempotencyKey': 'pay-1',
        'paymentMethod': 'PayPal',
        'simulatedOutcome': 'success',
        'studentId': 19,
      }),
      throwsA(isA<BookingPurchaseRequestException>()),
    );
    expect(
      () => CreatePaymentAttemptCommand.parse({
        'idempotencyKey': 'pay-1',
        'paymentMethod': 'PayPal',
        'simulatedOutcome': 'unknown',
      }),
      throwsA(isA<BookingPurchaseRequestException>()),
    );
  });
}
