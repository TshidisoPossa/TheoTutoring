import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

// GET /tutor/conversations/unread-count
//
// Returns the total number of unread messages across all student conversations.
// Used to drive the badge on the Chats nav item.

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
      "SELECT UserId FROM User WHERE FirebaseUid = :uid AND Role = 'tutor'",
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
      SELECT COUNT(*) AS total
      FROM Messaging
      WHERE ReceiveID = :tutorId AND IsRead = 0
      ''',
      {'tutorId': tutorUserId},
    );

    final total = int.parse(
      result.rows.first.colByName('total') ?? '0',
    );

    return Response.json(body: {'unreadCount': total});
  } catch (e) {
    print('❌ GET /tutor/conversations/unread-count error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}