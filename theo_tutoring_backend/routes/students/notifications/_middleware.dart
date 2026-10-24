import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/student_notifications.dart';

NotificationStore? _store; // shared, so the Google access token is reused

// Runs before every /students/notifications route: checks the Firebase ID
// token belongs to an active student, then gives the route the student and
// the Firestore store, and turns Firestore problems into JSON errors.
//
// Opening the bell (GET the list or the unread count) first adds any lesson
// reminders the student has not been given yet.
Handler middleware(Handler handler) {
  return (context) async {
    final StudentSession? student;
    try {
      final identity = await verifyFirebaseToken(
        context.request.headers['authorization'] ??
            context.request.headers['Authorization'],
      );
      student = await findActiveStudent(await getConnection(), identity.uid);
    } on AuthTokenException catch (e) {
      return Response.json(statusCode: 401, body: {'error': e.message});
    } catch (e) {
      stderr.writeln('Student notification sign-in failed: $e');
      return Response.json(
        statusCode: 503,
        body: {'error': 'Authentication service is temporarily unavailable.'},
      );
    }
    if (student == null) {
      return Response.json(
        statusCode: 403,
        body: {'error': 'An active student account is required.'},
      );
    }

    try {
      final store = _store ??= NotificationStore.fromFirebaseAdmin();
      if (context.request.method == HttpMethod.get) {
        await _sync(store, student);
      }
      return await handler(
        context
            .provide<StudentSession>(() => student!)
            .provide<NotificationStore>(() => store),
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

// The existing notifications can still be shown if this fails, so it is
// only logged.
Future<void> _sync(NotificationStore store, StudentSession student) async {
  try {
    await syncStudentNotifications(await getConnection(), store, student);
  } catch (e) {
    stderr.writeln(
      'Could not add reminders for student ${student.studentId}: $e',
    );
  }
}
