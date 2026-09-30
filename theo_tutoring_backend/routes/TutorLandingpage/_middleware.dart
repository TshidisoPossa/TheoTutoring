import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import '../../lib/database.dart'; // getConnection()
import '../../lib/firebase_auth_helper.dart'; // verifyFirebaseToken()
import '../../lib/tutorlanding_session.dart'; // TutorSession

//auther Tshidiso Possa

// Finds the TutorID that belongs to a Firebase UID, or null if not a tutor
Future<int?> _findTutorId(String firebaseUid) async {
  final conn = await getConnection(); // shared DB connection (do not close it)
  final result = await conn.execute(
    'SELECT tp.TutorID FROM TutorProfile tp ' // tutor row
    'INNER JOIN `User` u ON tp.UserId = u.UserId ' // link tutor to user
    'WHERE u.FirebaseUid = :uid', // match the verified Firebase UID
    {'uid': firebaseUid},
  );
  if (result.rows.isEmpty) return null; // this user is not a tutor
  return int.parse(result.rows.first.assoc()['TutorID']!); // TutorID as int
}

// Runs before every route under /tutor
Handler middleware(Handler handler) {
  return (context) async {
    final header =
        context.request.headers['Authorization'] ??
        ''; // read the Authorization header
    if (!header.startsWith('Bearer ')) {
      return Response.json(
        statusCode: 401,
        body: {'error': 'Missing token'},
      ); // no token sent
    }
    final uid = await verifyFirebaseToken(
      header.substring(7),
    ); // strip "Bearer " and verify
    if (uid == null) {
      return Response.json(
        statusCode: 401,
        body: {'error': 'Invalid token'},
      ); // bad token
    }
    final tutorId = await _findTutorId(uid); // map UID to TutorID
    if (tutorId == null) {
      return Response.json(
        statusCode: 403,
        body: {'error': 'Tutors only'},
      ); // NFR3 role restriction
    }
    return handler(
      context.provide<TutorSession>(
        () => TutorSession(uid, tutorId),
      ), // make session available to routes
    );
  };
}
