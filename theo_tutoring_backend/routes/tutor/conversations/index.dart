import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

// GET /tutor/conversations
//
// Returns the list of students the signed-in tutor has exchanged messages with,
// ordered by most recent message. Each entry includes the last message preview
// and unread count.

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return jsonError(405, 'Method not allowed');
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
      '''
      SELECT u.UserId
      FROM User u
      INNER JOIN TutorProfile tp ON tp.UserId = u.UserId
      WHERE u.FirebaseUid = :uid AND u.Role = 'tutor'
      ''',
      {'uid': firebaseUser.uid},
    );

    if (tutorResult.rows.isEmpty) {
      return jsonError(404, 'Tutor account not found.');
    }

    final tutorUserId = int.parse(
      tutorResult.rows.first.colByName('UserId')!,
    );

    final result = await db.execute(
      '''
      SELECT
        u.UserId        AS studentId,
        u.Name          AS studentName,
        m.MessageText   AS lastMessage,
        m.SentAt        AS lastMessageTime,
        SUM(CASE WHEN m2.IsRead = 0 AND m2.ReceiveID = :tutorId THEN 1 ELSE 0 END)
                        AS unreadCount
      FROM Messaging m
      INNER JOIN (
        SELECT
          CASE WHEN SenderID = :tutorId THEN ReceiveID ELSE SenderID END AS otherUserId,
          MAX(MessageID) AS lastMsgId
        FROM Messaging
        WHERE SenderID = :tutorId OR ReceiveID = :tutorId
        GROUP BY otherUserId
      ) latest ON m.MessageID = latest.lastMsgId
      INNER JOIN User u ON u.UserId = latest.otherUserId
      LEFT JOIN Messaging m2 ON (
        m2.SenderID = latest.otherUserId AND m2.ReceiveID = :tutorId
      )
      WHERE u.Role = 'student'
      GROUP BY u.UserId, u.Name, m.MessageText, m.SentAt
      ORDER BY m.SentAt DESC
      ''',
      {'tutorId': tutorUserId},
    );

    final conversations = result.rows.map((row) {
      final name = row.colByName('studentName') ?? '';
      final parts = name.trim().split(' ');
      final initials = parts.length >= 2
          ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
          : name.isNotEmpty
              ? name[0].toUpperCase()
              : '?';

      return {
        'userId': int.parse(row.colByName('studentId') ?? '0'),
        'name': name,
        'initials': initials,
        'lastMessage': row.colByName('lastMessage') ?? '',
        'time': row.colByName('lastMessageTime') ?? '',
        'unreadCount': int.parse(row.colByName('unreadCount') ?? '0'),
        'isOnline': false,
      };
    }).toList();

    return Response.json(body: conversations);
  } catch (e) {
    print('❌ GET /tutor/conversations error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}