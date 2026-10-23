import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

// GET /tutor/conversations — list of students the tutor has chatted with,
// ordered by most recent message, with last message preview and unread count.

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

    final tutorResult = await db.execute(
      "SELECT UserId FROM User WHERE FirebaseUid = :uid AND Role = 'tutor'",
      {'uid': firebaseUser.uid},
    );
    if ((tutorResult.rows as List).isEmpty) {
      return jsonError(404, 'Tutor account not found.');
    }
    final tutorId =
        int.parse(tutorResult.rows.first.colByName('UserId').toString());

    // For each student the tutor has exchanged messages with, get:
    // - student's name
    // - last message text and time
    // - unread count (messages FROM the student that are unread)
    final result = await db.execute(
      '''
      SELECT
        u.UserId        AS studentId,
        u.Name          AS name,
        latest.lastMsg  AS lastMessage,
        latest.lastAt   AS lastAt,
        COALESCE(unread.cnt, 0) AS unreadCount
      FROM (
        SELECT
          CASE WHEN SenderID = :tid THEN ReceiveID ELSE SenderID END AS otherId,
          MAX(SentAt) AS lastAt
        FROM Messaging
        WHERE SenderID = :tid OR ReceiveID = :tid
        GROUP BY otherId
      ) AS conv
      JOIN User u ON u.UserId = conv.otherId
      JOIN (
        SELECT
          CASE WHEN SenderID = :tid THEN ReceiveID ELSE SenderID END AS otherId,
          MessageText AS lastMsg,
          SentAt AS lastAt
        FROM Messaging
        WHERE SenderID = :tid OR ReceiveID = :tid
        ORDER BY SentAt DESC
      ) AS latest ON latest.otherId = conv.otherId AND latest.lastAt = conv.lastAt
      LEFT JOIN (
        SELECT SenderID, COUNT(*) AS cnt
        FROM Messaging
        WHERE ReceiveID = :tid AND IsRead = FALSE
        GROUP BY SenderID
      ) AS unread ON unread.SenderID = conv.otherId
      ORDER BY conv.lastAt DESC
      ''',
      {'tid': tutorId},
    );

    final conversations = result.rows.map((row) {
      final name = row.colByName('name')?.toString() ?? '';
      // Build initials from name
      final parts = name.trim().split(' ');
      final initials = parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : name.isNotEmpty
              ? name[0].toUpperCase()
              : '?';

      final lastAt = row.colByName('lastAt')?.toString() ?? '';
      final timeLabel = _formatTime(lastAt);

      return {
        'userId': int.parse(row.colByName('studentId').toString()),
        'name': name,
        'initials': initials,
        'lastMessage': row.colByName('lastMessage')?.toString() ?? '',
        'time': timeLabel,
        'unreadCount':
            int.tryParse(row.colByName('unreadCount').toString()) ?? 0,
        'isOnline': false,
      };
    }).toList();

    return Response.json(body: conversations);
  } catch (e) {
    print('❌ GET /tutor/conversations error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}

String _formatTime(String dbDatetime) {
  try {
    final dt = DateTime.parse(dbDatetime);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  } catch (_) {
    return '';
  }
}
