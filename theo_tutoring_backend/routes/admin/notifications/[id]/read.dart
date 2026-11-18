import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// POST /admin/notifications/{id}/read
// Called when the admin taps a notification card. Only the admin's own
// notifications can be marked.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }
  if (!NotificationStore.isValidId(id)) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid id'});
  }
  final admin = context.read<AdminNotificationUser>();
  final store = context.read<NotificationStore>();
  if (!await store.markRead(admin.uid, id)) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Notification not found'},
    );
  }
  return Response.json(
    body: {
      'id': id,
      'read': true,
      'unreadCount': await store.unreadCount(admin.uid),
    },
  );
}
