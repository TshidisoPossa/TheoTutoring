import 'package:dart_frog/dart_frog.dart';
import '../../../../lib/database.dart';
import '../../../../lib/firebase_auth.dart';
import '../../../../lib/request_utils.dart';

// GET  /tutor/conversations/[studentId]/messages — fetch message history
// POST /tutor/conversations/[studentId]/messages — send a message

Future<Response> onRequest(RequestContext context, String studentId) async {
  final sid = int.tryParse(studentId);
  if (sid == null) return jsonError(400, 'Invalid student ID.');

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

    // ── GET: message history ──────────────────────────────────────────────
    if (context.request.method == HttpMethod.get) {
      final result = await db.execute(
        '''SELECT MessageID, SenderID, ReceiveID, MessageText, SentAt, IsRead, BookingID
           FROM Messaging
           WHERE (SenderID = :tid AND ReceiveID = :sid)
              OR (SenderID = :sid AND ReceiveID = :tid)
           ORDER BY SentAt ASC''',
        {'tid': tutorId, 'sid': sid},
      );

      final messages = result.rows.map((row) {
        final isReadRaw = row.colByName('IsRead');
        return {
          'messageId':
              int.parse(row.colByName('MessageID').toString()),
          'senderId':
              int.parse(row.colByName('SenderID').toString()),
          'receiverId':
              int.parse(row.colByName('ReceiveID').toString()),
          'messageText':
              row.colByName('MessageText')?.toString() ?? '',
          'sentAt': row.colByName('SentAt')?.toString() ?? '',
          'isRead': isReadRaw == '1' || isReadRaw == true,
          'bookingId': row.colByName('BookingID') != null
              ? int.tryParse(row.colByName('BookingID').toString())
              : null,
        };
      }).toList();

      return Response.json(body: messages);
    }

    // ── POST: send a message ──────────────────────────────────────────────
    if (context.request.method == HttpMethod.post) {
      final body = await readJsonObject(context);
      final messageText = (body['messageText'] as String?)?.trim() ?? '';
      if (messageText.isEmpty) {
        return jsonError(400, 'Message text cannot be empty.');
      }
      final bookingId = body['bookingId'] as int?;

      await db.execute(
        '''INSERT INTO Messaging (UserID, SenderID, ReceiveID, MessageText, BookingID)
           VALUES (:uid, :sid_from, :sid_to, :text, :bid)''',
        {
          'uid': tutorId,
          'sid_from': tutorId,
          'sid_to': sid,
          'text': messageText,
          'bid': bookingId,
        },
      );

      // Fetch the inserted row to return it
      final inserted = await db.execute(
        '''SELECT MessageID, SenderID, ReceiveID, MessageText, SentAt, IsRead, BookingID
           FROM Messaging
           WHERE SenderID = :tid AND ReceiveID = :sid
           ORDER BY SentAt DESC LIMIT 1''',
        {'tid': tutorId, 'sid': sid},
      );

      if ((inserted.rows as List).isEmpty) {
        return jsonError(500, 'Message sent but could not be retrieved.');
      }

      final row = inserted.rows.first;
      final isReadRaw = row.colByName('IsRead');
      return Response.json(
        statusCode: 201,
        body: {
          'messageId':
              int.parse(row.colByName('MessageID').toString()),
          'senderId':
              int.parse(row.colByName('SenderID').toString()),
          'receiverId':
              int.parse(row.colByName('ReceiveID').toString()),
          'messageText':
              row.colByName('MessageText')?.toString() ?? '',
          'sentAt': row.colByName('SentAt')?.toString() ?? '',
          'isRead': isReadRaw == '1' || isReadRaw == true,
          'bookingId': row.colByName('BookingID') != null
              ? int.tryParse(row.colByName('BookingID').toString())
              : null,
        },
      );
    }

    return jsonError(405, 'Method not allowed.');
  } catch (e) {
    print('❌ /tutor/conversations/$studentId/messages error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}
