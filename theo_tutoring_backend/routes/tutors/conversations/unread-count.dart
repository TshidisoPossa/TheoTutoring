import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

// GET /tutor/conversations/unread-count — total unread messages across all students

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

    final result = await db.execute(
      'SELECT COUNT(*) AS cnt FROM Messaging WHERE ReceiveID = :tid AND IsRead = FALSE',
      {'tid': tutorId},
    );

    final count =
        int.tryParse(result.rows.first.colByName('cnt').toString()) ?? 0;

    return Response.json(body: {'unreadCount': count});
  } catch (e) {
    print('❌ GET /tutor/conversations/unread-count error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}
