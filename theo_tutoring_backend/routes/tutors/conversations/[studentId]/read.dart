import 'package:dart_frog/dart_frog.dart';
import '../../../../lib/database.dart';
import '../../../../lib/firebase_auth.dart';
import '../../../../lib/request_utils.dart';

// PUT /tutor/conversations/[studentId]/read — mark all messages from student as read

Future<Response> onRequest(RequestContext context, String studentId) async {
  if (context.request.method != HttpMethod.put) {
    return jsonError(405, 'Method not allowed.');
  }

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

    // Mark all messages sent by the student to this tutor as read
    await db.execute(
      '''UPDATE Messaging
         SET IsRead = TRUE
         WHERE SenderID = :sid AND ReceiveID = :tid AND IsRead = FALSE''',
      {'sid': sid, 'tid': tutorId},
    );

    return Response.json(body: {'success': true});
  } catch (e) {
    print('❌ PUT /tutor/conversations/$studentId/read error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}
