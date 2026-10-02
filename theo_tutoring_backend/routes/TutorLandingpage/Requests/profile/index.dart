import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/profile_tutor.dart'; // profile read/update functions
import 'package:theo_tutoring_backend/tutorlanding_session.dart'; // TutorSession

// GET   -> returns the tutor's profile (name, photo, about)
// PATCH -> updates name, profilePhotoUrl and/or about, then returns the profile
Future<Response> onRequest(RequestContext context) async {
  switch (context.request.method) {
    case HttpMethod.get:
      return _getProfile(context);
    case HttpMethod.patch:
      return _updateProfile(context);
    default:
      return Response(statusCode: 405); // only GET and PATCH are allowed
  }
}

Future<Response> _getProfile(RequestContext context) async {
  final tutor = context
      .read<TutorSession>(); // who is calling (set by middleware)
  final conn = await getConnection(); // shared DB connection (do not close it)

  final profile = await getTutorProfilePage(conn, tutor.tutorId);
  if (profile == null) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Tutor not found'},
    ); // tutor row missing
  }
  return Response.json(body: profile);
}

Future<Response> _updateProfile(RequestContext context) async {
  final tutor = context.read<TutorSession>();
  final conn = await getConnection(); // shared DB connection (do not close it)

  final body = await _readJsonObject(context.request);
  if (body == null) return _badRequest('Body must be a JSON object');

  // Which fields did the app send? (each pencil sends only its own field)
  final hasName = body.containsKey('name');
  final hasPhoto = body.containsKey('profilePhotoUrl');
  final hasAbout = body.containsKey('about');

  if (!hasName && !hasPhoto && !hasAbout) {
    return _badRequest('Nothing to update');
  }

  final name = body['name'];
  final photo = body['profilePhotoUrl'];
  final about = body['about'];

  // name and photo must be text; about may be text or null (null clears it)
  if ((hasName && name is! String) ||
      (hasPhoto && photo is! String) ||
      (hasAbout && about != null && about is! String)) {
    return _badRequest('name, profilePhotoUrl and about must be text');
  }

  try {
    if (hasName) await updateTutorName(conn, tutor.tutorId, name as String);
    if (hasPhoto) {
      await updateTutorPhoto(conn, tutor.tutorId, photo as String);
    }
    if (hasAbout) {
      await updateTutorAbout(conn, tutor.tutorId, (about as String?) ?? '');
    }
  } on ArgumentError catch (e) {
    return _badRequest(e.message.toString()); // e.g. "Name cannot be empty."
  }

  return _getProfile(context); // send back the saved profile
}

// Reads the request body as a JSON object, or null if it isn't one
Future<Map<String, dynamic>?> _readJsonObject(Request request) async {
  try {
    final body = await request.json();
    return body is Map<String, dynamic> ? body : null;
  } on FormatException {
    return null; // not valid JSON
  }
}

Response _badRequest(String message) {
  return Response.json(statusCode: 400, body: {'error': message});
}
