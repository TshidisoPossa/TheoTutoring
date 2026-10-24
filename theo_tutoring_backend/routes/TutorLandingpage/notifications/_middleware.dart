import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/tutor_notifications.dart';
// Relative, like the TutorLandingpage middleware that provides it: a
// package: import would be a different TutorSession type to Dart.
import '../../../lib/tutorlanding_session.dart';

NotificationStore? _store; // shared, so the Google access token is reused

// Runs after the TutorLandingpage middleware (so the tutor is already signed
// in): gives every notification route the Firestore store and turns
// Firestore problems into JSON errors.
//
// Opening the bell (GET the list or the unread count) first adds any lesson
// reminders and reviews the tutor has not been told about yet, so they are
// already in the list and the badge.
Handler middleware(Handler handler) {
  return (context) async {
    try {
      final store = _store ??= NotificationStore.fromFirebaseAdmin();
      if (context.request.method == HttpMethod.get) {
        await _sync(store, context.read<TutorSession>());
      }
      return await handler(context.provide<NotificationStore>(() => store));
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

// The existing notifications can still be shown if this fails, so it is
// only logged.
Future<void> _sync(NotificationStore store, TutorSession tutor) async {
  try {
    await syncTutorNotifications(
      await getConnection(),
      store,
      tutorUid: tutor.userId,
      tutorId: tutor.tutorId,
    );
  } catch (e) {
    stderr.writeln('Could not add reminders for tutor ${tutor.tutorId}: $e');
  }
}
