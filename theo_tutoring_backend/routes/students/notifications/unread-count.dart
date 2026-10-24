import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/student_notifications.dart';

// GET /students/notifications/unread-count
// The number on the student dashboard's bell icon.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  final student = context.read<StudentSession>();
  final store = context.read<NotificationStore>();
  return Response.json(
    body: {'unreadCount': await store.unreadCount(student.firebaseUid)},
  );
}
