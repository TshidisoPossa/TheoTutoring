import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// POST /admin/notifications/read-all
// "Mark all as read".
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }
  final admin = context.read<AdminNotificationUser>();
  final store = context.read<NotificationStore>();
  final updated = await store.markAllRead(admin.uid);
  return Response.json(
    body: {
      'updated': updated,
      'unreadCount': await store.unreadCount(admin.uid),
    },
  );
}
