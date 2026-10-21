import 'dart:io';

import 'env.dart';

class DemoPaymentConfig {
  const DemoPaymentConfig._({
    required this.applicationEnvironment,
    required this.enabledValue,
  });

  factory DemoPaymentConfig.current() => DemoPaymentConfig._(
    applicationEnvironment: Platform.environment['APP_ENV'],
    enabledValue: env['DEMO_PAYMENTS_ENABLED'],
  );

  factory DemoPaymentConfig.fromSources({
    required Map<String, String> processEnvironment,
    required String? enabledValue,
  }) => DemoPaymentConfig._(
    applicationEnvironment: processEnvironment['APP_ENV'],
    enabledValue: enabledValue,
  );

  final String? applicationEnvironment;
  final String? enabledValue;

  bool get isEnabled {
    if (applicationEnvironment != 'development' &&
        applicationEnvironment != 'test') {
      return false;
    }
    return enabledValue == 'true';
  }
}
