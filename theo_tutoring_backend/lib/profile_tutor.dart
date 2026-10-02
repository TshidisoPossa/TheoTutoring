import 'header_tutor.dart';
import 'package:mysql_client/mysql_client.dart'; // gives us the MySQLConnection type
import 'package:theo_tutoring_backend/header_tutor.dart';

// ---------------------------------------------------------------------------
// TUTOR PROFILE PAGE: BACKEND
// Boxes covered so far: the tutor profile box (photo + name) and About Me.
// More functions get added to this same file as we build the other boxes.
// ---------------------------------------------------------------------------

// Loads the "About Me" text from TutorProfile.Bio.
Future<String?> getTutorAbout(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    '''
    SELECT Bio
    FROM TutorProfile
    WHERE TutorID = :tutorId
    ''',
    {'tutorId': tutorId}, // value for :tutorId (prevents SQL injection)
  );

  if (result.rows.isEmpty) return null; // no such tutor

  final data = result.rows.first.assoc(); // first row as a column -> value map

  return data['Bio']; // null if the tutor hasn't written a bio yet
}

// ONE call for the whole Profile page.
// Your teammate calls this once and gets everything the page needs so far.
// Returns null if the tutor doesn't exist.
Future<Map<String, dynamic>?> getTutorProfilePage(
  MySQLConnection conn,
  int tutorId,
) async {
  // Name + photo (same shared function every tutor page uses)
  final header = await getTutorHeader(conn, tutorId);
  if (header == null) return null; // no such tutor

  final about = await getTutorAbout(conn, tutorId);

  return {
    ...header, // tutorId, name, profilePhotoUrl
    'about': about, // bio text (null if not written yet)
  };
}

// ============================== UPDATE =====================================

// Pencil next to the name.
// The name is stored in User.Name (VARCHAR(100), NOT NULL), so we reach the
// User row through TutorProfile.UserID.
// Throws ArgumentError if the name is empty or longer than 100 characters.
Future<void> updateTutorName(
  MySQLConnection conn,
  int tutorId,
  String name,
) async {
  final cleaned = name.trim();

  if (cleaned.isEmpty) {
    throw ArgumentError('Name cannot be empty.');
  }
  if (cleaned.length > 100) {
    throw ArgumentError('Name must be 100 characters or less.');
  }

  await conn.execute(
    '''
    UPDATE `User` u
    JOIN TutorProfile tp ON tp.UserID = u.UserId
    SET u.Name = :name
    WHERE tp.TutorID = :tutorId
    ''',
    {'name': cleaned, 'tutorId': tutorId},
  );
}

// Camera badge on the photo.
// This only saves the photo URL in User.ProfilePhoto (VARCHAR(255)).
// Uploading the image file itself (to wherever you host images) happens
// before this, and gives you the URL to pass in here.
// Throws ArgumentError if the URL is empty or longer than 255 characters.
Future<void> updateTutorPhoto(
  MySQLConnection conn,
  int tutorId,
  String photoUrl,
) async {
  final cleaned = photoUrl.trim();

  if (cleaned.isEmpty) {
    throw ArgumentError('Photo URL cannot be empty.');
  }
  if (cleaned.length > 255) {
    throw ArgumentError('Photo URL must be 255 characters or less.');
  }

  await conn.execute(
    '''
    UPDATE `User` u
    JOIN TutorProfile tp ON tp.UserID = u.UserId
    SET u.ProfilePhoto = :photoUrl
    WHERE tp.TutorID = :tutorId
    ''',
    {'photoUrl': cleaned, 'tutorId': tutorId},
  );
}

// Pencil on the About Me box.
// Saved in TutorProfile.Bio (TEXT). An empty bio is stored as NULL.
Future<void> updateTutorAbout(
  MySQLConnection conn,
  int tutorId,
  String about,
) async {
  final cleaned = about.trim();

  await conn.execute(
    '''
    UPDATE TutorProfile
    SET Bio = :about
    WHERE TutorID = :tutorId
    ''',
    {
      'about': cleaned.isEmpty ? null : cleaned, // NULL when nothing written
      'tutorId': tutorId,
    },
  );
}
