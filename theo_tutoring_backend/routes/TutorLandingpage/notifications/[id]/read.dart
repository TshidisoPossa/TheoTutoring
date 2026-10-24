import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/notifications.dart'; // NotificationStore
// Relative, like the TutorLandingpage middleware that provides it: a
// package: import would be a different TutorSession type to Dart.
import '../../../../lib/tutorlanding_session.dart'; // TutorSession

// POST /TutorLandingpage/notifications/{id}/read
// Called when the tutor taps a notification card.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405); // only POST is allowed
  }
  if (!NotificationStore.isValidId(id)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid id'},
    ); // not a Firestore document ID
  }
  final tutor = context.read<TutorSession>(); // who is calling
  final store = context.read<NotificationStore>();

  // Only looks in this tutor's own notifications, so nobody can mark
  // someone else's as read
  if (!await store.markRead(tutor.userId, id)) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Notification not found'},
    );
  }
  return Response.json(
    body: {
      'id': id,
      'read': true,
      'unreadCount': await store.unreadCount(tutor.userId), // new bell number
    },
  );
}
