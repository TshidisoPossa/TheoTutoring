import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';

// Firestore is the chat store (MySQL Messaging is an audit copy, written
// later from the outbox). Layout:
//
//   system/chatConfig                         {enabled}
//   conversations/s{studentId}_t{tutorId}     counters + last message
//   conversations/{cid}/messages/{senderId}-{clientMessageId}
//   chatOutbox/m_{cid}_{messageId}            audit this message
//   chatOutbox/r_{cid}_{role}                 audit read state up to target
//   chatOutbox/n_{cid}_{seq}                  notify the receiver
//
// Counters, for roles A (author) and B (the other side):
//   sent.A        messages A has written
//   readCount.B   how many of A's messages B has read (oldest first)
//   unread.B      sent.A - readCount.B
//   message.counts  both sent values right after that message
// A message from A is read when counts.A <= readCount.B.
//
// Sends and mark-reads are read-write transactions: every document they
// depend on, including system/chatConfig, is read inside the transaction,
// and every write carries a server-checked precondition. The decisions are
// pure functions (planChatSend, planChatMarkRead) so they can be tested
// without Firestore.
//
// Times (sentAt, lastSentAt, firstPendingAt) come from this backend's
// clock, written as explicit values: FirestoreRest does not return the
// value Firestore stores for a server-time transform, and commitTime is
// not documented to equal it. `seq`, not time, orders messages.

/// Firestore document that switches chat on (`enabled: true`). Missing or
/// anything else means chat is off.
const chatConfigPath = 'system/chatConfig';

/// Messages per page.
const chatMessagePageSize = 100;

/// Conversations per page.
const chatConversationPageSize = 100;

/// Most conversation pages [FirestoreChatStore.unreadTotal] adds up.
const chatUnreadPageLimit = 10;

/// Longest last-message preview kept on a conversation.
const chatPreviewLength = 200;

final _clientMessageId = RegExp(r'^[A-Za-z0-9_-]{16,64}$');
final _messageId = RegExp(r'^[0-9]{1,10}-[A-Za-z0-9_-]{16,64}$');

/// "s10_t1": the conversation between student 10 and tutor 1.
String chatConversationId(int studentUserId, int tutorUserId) =>
    's${studentUserId}_t$tutorUserId';

/// "10-<clientMessageId>": unique per sender, so a retried send finds it.
String chatMessageId(int senderUserId, String clientMessageId) =>
    '$senderUserId-$clientMessageId';

String _conversationPath(String cid) => 'conversations/$cid';
String _messagePath(String cid, String messageId) =>
    'conversations/$cid/messages/$messageId';
String _messageOutboxPath(String cid, String messageId) =>
    'chatOutbox/m_${cid}_$messageId';
String _readOutboxPath(String cid, ChatRole reader) =>
    'chatOutbox/r_${cid}_${reader.value}';
String _notifyOutboxPath(String cid, int seq) => 'chatOutbox/n_${cid}_$seq';

// ─── Errors ─────────────────────────────────────────────────────────────────

/// A chat store request could not be done as asked.
class ChatStoreException implements Exception {
  /// Creates the exception.
  const ChatStoreException(this.message);

  /// What went wrong (safe to show).
  final String message;

  @override
  String toString() => 'ChatStoreException: $message';
}

/// Chat is switched off (system/chatConfig missing or not enabled).
class ChatDisabled extends ChatStoreException {
  /// Creates the exception.
  const ChatDisabled() : super('Chat is currently unavailable.');
}

/// The clientMessageId was already used for a different message.
class ChatDuplicateConflict extends ChatStoreException {
  /// Creates the exception.
  const ChatDuplicateConflict()
    : super('clientMessageId was already used for a different message.');
}

/// The conversation or message does not exist.
class ChatNotFound extends ChatStoreException {
  /// Creates the exception.
  const ChatNotFound(super.message);
}

/// Stored chat data is not in the expected shape.
class ChatDataException extends ChatStoreException {
  /// Creates the exception.
  const ChatDataException(super.message);
}

// ─── Commands and stored values ─────────────────────────────────────────────

/// One side of a conversation.
class ChatParty {
  /// Creates a party. [firebaseUid] receives notifications.
  ChatParty({required this.userId, required this.firebaseUid}) {
    if (userId <= 0 || firebaseUid.trim().isEmpty) {
      throw ArgumentError('A chat party needs a user id and Firebase UID.');
    }
  }

  /// `User`.UserId.
  final int userId;

  /// `User`.FirebaseUid.
  final String firebaseUid;
}

/// A request to send one message (already authorised by the caller).
class ChatSendCommand {
  /// Creates a command. Throws an [ArgumentError] for invalid input; the
  /// text is trimmed.
  ChatSendCommand({
    required this.student,
    required this.tutor,
    required this.senderRole,
    required this.clientMessageId,
    required String text,
    required this.senderName,
    this.bookingId,
  }) : text = text.trim() {
    if (student.userId == tutor.userId) {
      throw ArgumentError('A student cannot chat with themselves.');
    }
    if (!_clientMessageId.hasMatch(clientMessageId)) {
      throw ArgumentError.value(
        clientMessageId,
        'clientMessageId',
        'Must be 16-64 letters, digits, "_" or "-"',
      );
    }
    if (this.text.isEmpty || this.text.length > maxChatMessageLength) {
      throw ArgumentError(
        'text must be 1 to $maxChatMessageLength characters.',
      );
    }
    if (bookingId != null && bookingId! <= 0) {
      throw ArgumentError.value(bookingId, 'bookingId', 'Must be positive');
    }
  }

  /// The student.
  final ChatParty student;

  /// The tutor.
  final ChatParty tutor;

  /// Who is sending.
  final ChatRole senderRole;

  /// Chosen by the app; the same id on a retry finds the first send.
  final String clientMessageId;

  /// The message, trimmed.
  final String text;

  /// Shown in the "New message from …" notification (never the text).
  final String senderName;

  /// The booking the message is about, if any.
  final int? bookingId;

  /// The sender.
  ChatParty get sender => senderRole == ChatRole.student ? student : tutor;

  /// The receiver.
  ChatParty get receiver => senderRole == ChatRole.student ? tutor : student;

  /// Conversation id.
  String get conversationId => chatConversationId(student.userId, tutor.userId);

  /// Message id.
  String get messageId => chatMessageId(sender.userId, clientMessageId);
}

/// A request to mark messages read, up to and including one message.
class ChatReadCommand {
  /// Creates a command. Throws an [ArgumentError] for invalid input.
  ChatReadCommand({
    required this.studentUserId,
    required this.tutorUserId,
    required this.readerRole,
    required this.upToMessageId,
  }) {
    if (studentUserId <= 0 ||
        tutorUserId <= 0 ||
        studentUserId == tutorUserId) {
      throw ArgumentError('A read needs two different users.');
    }
    if (!_messageId.hasMatch(upToMessageId)) {
      throw ArgumentError.value(
        upToMessageId,
        'upToMessageId',
        'Not a message id',
      );
    }
  }

  /// The student's user id.
  final int studentUserId;

  /// The tutor's user id.
  final int tutorUserId;

  /// Who is reading.
  final ChatRole readerRole;

  /// Last message the reader has seen.
  final String upToMessageId;

  /// Conversation id.
  String get conversationId => chatConversationId(studentUserId, tutorUserId);
}

/// Per-role counter pair.
typedef ChatCounts = ({int student, int tutor});

int _of(ChatCounts counts, ChatRole role) =>
    role == ChatRole.student ? counts.student : counts.tutor;

ChatCounts _with(ChatCounts counts, ChatRole role, int value) =>
    role == ChatRole.student
    ? (student: value, tutor: counts.tutor)
    : (student: counts.student, tutor: value);

Map<String, Object?> _countsFields(ChatCounts c) => {
  'student': c.student,
  'tutor': c.tutor,
};

/// A conversation document.
class ChatConversationState {
  /// Creates a state.
  const ChatConversationState({
    required this.studentUserId,
    required this.tutorUserId,
    required this.studentUid,
    required this.tutorUid,
    required this.lastSeq,
    required this.lastMessage,
    required this.lastSenderId,
    required this.lastSentAt,
    required this.sent,
    required this.readCount,
    required this.unread,
    required this.createdAt,
    this.updateTime,
  });

  /// Reads a stored conversation; throws a [ChatDataException] if it is
  /// malformed, or stored at a path that does not match its user ids.
  factory ChatConversationState.fromDocument(FirestoreDocument document) {
    final f = document.fields;
    final state = ChatConversationState(
      studentUserId: _int(f, 'studentUserId', min: 1),
      tutorUserId: _int(f, 'tutorUserId', min: 1),
      studentUid: _string(f, 'studentUid'),
      tutorUid: _string(f, 'tutorUid'),
      lastSeq: _int(f, 'lastSeq'),
      lastMessage: _string(f, 'lastMessage', allowEmpty: true),
      lastSenderId: _int(f, 'lastSenderId'),
      lastSentAt: _time(f, 'lastSentAt'),
      sent: _counts(f, 'sent'),
      readCount: _counts(f, 'readCount'),
      unread: _counts(f, 'unread'),
      createdAt: _time(f, 'createdAt'),
      updateTime: document.updateTime,
    );
    final expected = _conversationPath(
      chatConversationId(state.studentUserId, state.tutorUserId),
    );
    final consistent =
        document.path == expected &&
        state.sent.student + state.sent.tutor == state.lastSeq &&
        state.readCount.student <= state.sent.tutor &&
        state.readCount.tutor <= state.sent.student;
    if (!consistent) {
      throw ChatDataException('Conversation ${document.path} is malformed.');
    }
    return state;
  }

  /// Student's user id.
  final int studentUserId;

  /// Tutor's user id.
  final int tutorUserId;

  /// Student's Firebase UID.
  final String studentUid;

  /// Tutor's Firebase UID.
  final String tutorUid;

  /// Sequence number of the latest message (0 before the first).
  final int lastSeq;

  /// Preview of the latest message.
  final String lastMessage;

  /// Sender of the latest message.
  final int lastSenderId;

  /// When the latest message was sent (backend clock, UTC).
  final DateTime lastSentAt;

  /// Messages each side has written.
  final ChatCounts sent;

  /// How many of the other side's messages each side has read.
  final ChatCounts readCount;

  /// Unread messages for each side.
  final ChatCounts unread;

  /// When the conversation started.
  final DateTime createdAt;

  /// Firestore's update time when read (null for a new conversation).
  final String? updateTime;

  /// Conversation id.
  String get conversationId => chatConversationId(studentUserId, tutorUserId);

  /// Whether [message] has been read by its receiver.
  bool isRead(StoredChatMessage message) =>
      _of(message.counts, message.senderRole) <=
      _of(readCount, message.senderRole.other);

  Map<String, Object?> _toFields() => {
    'studentUserId': studentUserId,
    'tutorUserId': tutorUserId,
    'studentUid': studentUid,
    'tutorUid': tutorUid,
    'lastSeq': lastSeq,
    'lastMessage': lastMessage,
    'lastSenderId': lastSenderId,
    'lastSentAt': lastSentAt,
    'sent': _countsFields(sent),
    'readCount': _countsFields(readCount),
    'unread': _countsFields(unread),
    'createdAt': createdAt,
  };
}

/// A stored message.
class StoredChatMessage {
  /// Creates a message.
  const StoredChatMessage({
    required this.messageId,
    required this.conversationId,
    required this.seq,
    required this.senderId,
    required this.receiverId,
    required this.senderRole,
    required this.text,
    required this.sentAt,
    required this.counts,
    this.bookingId,
  });

  /// Reads a stored message; throws a [ChatDataException] if malformed.
  factory StoredChatMessage.fromDocument(FirestoreDocument document) {
    final segments = document.path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'conversations' ||
        segments[2] != 'messages') {
      throw ChatDataException('${document.path} is not a message.');
    }
    final f = document.fields;
    final role = switch (f['senderRole']) {
      'student' => ChatRole.student,
      'tutor' => ChatRole.tutor,
      _ => throw ChatDataException('Message ${document.path} has no role.'),
    };
    final bookingId = f['bookingId'];
    if (bookingId != null && (bookingId is! int || bookingId <= 0)) {
      throw ChatDataException('Message ${document.path} has a bad booking.');
    }
    final message = StoredChatMessage(
      messageId: segments[3],
      conversationId: segments[1],
      seq: _int(f, 'seq', min: 1),
      senderId: _int(f, 'senderId', min: 1),
      receiverId: _int(f, 'receiverId', min: 1),
      senderRole: role,
      text: _string(f, 'text'),
      sentAt: _time(f, 'sentAt'),
      counts: _counts(f, 'counts'),
      bookingId: bookingId as int?,
    );
    if (!message.messageId.startsWith('${message.senderId}-') ||
        _of(message.counts, role) < 1) {
      throw ChatDataException('Message ${document.path} is malformed.');
    }
    return message;
  }

  /// Document id ("{senderId}-{clientMessageId}").
  final String messageId;

  /// Conversation id.
  final String conversationId;

  /// Position in the conversation (1, 2, 3, …).
  final int seq;

  /// Sender's user id.
  final int senderId;

  /// Receiver's user id.
  final int receiverId;

  /// Sender's side.
  final ChatRole senderRole;

  /// The message.
  final String text;

  /// When it was sent (backend clock, UTC).
  final DateTime sentAt;

  /// Both sides' sent counts right after this message.
  final ChatCounts counts;

  /// The booking it is about, if any.
  final int? bookingId;

  Map<String, Object?> _toFields() => {
    'seq': seq,
    'senderId': senderId,
    'receiverId': receiverId,
    'senderRole': senderRole.value,
    'text': text,
    'bookingId': bookingId,
    'sentAt': sentAt,
    'counts': _countsFields(counts),
  };
}

// ─── Planners (pure) ────────────────────────────────────────────────────────

/// What a send should do, decided from the documents read in its
/// transaction.
sealed class ChatSendPlan {}

/// Do not write: chat is off, or the clientMessageId is taken.
final class ChatSendRefused extends ChatSendPlan {
  /// Refuses with [error].
  ChatSendRefused(this.error);

  /// Why.
  final ChatStoreException error;
}

/// The message was already sent with this clientMessageId and content.
final class ChatSendReplay extends ChatSendPlan {
  /// Replays [message].
  ChatSendReplay(this.message);

  /// The stored message.
  final StoredChatMessage message;
}

/// Commit [writes] to store [message].
final class ChatSendWrite extends ChatSendPlan {
  /// Writes [message].
  ChatSendWrite(this.writes, this.message, {required this.notify});

  /// Writes, each with a precondition.
  final List<FirestoreWrite> writes;

  /// The new message.
  final StoredChatMessage message;

  /// Whether this starts an unread burst (a notification is queued).
  final bool notify;
}

/// Decides a send from [config], the [conversation] and the [existing]
/// message with the same id (each null if missing), at time [now].
ChatSendPlan planChatSend({
  required FirestoreDocument? config,
  required FirestoreDocument? conversation,
  required FirestoreDocument? existing,
  required ChatSendCommand command,
  required DateTime now,
}) {
  if (!_enabled(config)) return ChatSendRefused(const ChatDisabled());

  final cid = command.conversationId;
  final state = conversation == null
      ? null
      : ChatConversationState.fromDocument(conversation);
  if (state != null &&
      (state.studentUid != command.student.firebaseUid ||
          state.tutorUid != command.tutor.firebaseUid)) {
    // Accounts are never re-linked to other Firebase users; refuse rather
    // than notify the wrong person.
    throw ChatDataException('Conversation $cid has different users.');
  }

  if (existing != null) {
    final stored = StoredChatMessage.fromDocument(existing);
    final same =
        stored.senderId == command.sender.userId &&
        stored.receiverId == command.receiver.userId &&
        stored.text == command.text &&
        stored.bookingId == command.bookingId;
    return same
        ? ChatSendReplay(stored)
        : ChatSendRefused(const ChatDuplicateConflict());
  }

  final a = command.senderRole;
  final b = a.other;
  final time = now.toUtc();
  const zero = (student: 0, tutor: 0);
  final sentBefore = state?.sent ?? zero;
  final readCount = state?.readCount ?? zero;
  final sent = _with(sentBefore, a, _of(sentBefore, a) + 1);
  final unreadBefore = _of(sentBefore, a) - _of(readCount, b);
  final unread = (
    student: sent.tutor - readCount.student,
    tutor: sent.student - readCount.tutor,
  );
  final seq = (state?.lastSeq ?? 0) + 1;

  final message = StoredChatMessage(
    messageId: command.messageId,
    conversationId: cid,
    seq: seq,
    senderId: command.sender.userId,
    receiverId: command.receiver.userId,
    senderRole: a,
    text: command.text,
    sentAt: time,
    counts: sent,
    bookingId: command.bookingId,
  );
  final next = ChatConversationState(
    studentUserId: command.student.userId,
    tutorUserId: command.tutor.userId,
    studentUid: command.student.firebaseUid,
    tutorUid: command.tutor.firebaseUid,
    lastSeq: seq,
    lastMessage: command.text.length <= chatPreviewLength
        ? command.text
        : command.text.substring(0, chatPreviewLength),
    lastSenderId: command.sender.userId,
    lastSentAt: time,
    sent: sent,
    readCount: readCount,
    unread: unread,
    createdAt: state?.createdAt ?? time,
  );
  final notify = unreadBefore == 0;

  return ChatSendWrite(
    [
      FirestoreWrite.update(
        _messagePath(cid, message.messageId),
        message._toFields(),
        precondition: FirestorePrecondition.mustNotExist,
      ),
      FirestoreWrite.update(
        _conversationPath(cid),
        next._toFields(),
        precondition: state == null
            ? FirestorePrecondition.mustNotExist
            : FirestorePrecondition.updateTime(state.updateTime!),
      ),
      FirestoreWrite.update(
        _messageOutboxPath(cid, message.messageId),
        {
          'kind': 'message',
          'conversationId': cid,
          'messageId': message.messageId,
          'firstPendingAt': time,
        },
        precondition: FirestorePrecondition.mustNotExist,
      ),
      if (notify)
        FirestoreWrite.update(
          _notifyOutboxPath(cid, seq),
          {
            'kind': 'notify',
            'conversationId': cid,
            'messageId': message.messageId,
            'seq': seq,
            'receiverUserId': command.receiver.userId,
            'receiverUid': command.receiver.firebaseUid,
            'senderName': command.senderName,
            'firstPendingAt': time,
          },
          precondition: FirestorePrecondition.mustNotExist,
        ),
    ],
    message,
    notify: notify,
  );
}

/// What a mark-read should do.
sealed class ChatReadPlan {}

/// Do not write: chat is off, or the conversation or message is missing.
final class ChatReadRefused extends ChatReadPlan {
  /// Refuses with [error].
  ChatReadRefused(this.error);

  /// Why.
  final ChatStoreException error;
}

/// Nothing changes (already read that far).
final class ChatReadUnchanged extends ChatReadPlan {
  /// Nothing to write.
  ChatReadUnchanged(this.unread);

  /// The reader's unread count.
  final int unread;
}

/// Commit [writes] to move the reader's read count forward.
final class ChatReadWrite extends ChatReadPlan {
  /// Moves the read count.
  ChatReadWrite(this.writes, {required this.markedRead, required this.unread});

  /// Writes, each with a precondition.
  final List<FirestoreWrite> writes;

  /// How many more messages are now read.
  final int markedRead;

  /// The reader's unread count afterwards.
  final int unread;
}

/// Decides a mark-read from the documents read in its transaction:
/// [config], the [conversation], the [upTo] message and the reader's
/// [readOutbox] entry (each null if missing).
ChatReadPlan planChatMarkRead({
  required FirestoreDocument? config,
  required FirestoreDocument? conversation,
  required FirestoreDocument? upTo,
  required FirestoreDocument? readOutbox,
  required ChatReadCommand command,
  required DateTime now,
}) {
  if (!_enabled(config)) return ChatReadRefused(const ChatDisabled());
  if (conversation == null) {
    return ChatReadRefused(const ChatNotFound('Conversation not found.'));
  }
  if (upTo == null) {
    return ChatReadRefused(
      const ChatNotFound('upToMessageId is not in this conversation.'),
    );
  }
  final state = ChatConversationState.fromDocument(conversation);
  final message = StoredChatMessage.fromDocument(upTo);
  if (state.studentUserId != command.studentUserId ||
      state.tutorUserId != command.tutorUserId ||
      message.conversationId != state.conversationId ||
      message.seq > state.lastSeq) {
    throw ChatDataException('Message ${upTo.path} does not fit its chat.');
  }

  final r = command.readerRole;
  final o = r.other;
  final oldRead = _of(state.readCount, r);
  final sentByOther = _of(state.sent, o);
  // Never backwards, never past what the other side has sent.
  final newRead = [
    oldRead,
    _of(message.counts, o),
  ].reduce((x, y) => x > y ? x : y).clamp(0, sentByOther);
  final unread = sentByOther - newRead;
  if (newRead == oldRead) return ChatReadUnchanged(unread);

  final cid = state.conversationId;
  final role = r.value;
  final entry = readOutbox?.fields;
  return ChatReadWrite(
    [
      FirestoreWrite.update(
        _conversationPath(cid),
        {
          'readCount': {role: newRead},
          'unread': {role: unread},
        },
        updateMask: ['readCount.$role', 'unread.$role'],
        precondition: FirestorePrecondition.updateTime(state.updateTime!),
      ),
      if (readOutbox == null)
        FirestoreWrite.update(
          _readOutboxPath(cid, r),
          {
            'kind': 'read',
            'conversationId': cid,
            'readerRole': role,
            'target': newRead,
            'doneThrough': oldRead,
            'firstPendingAt': now.toUtc(),
          },
          precondition: FirestorePrecondition.mustNotExist,
        )
      else if (entry!['target'] is! int)
        throw ChatDataException('Read outbox ${readOutbox.path} is malformed.')
      else
        FirestoreWrite.update(
          _readOutboxPath(cid, r),
          {'target': newRead},
          updateMask: const ['target'],
          precondition: FirestorePrecondition.updateTime(
            readOutbox.updateTime,
          ),
        ),
    ],
    markedRead: newRead - oldRead,
    unread: unread,
  );
}

bool _enabled(FirestoreDocument? config) => config?.fields['enabled'] == true;

// ─── Store ──────────────────────────────────────────────────────────────────

/// The result of [FirestoreChatStore.send].
class ChatSendResult {
  /// Creates a result.
  const ChatSendResult(this.message, {required this.created});

  /// The stored message.
  final StoredChatMessage message;

  /// False when this was a repeat of an earlier send.
  final bool created;
}

/// The result of [FirestoreChatStore.markRead].
class ChatMarkReadResult {
  /// Creates a result.
  const ChatMarkReadResult({required this.markedRead, required this.unread});

  /// How many more messages are now read.
  final int markedRead;

  /// The reader's unread count afterwards.
  final int unread;
}

/// One page of messages, oldest first.
class ChatMessagePage {
  /// Creates a page.
  const ChatMessagePage(this.messages, this.conversation, {this.nextBefore});

  /// The messages, oldest first.
  final List<StoredChatMessage> messages;

  /// The conversation (null if it does not exist yet).
  final ChatConversationState? conversation;

  /// Pass as `beforeSeq` for older messages; null when there are none.
  final int? nextBefore;
}

/// One page of conversations, newest first.
class ChatConversationPage {
  /// Creates a page.
  const ChatConversationPage(this.conversations, {this.nextCursor});

  /// The conversations, newest first.
  final List<ChatConversationState> conversations;

  /// Opaque cursor for the next page; null when this is the last.
  final String? nextCursor;
}

/// Chat messages in Firestore.
class FirestoreChatStore {
  /// Sends every request through the given client. Tests pass their own
  /// [clock].
  FirestoreChatStore(this._rest, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The store the backend uses (see [FirestoreRest.fromEnvironment]).
  factory FirestoreChatStore.fromEnvironment({http.Client? client}) =>
      FirestoreChatStore(FirestoreRest.fromEnvironment(client: client));

  final FirestoreRest _rest;
  final DateTime Function() _clock;

  /// Sends a message, or returns the earlier one if this clientMessageId
  /// was already sent with the same content. Throws [ChatDisabled] or
  /// [ChatDuplicateConflict]; Firestore errors pass through (a
  /// [FirestoreUnavailable] commit may have been applied: retry with the
  /// same clientMessageId).
  Future<ChatSendResult> send(ChatSendCommand command) =>
      _rest.runTransaction((transaction) async {
        final cid = command.conversationId;
        final docs = await transaction.batchGet([
          chatConfigPath,
          _conversationPath(cid),
          _messagePath(cid, command.messageId),
        ]);
        final plan = planChatSend(
          config: docs[chatConfigPath],
          conversation: docs[_conversationPath(cid)],
          existing: docs[_messagePath(cid, command.messageId)],
          command: command,
          now: _clock(),
        );
        switch (plan) {
          case ChatSendRefused(:final error):
            throw error;
          case ChatSendReplay(:final message):
            return ChatSendResult(message, created: false);
          case ChatSendWrite(:final writes, :final message):
            await transaction.commit(writes);
            return ChatSendResult(message, created: true);
        }
      });

  /// Marks the reader's messages read up to [ChatReadCommand.upToMessageId]
  /// (never backwards). Throws [ChatDisabled] or [ChatNotFound].
  Future<ChatMarkReadResult> markRead(ChatReadCommand command) =>
      _rest.runTransaction((transaction) async {
        final cid = command.conversationId;
        final paths = (
          conversation: _conversationPath(cid),
          upTo: _messagePath(cid, command.upToMessageId),
          outbox: _readOutboxPath(cid, command.readerRole),
        );
        final docs = await transaction.batchGet([
          chatConfigPath,
          paths.conversation,
          paths.upTo,
          paths.outbox,
        ]);
        final plan = planChatMarkRead(
          config: docs[chatConfigPath],
          conversation: docs[paths.conversation],
          upTo: docs[paths.upTo],
          readOutbox: docs[paths.outbox],
          command: command,
          now: _clock(),
        );
        switch (plan) {
          case ChatReadRefused(:final error):
            throw error;
          case ChatReadUnchanged(:final unread):
            return ChatMarkReadResult(markedRead: 0, unread: unread);
          case ChatReadWrite(:final writes, :final markedRead, :final unread):
            await transaction.commit(writes);
            return ChatMarkReadResult(markedRead: markedRead, unread: unread);
        }
      });

  /// The conversation between the two users, or null.
  Future<ChatConversationState?> conversation(
    int studentUserId,
    int tutorUserId,
  ) async {
    final doc = await _rest.get(
      _conversationPath(chatConversationId(studentUserId, tutorUserId)),
    );
    return doc == null ? null : ChatConversationState.fromDocument(doc);
  }

  /// Whether the two users have exchanged messages: what
  /// `ChatPermissions.link().hasMessages` must use once Firestore is the
  /// store (the MySQL audit table lags behind).
  Future<bool> hasConversation(int studentUserId, int tutorUserId) async =>
      ((await conversation(studentUserId, tutorUserId))?.lastSeq ?? 0) > 0;

  /// The newest [limit] messages before [beforeSeq] (or the newest
  /// overall), oldest first, with the conversation for read state.
  Future<ChatMessagePage> messages(
    int studentUserId,
    int tutorUserId, {
    int? beforeSeq,
    int limit = chatMessagePageSize,
  }) async {
    if (limit < 1 || limit > chatMessagePageSize) {
      throw ArgumentError.value(limit, 'limit');
    }
    if (beforeSeq != null && beforeSeq < 1) {
      throw ArgumentError.value(beforeSeq, 'beforeSeq');
    }
    final cid = chatConversationId(studentUserId, tutorUserId);
    final state = await conversation(studentUserId, tutorUserId);
    if (state == null) return const ChatMessagePage([], null);
    final docs = await _rest.runQuery({
      'from': [
        {'collectionId': 'messages'},
      ],
      if (beforeSeq != null)
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'seq'},
            'op': 'LESS_THAN',
            'value': encodeFirestoreValue(beforeSeq),
          },
        },
      'orderBy': [
        {
          'field': {'fieldPath': 'seq'},
          'direction': 'DESCENDING',
        },
      ],
      'limit': limit,
    }, parent: _conversationPath(cid));
    final newestFirst = [
      for (final doc in docs) StoredChatMessage.fromDocument(doc),
    ];
    if (newestFirst.any((m) => m.conversationId != cid)) {
      throw ChatDataException('Messages outside conversation $cid.');
    }
    final oldest = newestFirst.isEmpty ? null : newestFirst.last.seq;
    return ChatMessagePage(
      newestFirst.reversed.toList(),
      state,
      nextBefore: newestFirst.length == limit && oldest! > 1 ? oldest : null,
    );
  }

  /// [userId]'s conversations as [role], newest first, one page at a time.
  /// Throws an [ArgumentError] for a cursor this store did not make.
  Future<ChatConversationPage> conversations(
    int userId,
    ChatRole role, {
    String? cursor,
    int limit = chatConversationPageSize,
  }) async {
    if (userId <= 0) throw ArgumentError.value(userId, 'userId');
    if (limit < 1 || limit > chatConversationPageSize) {
      throw ArgumentError.value(limit, 'limit');
    }
    final after = cursor == null ? null : _decodeCursor(cursor);
    final idField = '${role.value}UserId';
    final docs = await _rest.runQuery({
      'from': [
        {'collectionId': 'conversations'},
      ],
      'where': {
        'fieldFilter': {
          'field': {'fieldPath': idField},
          'op': 'EQUAL',
          'value': encodeFirestoreValue(userId),
        },
      },
      'orderBy': [
        {
          'field': {'fieldPath': 'lastSentAt'},
          'direction': 'DESCENDING',
        },
        {
          'field': {'fieldPath': '__name__'},
          'direction': 'DESCENDING',
        },
      ],
      if (after != null)
        'startAt': {
          'values': [
            encodeFirestoreValue(after.lastSentAt),
            {
              'referenceValue': _rest.documentName(
                _conversationPath(after.conversationId),
              ),
            },
          ],
          'before': false,
        },
      'limit': limit,
    });
    final states = [
      for (final doc in docs) ChatConversationState.fromDocument(doc),
    ];
    final mine = role == ChatRole.student
        ? states.every((s) => s.studentUserId == userId)
        : states.every((s) => s.tutorUserId == userId);
    if (!mine) throw const ChatDataException('Query returned other chats.');
    final last = states.isEmpty ? null : states.last;
    return ChatConversationPage(
      states,
      nextCursor: states.length == limit && last != null
          ? _encodeCursor(last.lastSentAt, last.conversationId)
          : null,
    );
  }

  /// Unread messages across [userId]'s conversations as [role] (at most
  /// [chatUnreadPageLimit] pages are added up).
  Future<int> unreadTotal(int userId, ChatRole role) async {
    var total = 0;
    String? cursor;
    for (var page = 0; page < chatUnreadPageLimit; page++) {
      final result = await conversations(userId, role, cursor: cursor);
      for (final c in result.conversations) {
        total += _of(c.unread, role);
      }
      cursor = result.nextCursor;
      if (cursor == null) break;
    }
    return total;
  }

  static String _encodeCursor(DateTime lastSentAt, String cid) =>
      base64Url.encode(
        utf8.encode(
          jsonEncode({'t': lastSentAt.toUtc().toIso8601String(), 'c': cid}),
        ),
      );

  static ({DateTime lastSentAt, String conversationId}) _decodeCursor(
    String cursor,
  ) {
    try {
      final json =
          jsonDecode(utf8.decode(base64Url.decode(cursor)))
              as Map<String, dynamic>;
      final time = DateTime.parse(json['t'] as String);
      final cid = json['c'] as String;
      if (!time.isUtc ||
          !RegExp(r'^s[0-9]{1,10}_t[0-9]{1,10}$').hasMatch(cid)) {
        throw const FormatException();
      }
      return (lastSentAt: time, conversationId: cid);
    } on Object {
      throw ArgumentError.value(cursor, 'cursor', 'Not a conversation cursor');
    }
  }
}

// ─── Field readers ──────────────────────────────────────────────────────────

int _int(Map<String, Object?> f, String key, {int min = 0}) {
  final value = f[key];
  if (value is! int || value < min) {
    throw ChatDataException('Field $key is malformed.');
  }
  return value;
}

String _string(Map<String, Object?> f, String key, {bool allowEmpty = false}) {
  final value = f[key];
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw ChatDataException('Field $key is malformed.');
  }
  return value;
}

DateTime _time(Map<String, Object?> f, String key) {
  final value = f[key];
  if (value is! DateTime) throw ChatDataException('Field $key is malformed.');
  return value;
}

ChatCounts _counts(Map<String, Object?> f, String key) {
  final value = f[key];
  if (value is! Map<String, Object?>) {
    throw ChatDataException('Field $key is malformed.');
  }
  return (
    student: _int(value, 'student'),
    tutor: _int(value, 'tutor'),
  );
}
