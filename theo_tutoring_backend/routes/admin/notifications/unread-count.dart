import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// GET /admin/notifications/unread-count
// The number on the admin top bar's bell.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  final admin = context.read<AdminNotificationUser>();
  final store = context.read<NotificationStore>();
  return Response.json(
    body: {'unreadCount': await store.unreadCount(admin.uid)},
  );
}
