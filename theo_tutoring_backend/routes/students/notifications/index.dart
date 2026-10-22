import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

// GET /students/notifications — fetch all notifications for the logged-in student

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return jsonError(405, 'Method not allowed.');
  }

  final FirebaseUser firebaseUser;
  try {
    firebaseUser = await verifyFirebaseToken(
      context.request.headers['Authorization'] ??
          context.request.headers['authorization'],
    );
  } on AuthTokenException catch (e) {
    return jsonError(401, e.message);
  } catch (e) {
    return jsonError(503, 'Authentication service temporarily unavailable.');
  }

  try {
    final db = await getConnection();

    // Look up the student's UserId
    final userResult = await db.execute(
      "SELECT UserId FROM User WHERE FirebaseUid = :uid AND Role = 'student'",
      {'uid': firebaseUser.uid},
    );
    if ((userResult.rows as List).isEmpty) {
      return jsonError(404, 'Student account not found.');
    }
    final userId = int.parse(
        userResult.rows.first.colByName('UserId').toString());

    // Fetch notifications newest-first
    final notifResult = await db.execute(
      '''SELECT NotificationID, Type, Message, IsRead, Created_AT
         FROM Notification
         WHERE UserID = :userId
         ORDER BY Created_AT DESC
         LIMIT 100''',
      {'userId': userId},
    );

    final notifications = notifResult.rows.map((row) {
      final type = row.colByName('Type')?.toString() ?? 'other';
      final message = row.colByName('Message')?.toString() ?? '';
      final isReadRaw = row.colByName('IsRead');
      final isRead = isReadRaw == '1' || isReadRaw == true;
      final createdAt = row.colByName('Created_AT')?.toString() ?? '';

      // Derive a short title from the type
      String title;
      switch (type) {
        case 'new_message':
          title = 'New Message';
          break;
        case 'upcoming_lesson':
          title = 'Upcoming Lesson';
          break;
        default:
          title = 'Notification';
      }

      return {
        'id': row.colByName('NotificationID')?.toString() ?? '',
        'type': type,
        'title': title,
        'body': message,
        'sent_at': createdAt,
        'is_read': isRead,
        'action_label': null,
      };
    }).toList();

    return Response.json(body: {'notifications': notifications});
  } catch (e) {
    print('❌ GET /students/notifications error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}
