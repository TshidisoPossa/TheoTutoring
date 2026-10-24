import 'package:mysql_client/mysql_client.dart';

// Student <-> tutor chat. Who may chat is decided from MySQL
// (ChatPermissions). Messages live in Firestore (chat_store.dart); the
// MySQL Messaging table is only an audit copy (chat_audit.dart).
// Users are identified by `User`.UserId on both sides of a conversation.

/// Longest message a user may send.
const maxChatMessageLength = 2000;

/// Which side of a conversation a signed-in user is on.
enum ChatRole {
  /// A student (StudentProfile).
  student('student', 'StudentProfile'),

  /// A tutor (TutorProfile).
  tutor('tutor', 'TutorProfile');

  const ChatRole(this.value, this._profileTable);

  /// `User`.Role value.
  final String value;

  /// Profile table every user of this role has a row in. A fixed table
  /// name (never user input), so it is safe to put in the SQL text.
  final String _profileTable;

  /// The role on the other side of the conversation.
  ChatRole get other => this == student ? tutor : student;
}

/// A user taking part in a conversation.
class ChatParticipant {
  /// Creates a participant.
  const ChatParticipant({
    required this.userId,
    required this.name,
    required this.role,
    this.firebaseUid,
    this.profilePhoto,
    this.isActive = true,
    this.isPublicTutor = false,
  });

  /// `User`.UserId.
  final int userId;

  /// Display name.
  final String name;

  /// Which side of the conversation they are on.
  final ChatRole role;

  /// `User`.FirebaseUid (where notifications are delivered), if loaded.
  final String? firebaseUid;

  /// Profile photo URL, if any.
  final String? profilePhoto;

  /// `User`.AccountStatus is Active.
  final bool isActive;

  /// An Active, Approved tutor (shown in tutor search, so students may
  /// contact them).
  final bool isPublicTutor;
}

/// The latest message with one other user, for the conversation list.
class ChatConversation {
  /// Creates a conversation entry.
  const ChatConversation({
    required this.conversationId,
    required this.userId,
    required this.name,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    this.profilePhoto,
  });

  /// Firestore conversation id ("s{studentId}_t{tutorId}").
  final String conversationId;

  /// The other user's `User`.UserId.
  final int userId;

  /// The other user's name.
  final String name;

  /// The other user's profile photo URL, if any.
  final String? profilePhoto;

  /// Text of the last message.
  final String lastMessage;

  /// When the last message was sent, in UTC.
  final DateTime lastMessageAt;

  /// Messages from the other user not yet read by the caller.
  final int unreadCount;

  /// JSON for the conversation list; [nowUtc] drives the "2h ago" label.
  Map<String, Object?> toJson(DateTime nowUtc) => {
    'conversationId': conversationId,
    'userId': userId,
    'name': name,
    'initials': chatInitials(name),
    'profilePhotoUrl': profilePhoto,
    'lastMessage': lastMessage,
    'time': chatTimeLabel(lastMessageAt, nowUtc),
    'lastMessageAt': lastMessageAt.toUtc().toIso8601String(),
    'unreadCount': unreadCount,
    // No presence data exists for students, and the student app does not
    // show it for tutors, so nobody is reported as online yet.
    'isOnline': false,
  };
}

/// "Thabo Mokoena" -> "TM", "Thabo" -> "T", "" -> "?"
String chatInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Short "how long ago" label for the conversation list: "Just now",
/// "5m ago", "2h ago", "3d ago", then the date ("24 Oct").
String chatTimeLabel(DateTime sentUtc, DateTime nowUtc) {
  final age = nowUtc.difference(sentUtc);
  if (age.inMinutes < 1) return 'Just now';
  if (age.inHours < 1) return '${age.inMinutes}m ago';
  if (age.inDays < 1) return '${age.inHours}h ago';
  if (age.inDays < 7) return '${age.inDays}d ago';
  return '${sentUtc.day} ${_months[sentUtc.month - 1]}';
}

/// Most users [ChatPermissions.profiles] looks up at once (one page of
/// conversations).
const maxChatProfileLookup = 100;

/// Decides who may chat: accounts, roles, bookings and profiles (MySQL).
abstract interface class ChatPermissions {
  /// The Active user with [role] signed in as [firebaseUid], or null.
  Future<ChatParticipant?> signedIn(String firebaseUid, ChatRole role);

  /// The user [userId] if they have [role] (any account status), or null.
  Future<ChatParticipant?> participant(int userId, ChatRole role);

  /// Whether the student has a booking with the tutor that the tutor can
  /// see. (Whether they have messages is a Firestore question:
  /// FirestoreChatStore.hasConversation.)
  Future<bool> hasBooking({
    required int studentUserId,
    required int tutorUserId,
  });

  /// Whether [bookingId] is a booking between this student and tutor.
  Future<bool> bookingBelongsTo(
    int bookingId, {
    required int studentUserId,
    required int tutorUserId,
  });

  /// Name, photo and Firebase UID of each of [userIds] that has [role],
  /// keyed by user id (users without that role are left out). At most
  /// [maxChatProfileLookup] ids.
  Future<Map<int, ChatParticipant>> profiles(List<int> userIds, ChatRole role);
}

/// [ChatPermissions] from the MySQL `User`, profile and Booking tables.
class MySqlChatPermissions implements ChatPermissions {
  /// Uses the shared [MySQLConnection]; it is not closed here.
  MySqlChatPermissions(this._connection);

  final MySQLConnection _connection;

  // A booking counts once the tutor can see it: legacy bookings, and
  // purchased lessons once paid (same rule as GET /TutorLandingpage/bookings).
  static const _visibleBookingSql = '''
    FROM Booking b
    JOIN StudentProfile s ON s.StudentID = b.StudentID
    JOIN TutorProfile t ON t.TutorID = b.TutorID
    WHERE s.UserID = :studentUserId
      AND t.UserID = :tutorUserId
      AND (b.PurchaseID IS NULL OR b.Status IN ('Confirmed', 'Completed'))
  ''';

  /// Columns for [_participantFrom], selected from `User` u joined to the
  /// role's profile table p. Only fixed SQL is interpolated.
  static String _participantColumns(ChatRole role) =>
      '''
      u.UserId, u.Name, u.ProfilePhoto, u.FirebaseUid,
      u.AccountStatus = 'Active' AS IsActive,
      (${role == ChatRole.tutor ? "p.VerificationStat = 'Approved'" : 'FALSE'})
        AS IsApproved
      FROM `User` u
      JOIN ${role._profileTable} p ON p.UserID = u.UserId''';

  static ChatParticipant _participantFrom(
    Map<String, String?> row,
    ChatRole role,
  ) {
    final isActive = row['IsActive'] == '1';
    return ChatParticipant(
      userId: int.parse(row['UserId']!),
      name: row['Name'] ?? '',
      role: role,
      firebaseUid: row['FirebaseUid'],
      profilePhoto: row['ProfilePhoto'],
      isActive: isActive,
      isPublicTutor: isActive && row['IsApproved'] == '1',
    );
  }

  @override
  Future<ChatParticipant?> signedIn(String firebaseUid, ChatRole role) async {
    final result = await _connection.execute(
      '''
      SELECT ${_participantColumns(role)}
      WHERE u.FirebaseUid = :uid
        AND u.Role = :role
        AND u.AccountStatus = 'Active'
      LIMIT 1
      ''',
      {'uid': firebaseUid, 'role': role.value},
    );
    if (result.rows.isEmpty) return null;
    return _participantFrom(result.rows.first.assoc(), role);
  }

  @override
  Future<ChatParticipant?> participant(int userId, ChatRole role) async {
    final result = await _connection.execute(
      '''
      SELECT ${_participantColumns(role)}
      WHERE u.UserId = :userId AND u.Role = :role
      LIMIT 1
      ''',
      {'userId': userId, 'role': role.value},
    );
    if (result.rows.isEmpty) return null;
    return _participantFrom(result.rows.first.assoc(), role);
  }

  @override
  Future<Map<int, ChatParticipant>> profiles(
    List<int> userIds,
    ChatRole role,
  ) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    if (ids.length > maxChatProfileLookup || ids.any((id) => id <= 0)) {
      throw ArgumentError.value(
        userIds,
        'userIds',
        'Must be 1 to $maxChatProfileLookup positive user ids',
      );
    }
    // One named parameter per id (:id0, :id1, ...): values are never
    // placed in the SQL text.
    final result = await _connection.execute(
      '''
      SELECT ${_participantColumns(role)}
      WHERE u.Role = :role
        AND u.UserId IN (${[for (var i = 0; i < ids.length; i++) ':id$i'].join(', ')})
      ''',
      {
        'role': role.value,
        for (var i = 0; i < ids.length; i++) 'id$i': ids[i],
      },
    );
    return {
      for (final row in result.rows)
        int.parse(row.assoc()['UserId']!): _participantFrom(row.assoc(), role),
    };
  }

  @override
  Future<bool> hasBooking({
    required int studentUserId,
    required int tutorUserId,
  }) async {
    final result = await _connection.execute(
      'SELECT 1 $_visibleBookingSql LIMIT 1',
      {'studentUserId': studentUserId, 'tutorUserId': tutorUserId},
    );
    return result.rows.isNotEmpty;
  }

  @override
  Future<bool> bookingBelongsTo(
    int bookingId, {
    required int studentUserId,
    required int tutorUserId,
  }) async {
    final result = await _connection.execute(
      'SELECT 1 $_visibleBookingSql AND b.Booking_id = :bookingId LIMIT 1',
      {
        'studentUserId': studentUserId,
        'tutorUserId': tutorUserId,
        'bookingId': bookingId,
      },
    );
    return result.rows.isNotEmpty;
  }
}
