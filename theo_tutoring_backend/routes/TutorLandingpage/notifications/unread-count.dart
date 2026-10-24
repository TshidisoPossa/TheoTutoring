import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/notifications.dart';
// Relative, like the TutorLandingpage middleware that provides it: a
// package: import would be a different TutorSession type to Dart.
import '../../../lib/tutorlanding_session.dart';

// GET /TutorLandingpage/notifications/unread-count
// The number on the dashboard's bell icon.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  final tutor = context.read<TutorSession>();
  final store = context.read<NotificationStore>();
  return Response.json(
    body: {'unreadCount': await store.unreadCount(tutor.userId)},
  );
}
