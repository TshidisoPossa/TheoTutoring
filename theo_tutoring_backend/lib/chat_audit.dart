import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/chat.dart';

// The MySQL Messaging table as an audit copy of Firestore chat messages
// (schema.sql: "Firestore remains the primary chat store"). Rows are keyed
// by FirestoreMessageID, which is unique, so every write is safe to repeat:
// a row is inserted once, and IsRead only ever goes from 0 to 1.

/// Most message ids one [ChatAuditSink] call takes (one outbox batch).
const maxChatAuditBatch = 200;

// "{conversationId}/{messageId}", e.g. "s10_t1/1-abc…": at most 128
// characters (the column's size), path-safe characters only.
final _firestoreMessageId = RegExp(r'^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$');

/// One Firestore message, as recorded in the audit table.
class ChatAuditMessage {
  /// Creates an audit record. Throws an [ArgumentError] for values the
  /// audit table cannot hold.
  ChatAuditMessage({
    required this.firestoreMessageId,
    required this.senderId,
    required this.receiverId,
    required this.messageText,
    required this.sentAt,
    required this.isRead,
    this.bookingId,
  }) {
    checkChatAuditId(firestoreMessageId);
    if (senderId <= 0 || receiverId <= 0 || senderId == receiverId) {
      throw ArgumentError('senderId and receiverId must be two users.');
    }
    if (messageText.trim().isEmpty ||
        messageText.length > maxChatMessageLength) {
      throw ArgumentError.value(
        messageText.length,
        'messageText',
        'Must be 1 to $maxChatMessageLength characters',
      );
    }
    if (bookingId != null && bookingId! <= 0) {
      throw ArgumentError.value(bookingId, 'bookingId', 'Must be positive');
    }
  }

  /// "{conversationId}/{messageId}" in Firestore.
  final String firestoreMessageId;

  /// `User`.UserId of the sender (also the row's UserID).
  final int senderId;

  /// `User`.UserId of the receiver.
  final int receiverId;

  /// The message itself.
  final String messageText;

  /// Firestore's commit time; stored as UTC to the second.
  final DateTime sentAt;

  /// Whether the receiver had read it when it was recorded.
  final bool isRead;

  /// The booking the message is about, if any.
  final int? bookingId;
}

/// Throws an [ArgumentError] unless [id] is a valid FirestoreMessageID.
String checkChatAuditId(String id) {
  if (id.length > 128 || !_firestoreMessageId.hasMatch(id)) {
    throw ArgumentError.value(id, 'firestoreMessageId', 'Not a message id');
  }
  return id;
}

/// Writes the Messaging audit table.
abstract interface class ChatAuditSink {
  /// Records [message]; repeating it changes nothing, except that a row
  /// recorded as unread becomes read if [ChatAuditMessage.isRead] is true.
  Future<void> recordMessage(ChatAuditMessage message);

  /// Which of [firestoreMessageIds] already have a row.
  Future<Set<String>> presentIds(List<String> firestoreMessageIds);

  /// Marks the rows for [firestoreMessageIds] as read; returns how many
  /// changed (rows already read, or not yet recorded, are not counted).
  Future<int> markRead(List<String> firestoreMessageIds);
}

/// [ChatAuditSink] on the MySQL Messaging table.
class MySqlChatAudit implements ChatAuditSink {
  /// Uses the shared [MySQLConnection]; it is not closed here.
  MySqlChatAudit(this._connection);

  final MySQLConnection _connection;

  /// Insert-or-keep; IsRead may only go from 0 to 1. UserID is the account
  /// the row belongs to: the sender.
  static const recordSql = '''
    INSERT INTO Messaging
      (FirestoreMessageID, UserID, BookingID, ReceiveID, SenderID,
       MessageText, SentAt, IsRead)
    VALUES
      (:firestoreMessageId, :senderId, :bookingId, :receiverId, :senderId,
       :messageText, :sentAt, :isRead)
    ON DUPLICATE KEY UPDATE IsRead = IsRead OR VALUES(IsRead)
  ''';

  @override
  Future<void> recordMessage(ChatAuditMessage message) async {
    await _connection.execute(recordSql, {
      'firestoreMessageId': message.firestoreMessageId,
      'senderId': message.senderId,
      'receiverId': message.receiverId,
      'bookingId': message.bookingId,
      'messageText': message.messageText,
      'sentAt': mySqlUtcDateTime(message.sentAt),
      'isRead': message.isRead ? 1 : 0,
    });
  }

  @override
  Future<Set<String>> presentIds(List<String> firestoreMessageIds) async {
    final ids = _checkedIds(firestoreMessageIds);
    if (ids.isEmpty) return {};
    final result = await _connection.execute(
      'SELECT FirestoreMessageID FROM Messaging '
      'WHERE FirestoreMessageID IN (${_placeholders(ids)})',
      _parameters(ids),
    );
    return {
      for (final row in result.rows)
        if (row.colByName('FirestoreMessageID') case final id?) id,
    };
  }

  @override
  Future<int> markRead(List<String> firestoreMessageIds) async {
    final ids = _checkedIds(firestoreMessageIds);
    if (ids.isEmpty) return 0;
    final result = await _connection.execute(
      'UPDATE Messaging SET IsRead = TRUE '
      'WHERE IsRead = FALSE AND FirestoreMessageID IN (${_placeholders(ids)})',
      _parameters(ids),
    );
    return result.affectedRows.toInt();
  }

  static List<String> _checkedIds(List<String> ids) {
    final unique = ids.toSet().toList();
    if (unique.length > maxChatAuditBatch) {
      throw ArgumentError.value(
        unique.length,
        'firestoreMessageIds',
        'At most $maxChatAuditBatch ids per call',
      );
    }
    unique.forEach(checkChatAuditId);
    return unique;
  }

  // One named parameter per id (:id0, :id1, ...): values never go into the
  // SQL text.
  static String _placeholders(List<String> ids) =>
      [for (var i = 0; i < ids.length; i++) ':id$i'].join(', ');

  static Map<String, Object?> _parameters(List<String> ids) => {
    for (var i = 0; i < ids.length; i++) 'id$i': ids[i],
  };
}

/// "2026-10-24 09:41:00": [time] in UTC, to the second (a MySQL DATETIME).
String mySqlUtcDateTime(DateTime time) {
  final utc = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
}
