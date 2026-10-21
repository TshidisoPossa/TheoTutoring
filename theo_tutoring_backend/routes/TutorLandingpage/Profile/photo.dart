import 'dart:io'; // HttpStatus codes + stderr

import 'package:dart_frog/dart_frog.dart'; // Dart Frog types
import 'package:theo_tutoring_backend/cloudinary_url.dart'; // URL check
import 'package:theo_tutoring_backend/database.dart'; // getConnection()
import 'package:theo_tutoring_backend/header_tutor.dart'; // name + photo
import 'package:theo_tutoring_backend/profile_tutor.dart'; // updateTutorPhoto
import 'package:theo_tutoring_backend/request_utils.dart'; // JSON helpers
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart'; // TutorSession

// PUT /TutorLandingpage/Profile/photo   (camera badge on the profile picture)
//
// The app uploads the new picture to Cloudinary first, then sends its URL:
//   {"profilePhotoUrl": "https://res.cloudinary.com/<cloud>/image/upload/....jpg"}
// The URL is saved in User.ProfilePhoto and the updated name + photo are sent
// back, so the app can show the new picture straight away. Every tutor page
// reads the photo through getTutorHeader, so it changes everywhere.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
    ); // only PUT is allowed
  }
  final tutor = context.read<TutorSession>(); // who is calling

  try {
    final body = await readJsonObject(context);
    final url = optionalString(body, 'profilePhotoUrl', maxLength: 255);
    if (url == null) {
      return jsonError(HttpStatus.badRequest, 'Please choose a photo.');
    }
    final urlError = checkCloudinaryUrl(
      url,
      'Profile photo',
      cloudinaryImageTypes, // JPG or PNG only
      cloudinaryCloudName(),
    );
    if (urlError != null) return jsonError(HttpStatus.badRequest, urlError);

    final conn = await getConnection(); // shared DB connection (do not close it)
    await updateTutorPhoto(conn, tutor.tutorId, url);

    final header = await getTutorHeader(conn, tutor.tutorId);
    if (header == null) {
      return jsonError(HttpStatus.notFound, 'Tutor not found');
    }
    return Response.json(
      body: {
        'message': 'Profile photo updated.',
        'tutor': header, // tutorId, name, profilePhotoUrl (the new one)
      },
    );
  } on FormatException catch (e) {
    return jsonError(HttpStatus.badRequest, e.message);
  } catch (e) {
    stderr.writeln('Error updating tutor photo: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Could not update your photo. Please try again.',
    );
  }
}
