import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/notifications.dart';

NotificationStore? _store; // shared, so the Google access token is reused

// Runs after the TutorLandingpage middleware (so the tutor is already signed
// in): gives the booking routes the Firestore store, so postponing a session
// can notify the student. The store is only built when a route reads it.
Handler middleware(Handler handler) {
  return handler.use(
    provider<NotificationStore>(
      (_) => _store ??= NotificationStore.fromFirebaseAdmin(),
    ),
  );
}
