import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

Future<Response> onRequest(RequestContext context) async {
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
      "SELECT UserId, Email, PhoneNum FROM User WHERE FirebaseUid = :uid AND Role = 'tutor'",
      {'uid': firebaseUser.uid},
    );

    if ((userResult.rows as List).isEmpty) {
      return jsonError(404, 'Tutor account not found.');
    }

    if (context.request.method == HttpMethod.get) {
      final row = userResult.rows.first;
      return Response.json(body: {
        'email': row.colByName('Email')?.toString() ?? '',
        'phone': row.colByName('PhoneNum')?.toString() ?? '',
        'notifications': {
          'sessionReminders': true,
          'newBookingAlerts': true,
          'directMessages': true,
          'newReviews': false,
        },
      });
    } else if (context.request.method == HttpMethod.put) {
      final body = await readJsonObject(context);
      final email = (body['email'] as String?)?.trim() ?? '';
      final phone = (body['phone'] as String?)?.trim() ?? '';

      if (email.isEmpty) return jsonError(400, 'Email cannot be empty.');
      if (phone.isEmpty) return jsonError(400, 'Phone number cannot be empty.');

      final userId = int.parse(
        userResult.rows.first.colByName('UserId').toString(),
      );
      await db.execute(
        'UPDATE User SET Email = :email, PhoneNum = :phone WHERE UserId = :id',
        {'email': email, 'phone': phone, 'id': userId},
      );
      return Response.json(body: {'success': true});
    } else {
      return jsonError(405, 'Method not allowed.');
    }
  } catch (e) {
    print('❌ /tutor/settings error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}