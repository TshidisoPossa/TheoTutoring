import 'dart:io';

import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/notifications.dart'; // NotificationStore

NotificationStore? _store; // shared, so the Google access token is reused

// Runs after the TutorLandingpage middleware (so the tutor is already signed
// in): gives every notification route the Firestore store and turns
// Firestore problems into JSON errors.
Handler middleware(Handler handler) {
  return (context) async {
    try {
      return await handler(
        context.provide<NotificationStore>(
          () => _store ??= NotificationStore.fromFirebaseAdmin(),
        ),
      );
    } on FirebaseAdminException catch (e) {
      stderr.writeln(e); // missing or bad service account key
      return Response.json(
        statusCode: 500,
        body: {'error': 'Notifications are not configured on the server.'},
      );
    } on NotificationServiceException catch (e) {
      stderr.writeln(e); // Firestore down or rejected the request
      return Response.json(
        statusCode: 503,
        body: {'error': 'Notifications are temporarily unavailable.'},
      );
    }
  };
}
