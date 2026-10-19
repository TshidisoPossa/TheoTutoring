import 'package:dart_frog/dart_frog.dart';
import '../../../../lib/database.dart';
import '../../../../lib/firebase_auth.dart';
import '../../../../lib/request_utils.dart';

Future<Response> onRequest(RequestContext context, String studentId) async {
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
  if (studentIdInt == null) return jsonError(400, 'Invalid student ID.');

  try {
    final db = await getConnection();
    final tutorResult = await db.execute('''
      SELECT u.UserId FROM User u
      INNER JOIN TutorProfile tp ON tp.UserId = u.UserId
      WHERE u.FirebaseUid = :uid AND u.Role = 'tutor'
    ''', {'uid': firebaseUser.uid});

    if (tutorResult.rows.isEmpty) return jsonError(404, 'Tutor account not found.');
    final tutorUserId = int.parse(tutorResult.rows.first.colByName('UserId').toString());

    if (context.request.method == HttpMethod.get) {
      return _getMessages(db, tutorUserId, studentIdInt);
    } else if (context.request.method == HttpMethod.post) {
      return _sendMessage(context, db, tutorUserId, studentIdInt);
    } else {
      return jsonError(405, 'Method not allowed');
    }
  } catch (e) {
    print('❌ /tutor/conversations/$studentId/messages error: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}

Future<Response> _getMessages(dynamic db, int tutorUserId, int studentIdInt) async {
  final result = await db.execute('''
    SELECT m.MessageID, m.SenderID, m.ReceiveID, m.MessageText,
           m.SentAt, m.IsRead, m.BookingID
    FROM Messaging m
    WHERE (m.SenderID = :tutorId AND m.ReceiveID = :studentId)
       OR (m.SenderID = :studentId AND m.ReceiveID = :tutorId)
    ORDER BY m.SentAt ASC
  ''', {'tutorId': tutorUserId, 'studentId': studentIdInt});

  final messages = result.rows.map((row) {
    final bookingRaw = row.colByName('BookingID');
    return {
      'messageId': int.parse(row.colByName('MessageID').toString()),
      'senderId': int.parse(row.colByName('SenderID').toString()),
      'receiverId': int.parse(row.colByName('ReceiveID').toString()),
      'messageText': row.colByName('MessageText')?.toString() ?? '',
      'sentAt': row.colByName('SentAt')?.toString() ?? '',
      'isRead': row.colByName('IsRead').toString() == '1',
      'bookingId': bookingRaw != null ? int.tryParse(bookingRaw.toString()) : null,
    };
  }).toList();

  return Response.json(body: messages);
}

Future<Response> _sendMessage(
    RequestContext context, dynamic db, int tutorUserId, int studentIdInt) async {
  final body = await readJsonObject(context);
  final messageText = (body['messageText'] as String?)?.trim() ?? '';
  if (messageText.isEmpty) return jsonError(400, 'Message text cannot be empty.');
  if (messageText.length > 2000) return jsonError(400, 'Message is too long (max 2000 characters).');

  final bookingId = body['bookingId'] as int?;
  final studentCheck = await db.execute(
    "SELECT UserId FROM User WHERE UserId = :id AND Role = 'student'",
    {'id': studentIdInt},
  );
  if ((studentCheck.rows as List).isEmpty) return jsonError(404, 'Student not found.');

  final insertResult = await db.execute('''
    INSERT INTO Messaging (SenderID, ReceiveID, MessageText, SentAt, IsRead, BookingID)
    VALUES (:senderId, :receiverId, :text, NOW(), 0, :bookingId)
  ''', {'senderId': tutorUserId, 'receiverId': studentIdInt, 'text': messageText, 'bookingId': bookingId});

  final newId = insertResult.lastInsertID.toInt();
  final saved = await db.execute('''
    SELECT MessageID, SenderID, ReceiveID, MessageText, SentAt, IsRead, BookingID
    FROM Messaging WHERE MessageID = :id
  ''', {'id': newId});

  final row = saved.rows.first;
  final bookingRaw = row.colByName('BookingID');
  return Response.json(statusCode: 201, body: {
    'messageId': int.parse(row.colByName('MessageID').toString()),
    'senderId': int.parse(row.colByName('SenderID').toString()),
    'receiverId': int.parse(row.colByName('ReceiveID').toString()),
    'messageText': row.colByName('MessageText')?.toString() ?? '',
    'sentAt': row.colByName('SentAt')?.toString() ?? '',
    'isRead': false,
    'bookingId': bookingRaw != null ? int.tryParse(bookingRaw.toString()) : null,
  });
}