import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/student_notifications.dart';

// GET /students/notifications?limit=50
// The student's Notifications page: their notifications, newest first.
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

  final student = context.read<StudentSession>();
  final store = context.read<NotificationStore>();

  // Both reads at once: the list and the total unread (for "3 unread")
  final results = await Future.wait([
    store.list(student.firebaseUid, limit: limit),
    store.unreadCount(student.firebaseUid),
  ]);
  final notifications = results[0] as List<AppNotification>;

  return Response.json(
    body: {
      'unreadCount': results[1], // all unread, not only the ones returned
      'count': notifications.length,
      // each card: id, type, title, body, bookingId, read, createdAt,
      // minutesAgo ("2 min ago") and section ('today'/'yesterday'/'earlier')
      'notifications': notifications.map((n) => n.toJson()).toList(),
    },
  );
}
