import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/notifications.dart';
// Relative, like the TutorLandingpage middleware that provides it: a
// package: import would be a different TutorSession type to Dart.
import '../../../lib/tutorlanding_session.dart';

// POST /TutorLandingpage/notifications/read-all
// "Mark all as read".
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }
  final tutor = context.read<TutorSession>();
  final store = context.read<NotificationStore>();
  final updated = await store.markAllRead(tutor.userId);
  return Response.json(
    body: {
      'updated': updated, // how many were unread
      'unreadCount': await store.unreadCount(tutor.userId), // new bell number
    },
  );
}
