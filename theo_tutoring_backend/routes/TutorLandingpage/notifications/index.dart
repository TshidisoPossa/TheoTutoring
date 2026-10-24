import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/notifications.dart';
// Relative, like the TutorLandingpage middleware that provides it: a
// package: import would be a different TutorSession type to Dart.
import '../../../lib/tutorlanding_session.dart';

// GET /TutorLandingpage/notifications?limit=50
// The Notifications page: the tutor's notifications, newest first.
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

  final tutor = context.read<TutorSession>();
  final store = context.read<NotificationStore>();

  // Both reads at once: the list and the total unread (for "3 unread")
  final results = await Future.wait([
    store.list(tutor.userId, limit: limit),
    store.unreadCount(tutor.userId),
  ]);
  final notifications = results[0] as List<AppNotification>;

  return Response.json(
    body: {
      'unreadCount': results[1], // all unread, not only the ones returned
      'count': notifications.length, // number of notifications returned
      // each card: id, type, title, body, bookingId, read, createdAt,
      // minutesAgo ("2 min ago") and section ('today'/'yesterday'/'earlier')
      'notifications': notifications.map((n) => n.toJson()).toList(),
    },
  );
}
