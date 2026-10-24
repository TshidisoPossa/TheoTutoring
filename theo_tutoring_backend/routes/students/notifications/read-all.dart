import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/student_notifications.dart';

// POST /students/notifications/read-all
// "Mark all as read".
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405); // only POST is allowed
  }
  final student = context.read<StudentSession>();
  final store = context.read<NotificationStore>();
  final updated = await store.markAllRead(student.firebaseUid);
  return Response.json(
    body: {
      'updated': updated, // how many were unread
      'unreadCount': await store.unreadCount(student.firebaseUid),
    },
  );
}
