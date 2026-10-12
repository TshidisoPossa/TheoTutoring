import 'package:flutter/foundation.dart';

/// Base URL of the Dart Frog backend.
///
/// The Android emulator reaches the host PC through 10.0.2.2; everything else
/// (Chrome, Windows, iOS simulator) uses localhost. For a real phone, run with
/// `--dart-define=API_BASE_URL=http://YOUR-PC-IP:8080`
String get apiBaseUrl {
  const override = String.fromEnvironment('API_BASE_URL');
  if (override.isNotEmpty) return override;

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8080';
  }
  return 'http://localhost:8080';
}
