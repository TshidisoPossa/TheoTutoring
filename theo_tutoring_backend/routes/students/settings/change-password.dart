import 'package:dart_frog/dart_frog.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

// POST /student/settings/change-password
// Firebase handles passwords — we just verify the token is valid
// and return success. The actual password change happens on the
// client via FirebaseAuth.instance.currentUser?.updatePassword().

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(405, 'Method not allowed.');
  }

  try {
    await verifyFirebaseToken(
      context.request.headers['Authorization'] ??
          context.request.headers['authorization'],
    );
  } on AuthTokenException catch (e) {
    return jsonError(401, e.message);
  } catch (e) {
    return jsonError(503, 'Authentication service temporarily unavailable.');
  }

  // Password changes are handled entirely by Firebase on the client side.
  // This endpoint exists so the service layer has a consistent pattern.
  return Response.json(body: {'success': true});
}