import 'dart:async';

import 'tutor_api.dart';

/// Keeps the signed-in tutor "Available Now" for students while the app is
/// open: pings the backend every minute, and clears it on sign-out.
/// Started by the tutor dashboard (every tutor lands there after login).
class TutorPresence {
  TutorPresence._();

  static final TutorPresence instance = TutorPresence._();

  /// Must stay under the backend's 3-minute window (lib/tutor_presence.dart).
  static const interval = Duration(minutes: 1);

  Timer? _timer;

  bool get isRunning => _timer != null;

  /// Starts pinging; does nothing if it is already running.
  void start() {
    if (_timer != null) return;
    unawaited(_ping());
    _timer = Timer.periodic(interval, (_) => unawaited(_ping()));
  }

  /// Stops pinging and shows the tutor offline. Call before signing out,
  /// while the Firebase token is still valid.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    try {
      await clearTutorPresence();
    } catch (_) {
      // Offline anyway once the pings stop (after 3 minutes).
    }
  }

  Future<void> _ping() async {
    try {
      await pingTutorPresence();
    } catch (_) {
      // A missed ping only matters if the next ones fail too.
    }
  }
}
