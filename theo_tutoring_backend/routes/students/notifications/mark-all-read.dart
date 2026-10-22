import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

// PUT /students/notifications/mark-all-read — mark every notification as read

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
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

    final userResult = await db.execute(
      "SELECT UserId FROM User WHERE FirebaseUid = :uid AND Role = 'student'",
      {'uid': firebaseUser.uid},
    );
    if ((userResult.rows as List).isEmpty) {
      return jsonError(404, 'Student account not found.');
    }
    final userId = int.parse(
        userResult.rows.first.colByName('UserId').toString());

    await db.execute(
      'UPDATE Notification SET IsRead = TRUE WHERE UserID = :userId',
      {'userId': userId},
    );

    return Response.json(body: {'success': true});
  } catch (e) {
    print('❌ PUT /students/notifications/mark-all-read error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}
