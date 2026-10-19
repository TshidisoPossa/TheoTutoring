import 'package:dart_frog/dart_frog.dart';
import '../../../../lib/database.dart';
import '../../../../lib/firebase_auth.dart';
import '../../../../lib/request_utils.dart';

// PUT /tutor/conversations/[studentId]/read
//
// Marks all unread messages FROM the student TO this tutor as read.
// Called when the tutor opens the conversation screen.

Future<Response> onRequest(RequestContext context, String studentId) async {
  if (context.request.method != HttpMethod.put) {
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

  final studentIdInt = int.tryParse(studentId);
  if (studentIdInt == null) {
    return jsonError(400, 'Invalid student ID.');
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
      tutorResult.rows.first.colByName('UserId').toString(),
    );

    await db.execute(
      '''
      UPDATE Messaging
      SET IsRead = 1
      WHERE SenderID = :studentId
        AND ReceiveID = :tutorId
        AND IsRead = 0
      ''',
      {'studentId': studentIdInt, 'tutorId': tutorUserId},
    );

    return Response.json(body: {'success': true});
  } catch (e) {
    print('❌ PUT /tutor/conversations/$studentId/read error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}