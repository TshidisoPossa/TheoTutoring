import 'package:mysql_client/mysql_client.dart';

// ONE place that loads the tutor's name and profile picture.
// Every tutor page (Dashboard, Requests, Request Details, Schedule, Profile)
// calls this, so the picture in the top right is always the same.
Future<Map<String, dynamic>?> getTutorHeader(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    // TutorProfile.UserID links to User.UserId, where Name and ProfilePhoto are stored
    '''
    SELECT tp.TutorID,
           u.Name,
           u.ProfilePhoto
    FROM TutorProfile tp
    JOIN `User` u ON u.UserId = tp.UserID
    WHERE tp.TutorID = :tutorId
    ''',
    {'tutorId': tutorId},
  );

  if (result.rows.isEmpty) return null; // no such tutor

  final data = result.rows.first.assoc();

  return {
    'tutorId': int.parse(data['TutorID']!),
    'name': data['Name'],
    'profilePhotoUrl':
        data['ProfilePhoto'], // photo url (null if none uploaded)
  };
}
