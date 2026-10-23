import 'package:dart_frog/dart_frog.dart';
import '../../lib/database.dart';
import '../../lib/firebase_auth.dart';
import '../../lib/request_utils.dart';

// GET /tutor/me — returns the MySQL UserId for the signed-in tutor

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
    final result = await db.execute(
      "SELECT UserId, Name FROM User WHERE FirebaseUid = :uid AND Role = 'tutor'",
      {'uid': firebaseUser.uid},
    );
    if ((result.rows as List).isEmpty) {
      return jsonError(404, 'Tutor account not found.');
    }
    final row = result.rows.first;
    return Response.json(body: {
      'userId': int.parse(row.colByName('UserId').toString()),
      'name': row.colByName('Name')?.toString() ?? '',
    });
  } catch (e) {
    print('❌ GET /tutor/me error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}
