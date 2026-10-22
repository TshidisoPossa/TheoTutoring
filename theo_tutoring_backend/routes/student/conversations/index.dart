import 'package:dart_frog/dart_frog.dart';

import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

// GET /student/conversations
//
// Returns tutors the signed-in student has exchanged messages with, ordered
// by most recent message.
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
    return jsonError(503, 'Authentication service temporarily unavailable. Please try again later.');
  }

  try {
    final db = await getConnection();
    final studentResult = await db.execute(
      "SELECT UserId FROM User WHERE FirebaseUid = :uid AND Role = 'student'",
      {'uid': firebaseUser.uid},
    );

    if (studentResult.rows.isEmpty) {
      return jsonError(404, 'Student account not found.');
    }

    final studentUserId = int.parse(
      studentResult.rows.first.colByName('UserId').toString(),
    );
    final result = await db.execute(
      '''
      SELECT
        u.UserId AS tutorId,
        u.Name AS tutorName,
        u.ProfilePhoto AS profilePhotoUrl,
        m.MessageText AS lastMessage,
        m.SentAt AS lastMessageTime,
        SUM(CASE WHEN m2.IsRead = 0 AND m2.ReceiveID = :studentId THEN 1 ELSE 0 END)
          AS unreadCount
      FROM Messaging m
      INNER JOIN (
        SELECT
          CASE WHEN SenderID = :studentId THEN ReceiveID ELSE SenderID END AS otherUserId,
          MAX(MessageID) AS lastMsgId
        FROM Messaging
        WHERE SenderID = :studentId OR ReceiveID = :studentId
        GROUP BY otherUserId
      ) latest ON m.MessageID = latest.lastMsgId
      INNER JOIN User u ON u.UserId = latest.otherUserId
      LEFT JOIN Messaging m2 ON (
        m2.SenderID = latest.otherUserId AND m2.ReceiveID = :studentId
      )
      WHERE u.Role = 'tutor'
      GROUP BY u.UserId, u.Name, u.ProfilePhoto, m.MessageText, m.SentAt
      ORDER BY m.SentAt DESC
      ''',
      {'studentId': studentUserId},
    );

    final conversations = result.rows.map((dynamic row) {
      final name = row.colByName('tutorName')?.toString() ?? '';
      return {
        'userId': int.parse(row.colByName('tutorId').toString()),
        'name': name,
        'profilePhotoUrl': row.colByName('profilePhotoUrl')?.toString(),
        'lastMessage': row.colByName('lastMessage')?.toString() ?? '',
        'time': row.colByName('lastMessageTime')?.toString() ?? '',
        'unreadCount': int.parse(
          row.colByName('unreadCount')?.toString() ?? '0',
        ),
      };
    }).toList();

    return Response.json(body: conversations);
  } catch (e) {
    print('GET /student/conversations error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}
