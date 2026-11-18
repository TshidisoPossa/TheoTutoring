import 'package:theo_tutoring_backend/firestore_rest.dart';

// Chat moderation: students and tutors may not swap contact details
// (emails, phone numbers, other apps) or send abusive words in chat.
//
// [screenChatMessage] checks every message on the server before it is
// saved. A blocked message is never stored in the conversation, so the
// recipient never gets it. Instead the sender's chat is suspended (sending
// only; they can still read), the message is kept here for the admins, and
// the admins are told. The sender can send one explanation (an appeal);
// an admin then lifts the suspension or keeps it.
//
// One record per user, in Firestore next to the chats:
//   chatModeration/user-{UserId}
// status: suspended -> appealed -> lifted | upheld (still suspended)

/// Why a message was blocked.
class ChatModerationVerdict {
  const ChatModerationVerdict(this.category, this.reason);

  /// email, phone, contact_app, off_platform or abusive.
  final String category;

  /// What the sender and the admin see, e.g. "an email address".
  final String reason;
}

final _email = RegExp(
  r'[A-Za-z0-9._%+-]+\s*@\s*[A-Za-z0-9-]+(\s*\.\s*[A-Za-z]{2,})+',
);

// "lerato at gmail dot com", "lerato (at) gmail [dot] com"
final _spelledEmail = RegExp(
  r'\b[a-z0-9._-]+\s*[\(\[]?\s*at\s*[\)\]]?\s*[a-z0-9-]+\s*[\(\[]?\s*dot\s*'
  r'[\)\]]?\s*(com|co|za|net|org|edu|ac)\b',
  caseSensitive: false,
);

// Runs of digits that may be split by spaces, dashes, dots or brackets
final _digitRun = RegExp(r'\+?\(?\d[\d\s().\-]{6,}\d');

const _numberWords = {
  'zero', 'oh', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
  'eight', 'nine',
};

/// Apps and channels for talking outside TheoTutoring.
const _contactApps = [
  'whatsapp', 'whats app', 'telegram', 'signal app', 'instagram', 'insta',
  'snapchat', 'snap me', 'facebook', 'messenger', 'tiktok', 'twitter',
  'skype', 'discord', 'linkedin',
];

/// Phrases asking to move the conversation or payment off the platform.
const _offPlatformPhrases = [
  'my number is', 'my cell is', 'my phone number', 'call me on',
  'text me on', 'sms me', 'dm me', 'email me at', 'my email is',
  'contact me directly', 'reach me on', 'pay me directly', 'pay me cash',
  'pay outside', 'outside the app', 'outside the platform',
  'off the platform', 'eft me', 'send money to',
];

/// Abusive words (whole words only).
const _abusiveWords = [
  'fuck', 'fucking', 'fucker', 'shit', 'bitch', 'bastard', 'asshole',
  'dick', 'cunt', 'whore', 'slut', 'nigga', 'nigger', 'kaffir', 'faggot',
  'retard', 'moron', 'idiot', 'stupid', 'dumbass', 'poes', 'naai',
];

String _normalise(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Null when [text] may be sent; otherwise why it is blocked.
ChatModerationVerdict? screenChatMessage(String text) {
  if (_email.hasMatch(text) || _spelledEmail.hasMatch(text)) {
    return const ChatModerationVerdict('email', 'an email address');
  }
  for (final match in _digitRun.allMatches(text)) {
    final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9 && digits.length <= 15) {
      return const ChatModerationVerdict('phone', 'a phone number');
    }
  }
  // "zero eight two five five five ..." spelled out
  final words = _normalise(text).split(RegExp(r'[^a-z0-9]+'));
  var run = 0;
  for (final w in words) {
    run = _numberWords.contains(w) || RegExp(r'^\d$').hasMatch(w) ? run + 1 : 0;
    if (run >= 7) {
      return const ChatModerationVerdict('phone', 'a phone number');
    }
  }

  final normal = _normalise(text);
  final spaced = ' ${normal.replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
  for (final app in _contactApps) {
    if (spaced.contains(' $app ')) {
      return const ChatModerationVerdict(
        'contact_app',
        'a request to talk on another app',
      );
    }
  }
  for (final phrase in _offPlatformPhrases) {
    if (spaced.contains(' $phrase ')) {
      return const ChatModerationVerdict(
        'off_platform',
        'a request to talk or pay outside TheoTutoring',
      );
    }
  }
  for (final word in _abusiveWords) {
    if (spaced.contains(' $word ')) {
      return const ChatModerationVerdict('abusive', 'abusive language');
    }
  }
  return null;
}

/// Moderation states.
abstract final class ChatModerationStatus {
  /// Blocked message, waiting for the user's explanation or an admin.
  static const suspended = 'suspended';

  /// The user explained; waiting for an admin.
  static const appealed = 'appealed';

  /// An admin lifted the suspension: chat works again.
  static const lifted = 'lifted';

  /// An admin kept the suspension.
  static const upheld = 'upheld';

  /// States in which the user may not send messages.
  static const blocking = {suspended, appealed, upheld};
}

/// One user's moderation record.
class ChatModerationRecord {
  const ChatModerationRecord({
    required this.userId,
    required this.role,
    required this.name,
    required this.status,
    required this.category,
    required this.reason,
    required this.flaggedText,
    required this.otherUserId,
    required this.otherName,
    required this.flaggedAt,
    this.flagCount = 1,
    this.appeal,
    this.appealedAt,
    this.decidedAt,
    this.decidedBy,
    this.decisionNote,
  });

  factory ChatModerationRecord.fromFields(Map<String, Object?> f) =>
      ChatModerationRecord(
        userId: (f['userId'] as num?)?.toInt() ?? 0,
        role: f['role'] as String? ?? '',
        name: f['name'] as String? ?? '',
        status: f['status'] as String? ?? ChatModerationStatus.suspended,
        category: f['category'] as String? ?? '',
        reason: f['reason'] as String? ?? '',
        flaggedText: f['flaggedText'] as String? ?? '',
        otherUserId: (f['otherUserId'] as num?)?.toInt() ?? 0,
        otherName: f['otherName'] as String? ?? '',
        flaggedAt: f['flaggedAt'] as DateTime? ?? DateTime.utc(1970),
        flagCount: (f['flagCount'] as num?)?.toInt() ?? 1,
        appeal: f['appeal'] as String?,
        appealedAt: f['appealedAt'] as DateTime?,
        decidedAt: f['decidedAt'] as DateTime?,
        decidedBy: f['decidedBy'] as String?,
        decisionNote: f['decisionNote'] as String?,
      );

  final int userId;
  final String role; // student or tutor
  final String name;
  final String status;
  final String category;
  final String reason;
  final String flaggedText;
  final int otherUserId;
  final String otherName;
  final DateTime flaggedAt;

  /// How many messages this user has had blocked in total.
  final int flagCount;
  final String? appeal;
  final DateTime? appealedAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final String? decisionNote;

  /// Whether the user may not send messages.
  bool get isSuspended => ChatModerationStatus.blocking.contains(status);

  /// Whether the user may send an explanation now.
  bool get canAppeal =>
      status == ChatModerationStatus.suspended ||
      status == ChatModerationStatus.upheld;

  Map<String, Object?> toFields() => {
    'userId': userId,
    'role': role,
    'name': name,
    'status': status,
    'category': category,
    'reason': reason,
    'flaggedText': flaggedText,
    'otherUserId': otherUserId,
    'otherName': otherName,
    'flaggedAt': flaggedAt,
    'flagCount': flagCount,
    'appeal': appeal,
    'appealedAt': appealedAt,
    'decidedAt': decidedAt,
    'decidedBy': decidedBy,
    'decisionNote': decisionNote,
  };

  /// What the user sees about their own chat.
  Map<String, Object?> toOwnerJson() => {
    'suspended': isSuspended,
    'status': status,
    'reason': reason,
    'canAppeal': canAppeal,
    'appeal': appeal,
    'flaggedAt': flaggedAt.toUtc().toIso8601String(),
    'decisionNote': decisionNote,
  };

  /// What admins see.
  Map<String, Object?> toAdminJson() => {
    'userId': userId,
    'role': role,
    'name': name,
    'status': status,
    'category': category,
    'reason': reason,
    'flaggedText': flaggedText,
    'otherUserId': otherUserId,
    'otherName': otherName,
    'flaggedAt': flaggedAt.toUtc().toIso8601String(),
    'flagCount': flagCount,
    'appeal': appeal,
    'appealedAt': appealedAt?.toUtc().toIso8601String(),
    'decidedAt': decidedAt?.toUtc().toIso8601String(),
    'decidedBy': decidedBy,
    'decisionNote': decisionNote,
  };

  ChatModerationRecord copyWith({
    String? status,
    String? appeal,
    DateTime? appealedAt,
    DateTime? decidedAt,
    String? decidedBy,
    String? decisionNote,
  }) => ChatModerationRecord(
    userId: userId,
    role: role,
    name: name,
    status: status ?? this.status,
    category: category,
    reason: reason,
    flaggedText: flaggedText,
    otherUserId: otherUserId,
    otherName: otherName,
    flaggedAt: flaggedAt,
    flagCount: flagCount,
    appeal: appeal ?? this.appeal,
    appealedAt: appealedAt ?? this.appealedAt,
    decidedAt: decidedAt ?? this.decidedAt,
    decidedBy: decidedBy ?? this.decidedBy,
    decisionNote: decisionNote ?? this.decisionNote,
  );
}

/// Thrown when a moderation action is not allowed now.
class ChatModerationException implements Exception {
  const ChatModerationException(this.statusCode, this.message);

  final int statusCode;
  final String message;
}

/// Where moderation records are kept (Firestore in the app, a fake in
/// tests).
abstract interface class ChatModerationStore {
  /// The user's record, or null if they were never flagged.
  Future<ChatModerationRecord?> get(int userId);

  /// Several users at once; users never flagged are left out.
  Future<Map<int, ChatModerationRecord>> getMany(Iterable<int> userIds);

  /// Saves (replaces) a record.
  Future<void> save(ChatModerationRecord record);

  /// Every record, newest flag first.
  Future<List<ChatModerationRecord>> all();
}

/// Records in Firestore: chatModeration/user-{UserId}.
class FirestoreChatModerationStore implements ChatModerationStore {
  FirestoreChatModerationStore(this._rest);

  final FirestoreRest _rest;

  static const collection = 'chatModeration';
  static String path(int userId) => '$collection/user-$userId';

  @override
  Future<ChatModerationRecord?> get(int userId) async {
    final doc = await _rest.get(path(userId));
    return doc == null ? null : ChatModerationRecord.fromFields(doc.fields);
  }

  @override
  Future<Map<int, ChatModerationRecord>> getMany(Iterable<int> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    final docs = await _rest.batchGet([for (final id in ids) path(id)]);
    return {
      for (final id in ids)
        if (docs[path(id)] case final doc?)
          id: ChatModerationRecord.fromFields(doc.fields),
    };
  }

  @override
  Future<void> save(ChatModerationRecord record) async {
    await _rest.commit([
      FirestoreWrite.update(path(record.userId), record.toFields()),
    ]);
  }

  @override
  Future<List<ChatModerationRecord>> all() async {
    final docs = await _rest.runQuery({
      'from': [
        {'collectionId': collection},
      ],
      'orderBy': [
        {
          'field': {'fieldPath': 'flaggedAt'},
          'direction': 'DESCENDING',
        },
      ],
      'limit': 200,
    });
    return [for (final d in docs) ChatModerationRecord.fromFields(d.fields)];
  }
}

/// Records a blocked message for [userId]: suspends their chat (or keeps it
/// suspended) and remembers the message for the admins.
Future<ChatModerationRecord> flagChatMessage(
  ChatModerationStore store, {
  required int userId,
  required String role,
  required String name,
  required int otherUserId,
  required String otherName,
  required String text,
  required ChatModerationVerdict verdict,
  required DateTime now,
}) async {
  final previous = await store.get(userId);
  final record = ChatModerationRecord(
    userId: userId,
    role: role,
    name: name,
    status: ChatModerationStatus.suspended,
    category: verdict.category,
    reason: verdict.reason,
    flaggedText: text,
    otherUserId: otherUserId,
    otherName: otherName,
    flaggedAt: now,
    flagCount: (previous?.flagCount ?? 0) + 1,
  );
  await store.save(record);
  return record;
}

/// The suspended user's explanation ([explanation], 10 to 1000 characters).
Future<ChatModerationRecord> appealChatSuspension(
  ChatModerationStore store, {
  required int userId,
  required String explanation,
  required DateTime now,
}) async {
  final text = explanation.trim();
  if (text.length < 10 || text.length > 1000) {
    throw const ChatModerationException(
      400,
      'Please write an explanation of 10 to 1000 characters.',
    );
  }
  final record = await store.get(userId);
  if (record == null || !record.isSuspended) {
    throw const ChatModerationException(
      409,
      'Your chat is not suspended.',
    );
  }
  if (!record.canAppeal) {
    throw const ChatModerationException(
      409,
      'Your explanation has already been sent. An admin will review it.',
    );
  }
  final updated = record.copyWith(
    status: ChatModerationStatus.appealed,
    appeal: text,
    appealedAt: now,
  );
  await store.save(updated);
  return updated;
}

/// An admin's decision: [lift] restores chat, otherwise it stays suspended.
Future<ChatModerationRecord> decideChatSuspension(
  ChatModerationStore store, {
  required int userId,
  required bool lift,
  required String adminName,
  String? note,
  required DateTime now,
}) async {
  final record = await store.get(userId);
  if (record == null) {
    throw const ChatModerationException(404, 'No chat flag for this user.');
  }
  if (!record.isSuspended) {
    throw const ChatModerationException(
      409,
      "This user's chat is not suspended.",
    );
  }
  final trimmed = note?.trim();
  final updated = record.copyWith(
    status: lift ? ChatModerationStatus.lifted : ChatModerationStatus.upheld,
    decidedAt: now,
    decidedBy: adminName,
    decisionNote: trimmed == null || trimmed.isEmpty ? null : trimmed,
  );
  await store.save(updated);
  return updated;
}
