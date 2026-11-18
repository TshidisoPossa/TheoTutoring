import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/notifications.dart';

NotificationStore? _store; // shared, so the Google access token is reused

// Runs before every /admin/notifications route: checks the Firebase ID
// token belongs to an active administrator, then gives the route their
// UID and the Firestore store (the same store students and tutors use),
// and turns Firestore problems into JSON errors.
Handler middleware(Handler handler) {
  return (context) async {
    final authorization =
        context.request.headers['authorization'] ??
        context.request.headers['Authorization'];
    final String uid;
    try {
      uid = (await verifyFirebaseToken(authorization)).uid;
      await resolveAdmin(authorization); // must be an active admin
    } on AuthTokenException catch (e) {
      return Response.json(statusCode: 401, body: {'error': e.message});
    } on AdminAccessDenied catch (e) {
      return Response.json(statusCode: 403, body: {'error': e.message});
    } catch (e) {
      stderr.writeln('Admin notification sign-in failed: $e');
      return Response.json(
        statusCode: 503,
        body: {'error': 'Authentication service is temporarily unavailable.'},
      );
    }

    try {
      final store = _store ??= NotificationStore.fromFirebaseAdmin();
      return await handler(
        context
            .provide<AdminNotificationUser>(() => AdminNotificationUser(uid))
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
