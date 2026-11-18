import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// GET /admin/notifications?limit=50
// The admin Notifications page: newest first, same shape as the student
// and tutor lists.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  final rawLimit = context.request.uri.queryParameters['limit'];
  final limit = rawLimit == null ? 50 : int.tryParse(rawLimit);
  if (limit == null || limit < 1 || limit > NotificationStore.maxLimit) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'limit must be 1 to ${NotificationStore.maxLimit}'},
    );
  }
  final admin = context.read<AdminNotificationUser>();
  final store = context.read<NotificationStore>();
  final results = await Future.wait([
    store.list(admin.uid, limit: limit),
    store.unreadCount(admin.uid),
  ]);
  final notifications = results[0] as List<AppNotification>;
  return Response.json(
    body: {
      'unreadCount': results[1],
      'count': notifications.length,
      'notifications': notifications.map((n) => n.toJson()).toList(),
    },
  );
}
