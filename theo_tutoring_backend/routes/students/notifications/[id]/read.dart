import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/student_notifications.dart';

// POST /students/notifications/{id}/read
// Called when the student taps a notification card.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405); // only POST is allowed
  }
  if (!NotificationStore.isValidId(id)) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid id'});
  }
  final student = context.read<StudentSession>();
  final store = context.read<NotificationStore>();

  // Only looks in this student's own notifications, so nobody can mark
  // someone else's as read
  if (!await store.markRead(student.firebaseUid, id)) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Notification not found'},
    );
  }
  return Response.json(
    body: {
      'id': id,
      'read': true,
      'unreadCount': await store.unreadCount(student.firebaseUid),
    },
  );
}
