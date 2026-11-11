import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_audit.dart';
import 'package:theo_tutoring_backend/chat_outbox.dart';
import 'package:theo_tutoring_backend/chat_store.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Request handling shared by the tutor (/tutor/...) and student
// (/student/...) chat routes. Each route passes the caller's ChatRole; the
// path id is always the other user's `User`.UserId.
//
// Messages live in Firestore (FirestoreChatStore); accounts, roles and
// bookings are checked in MySQL (ChatPermissions). Handlers never write the
// MySQL Messaging table: audit rows come from the chat outbox.
//
// Who may chat:
//  - the caller must be signed in as an Active user with that role;
//  - a student may open a chat with any tutor shown in tutor search
//    (Active and Approved), so they can ask before booking;
//  - a tutor may only chat with a student who has a booking with them, or
//    who already has a conversation with them (in Firestore);
//  - either side may always read a conversation they already have.
// Every read is limited to the caller's own conversation.

/// Verifies the "Authorization: Bearer <Firebase ID token>" header.
typedef ChatTokenVerifier =
    Future<FirebaseUser> Function(String? authorization);

/// Opens the permission checks for one request.
typedef ChatPermissionsFactory = Future<ChatPermissions> Function();

/// Opens the Firestore message store for one request.
typedef ChatStoreFactory = Future<FirestoreChatStore> Function();

/// Opens the Messaging audit table for one request.
typedef ChatAuditFactory = Future<ChatAuditSink> Function();

/// Opens the chat outbox worker for one request.
typedef ChatOutboxFactory = Future<ChatOutboxWorker> Function();

/// Chat cannot be served because the server is set up wrongly (for
/// example, the default MySQL connection in Firestore emulator mode).
class ChatSetupException implements Exception {
  /// Creates the exception.
  const ChatSetupException(this.message);

  /// What is wrong (for the server log).
  final String message;

  @override
  String toString() => 'ChatSetupException: $message';
}

/// What the chat handlers need.
///
/// Every part must be given: tests pass fakes for all of them, so nothing
/// can silently fall back to MySQL or production Firestore. Only the route
/// files use [ChatDependencies.production].
class ChatDependencies {
  /// Explicit dependencies (tests).
  ChatDependencies({
    required this.verifyToken,
    required this.permissions,
    required this.store,
    required this.audit,
    this.outbox,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// What the routes use: the Firebase token check, the shared MySQL
  /// connection (refused before connecting in Firestore emulator mode or
  /// with invalid settings) and the store chosen by [FirestoreEndpoint]
  /// (only the emulator in emulator mode).
  factory ChatDependencies.production() => ChatDependencies(
    verifyToken: verifyFirebaseToken,
    permissions: () async => MySqlChatPermissions(await _defaultConnection()),
    store: () async => FirestoreChatStore.fromEnvironment(),
    audit: () async => MySqlChatAudit(await _defaultConnection()),
    outbox: () async => ChatOutboxWorker(
      rest: FirestoreRest.fromEnvironment(),
      audit: MySqlChatAudit(await _defaultConnection()),
      notifications: NotificationStore.fromFirebaseAdmin(),
    ),
  );

  /// Checks the sign-in token.
  final ChatTokenVerifier verifyToken;

  /// Opens the permission checks.
  final ChatPermissionsFactory permissions;

  /// Opens the message store.
  final ChatStoreFactory store;

  /// Opens the audit table (used by the outbox worker, never by handlers).
  final ChatAuditFactory audit;

  /// Processes the outbox entries a request wrote, best effort; none
  /// (nothing processed) when absent.
  final ChatOutboxFactory? outbox;

  /// Current time, for the "2h ago" labels.
  final DateTime Function() clock;

  /// The shared MySQL connection, refused (before connecting) in Firestore
  /// emulator mode or when the Firestore settings are invalid.
  static Future<MySQLConnection> _defaultConnection() {
    final FirestoreEndpoint endpoint;
    try {
      endpoint = FirestoreEndpoint.resolve();
    } on FirestoreEndpointException {
      throw const ChatSetupException(
        'Invalid Firestore settings, so the default chat database is '
        'disabled.',
      );
    }
    if (endpoint.isEmulator) {
      throw const ChatSetupException(
        'Firestore emulator mode is on, so the default chat database is '
        'disabled; pass test dependencies instead.',
      );
    }
    return getConnection();
  }
}

/// GET /{role}/me: the caller's `User`.UserId, used by the app to tell its
/// own messages from the other user's.
Future<Response> handleChatMe(
  RequestContext context,
  ChatRole role,
  ChatDependencies deps,
) => _run(context, role, deps, {HttpMethod.get}, (session) async {
  return Response.json(
    body: {'userId': session.me.userId, 'name': session.me.name},
  );
});

/// GET /{role}/conversations[?cursor=]: up to [chatConversationPageSize]
/// conversations, newest first. When there are more, the X-Next-Cursor
/// header holds the cursor for the next page.
Future<Response> handleChatConversations(
  RequestContext context,
  ChatRole role,
  ChatDependencies deps,
) => _run(context, role, deps, {HttpMethod.get}, (session) async {
  final cursor = context.request.uri.queryParameters['cursor'];
  final ChatConversationPage page;
  try {
    page = await (await session.store).conversations(
      session.me.userId,
      role,
      cursor: cursor,
    );
  } on ArgumentError {
    // The cursor format is private to the store, so its ArgumentError is
    // the only sign of a bad cursor.
    return _error(HttpStatus.badRequest, 'cursor is not valid.');
  }
  int otherIn(ChatConversationState c) =>
      role == ChatRole.student ? c.tutorUserId : c.studentUserId;
  final otherIds = [for (final c in page.conversations) otherIn(c)];
  final profiles = await session.permissions.profiles(otherIds, role.other);
  final now = session.deps.clock().toUtc();
  return Response.json(
    headers: {'X-Next-Cursor': ?page.nextCursor},
    body: [
      for (final c in page.conversations)
        if (profiles[otherIn(c)] case final other?)
          ChatConversation(
            conversationId: c.conversationId,
            userId: other.userId,
            name: other.name,
            profilePhoto: other.profilePhoto,
            lastMessage: c.lastMessage,
            lastMessageAt: c.lastSentAt,
            unreadCount: role == ChatRole.student
                ? c.unread.student
                : c.unread.tutor,
          ).toJson(now),
    ],
  );
});

/// GET /{role}/conversations/unread-count: unread messages across the
/// caller's conversations.
Future<Response> handleChatUnreadCount(
  RequestContext context,
  ChatRole role,
  ChatDependencies deps,
) => _run(context, role, deps, {HttpMethod.get}, (session) async {
  final total = await (await session.store).unreadTotal(
    session.me.userId,
    role,
  );
  return Response.json(body: {'unreadCount': total});
});

/// GET  /{role}/conversations/{otherUserId}/messages[?beforeSeq=]: up to
/// [chatMessagePageSize] messages, oldest first. When there are older ones,
/// the X-Next-Before-Seq header holds the next `beforeSeq`.
/// POST /{role}/conversations/{otherUserId}/messages: sends
/// {clientMessageId, messageText, receiverId?, bookingId?}. 201 for a new
/// message, 200 when the same clientMessageId and content was already sent,
/// 409 when the clientMessageId was used for different content, 503 while
/// chat is switched off.
Future<Response> handleChatMessages(
  RequestContext context,
  ChatRole role,
  String otherUserId,
  ChatDependencies deps,
) => _run(context, role, deps, {HttpMethod.get, HttpMethod.post}, (
  session,
) async {
  final isSend = context.request.method == HttpMethod.post;

  // Validate the request before touching the conversation.
  _SendRequest? send;
  int? beforeSeq;
  try {
    if (isSend) {
      send = _SendRequest.parse(await _readBody(context));
    } else {
      beforeSeq = _optionalQueryId(context, 'beforeSeq');
    }
  } on FormatException catch (e) {
    return _error(HttpStatus.badRequest, e.message);
  }

  final other = await session.open(otherUserId, sending: isSend);
  if (other.error != null) return other.error!;
  final otherUser = other.participant!;
  final studentId = session.studentIdWith(otherUser.userId);
  final tutorId = session.tutorIdWith(otherUser.userId);

  if (send == null) {
    final page = await (await session.store).messages(
      studentId,
      tutorId,
      beforeSeq: beforeSeq,
    );
    return Response.json(
      headers: {'X-Next-Before-Seq': ?page.nextBefore?.toString()},
      body: [
        for (final m in page.messages)
          _messageJson(m, page.conversation!, session.me.userId),
      ],
    );
  }

  if (send.receiverId != null && send.receiverId != otherUser.userId) {
    return _error(
      HttpStatus.badRequest,
      'receiverId does not match this conversation.',
    );
  }
  if (send.bookingId != null &&
      !await session.permissions.bookingBelongsTo(
        send.bookingId!,
        studentUserId: studentId,
        tutorUserId: tutorId,
      )) {
    return _error(
      HttpStatus.badRequest,
      'bookingId is not a booking in this conversation.',
    );
  }

  final me = session.party(session.me);
  final them = session.party(otherUser);
  final result = await (await session.store).send(
    ChatSendCommand(
      student: role == ChatRole.student ? me : them,
      tutor: role == ChatRole.tutor ? me : them,
      senderRole: role,
      clientMessageId: send.clientMessageId,
      text: send.messageText,
      senderName: session.me.name,
      bookingId: send.bookingId,
    ),
  );
  // Read state comes from the conversation; a new message is unread.
  final message = result.message;
  if (result.created) {
    await session.afterWrite((worker) => worker.afterSend(message));
  }
  return Response.json(
    statusCode: result.created ? HttpStatus.created : HttpStatus.ok,
    body: {
      ..._messageFields(message, session.me.userId),
      'isRead': false,
    },
  );
});

/// PUT /{role}/conversations/{otherUserId}/read: marks the other user's
/// messages read up to and including `upToMessageId` (never backwards).
/// The body may repeat the other user's id ({"studentId": n} from the tutor
/// app, {"tutorId": n} from the student app); it must match the path.
Future<Response> handleChatRead(
  RequestContext context,
  ChatRole role,
  String otherUserId,
  ChatDependencies deps,
) => _run(context, role, deps, {HttpMethod.put}, (session) async {
  final int? bodyId;
  final String upToMessageId;
  try {
    final body = await _readBody(context);
    bodyId = _optionalId(body, '${role.other.value}Id');
    final upTo = body['upToMessageId'];
    if (upTo is! String || upTo.isEmpty) {
      throw const FormatException('upToMessageId is required.');
    }
    if (!_messageId.hasMatch(upTo)) {
      throw const FormatException('upToMessageId is not valid.');
    }
    upToMessageId = upTo;
  } on FormatException catch (e) {
    return _error(HttpStatus.badRequest, e.message);
  }

  final other = await session.open(otherUserId, sending: false);
  if (other.error != null) return other.error!;
  final otherId = other.participant!.userId;
  if (bodyId != null && bodyId != otherId) {
    return _error(
      HttpStatus.badRequest,
      '${role.other.value}Id does not match this conversation.',
    );
  }

  final command = ChatReadCommand(
    studentUserId: session.studentIdWith(otherId),
    tutorUserId: session.tutorIdWith(otherId),
    readerRole: role,
    upToMessageId: upToMessageId,
  );
  final result = await (await session.store).markRead(command);
  if (result.markedRead > 0) {
    await session.afterWrite(
      (worker) => worker.afterRead(command.conversationId, role),
    );
  }
  return Response.json(
    body: {'markedRead': result.markedRead, 'unreadCount': result.unread},
  );
});

// ─── JSON ───────────────────────────────────────────────────────────────────

Map<String, Object?> _messageFields(StoredChatMessage m, int viewerId) => {
  'messageId': m.messageId,
  'seq': m.seq,
  'senderId': m.senderId,
  'receiverId': m.receiverId,
  'messageText': m.text,
  'sentAt': m.sentAt.toUtc().toIso8601String(),
  'isOutgoing': m.senderId == viewerId,
  'bookingId': m.bookingId,
};

Map<String, Object?> _messageJson(
  StoredChatMessage m,
  ChatConversationState conversation,
  int viewerId,
) => {..._messageFields(m, viewerId), 'isRead': conversation.isRead(m)};

// ─── Shared plumbing ────────────────────────────────────────────────────────

class _Session {
  _Session(this.role, this.me, this.permissions, this.deps);

  final ChatRole role;
  final ChatParticipant me;
  final ChatPermissions permissions;
  final ChatDependencies deps;

  /// The message store, opened only by handlers that need it.
  late final Future<FirestoreChatStore> store = deps.store();

  int studentIdWith(int otherId) =>
      role == ChatRole.student ? me.userId : otherId;

  int tutorIdWith(int otherId) => role == ChatRole.tutor ? me.userId : otherId;

  /// Runs [work] on the outbox worker, if there is one. Best effort: the
  /// change is already saved, so a failure is only logged (the entries
  /// stay for ChatOutboxWorker.runOnce).
  Future<void> afterWrite(
    Future<void> Function(ChatOutboxWorker worker) work,
  ) async {
    final open = deps.outbox;
    if (open == null) return;
    try {
      await work(await open());
    } on Object catch (e) {
      stderr.writeln('Chat outbox processing deferred: ${e.runtimeType}');
    }
  }

  /// [user] as a conversation party; every chat user has a Firebase UID.
  ChatParty party(ChatParticipant user) {
    final uid = user.firebaseUid;
    if (uid == null || uid.trim().isEmpty) {
      throw ChatSetupException('User ${user.userId} has no Firebase UID.');
    }
    return ChatParty(userId: user.userId, firebaseUid: uid);
  }

  /// Finds the other user from the path and checks the caller may read
  /// (or, when [sending], write to) this conversation. "Already has a
  /// conversation" is asked of Firestore, and only when a booking or
  /// tutor search does not already allow it.
  Future<({ChatParticipant? participant, Response? error})> open(
    String rawId, {
    required bool sending,
  }) async {
    final id = int.tryParse(rawId);
    if (id == null || id <= 0) {
      return (
        participant: null,
        error: _error(
          HttpStatus.badRequest,
          '${role.other.value}Id must be a positive whole number.',
        ),
      );
    }
    final other = await permissions.participant(id, role.other);
    if (other == null) {
      return (
        participant: null,
        error: _error(
          HttpStatus.notFound,
          role.other == ChatRole.tutor
              ? 'Tutor not found.'
              : 'Student not found.',
        ),
      );
    }

    final studentId = studentIdWith(id);
    final tutorId = tutorIdWith(id);
    final studentMayStart = role == ChatRole.student && other.isPublicTutor;
    final linked =
        studentMayStart ||
        await permissions.hasBooking(
          studentUserId: studentId,
          tutorUserId: tutorId,
        ) ||
        await (await store).hasConversation(studentId, tutorId);
    final allowed = linked && (!sending || other.isActive);
    if (!allowed) {
      return (
        participant: null,
        error: _error(
          HttpStatus.forbidden,
          sending
              ? 'You cannot send messages to this user.'
              : 'You are not part of this conversation.',
        ),
      );
    }
    return (participant: other, error: null);
  }
}

/// Checks the method, verifies the token, loads the caller, then runs
/// [body]. Token, account, chat-store and database failures become JSON
/// errors that never echo internal details.
Future<Response> _run(
  RequestContext context,
  ChatRole role,
  ChatDependencies deps,
  Set<HttpMethod> methods,
  Future<Response> Function(_Session session) body,
) async {
  if (!methods.contains(context.request.method)) {
    return _error(HttpStatus.methodNotAllowed, 'Method not allowed.');
  }
  final d = deps;

  final FirebaseUser user;
  try {
    user = await d.verifyToken(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
  } on AuthTokenException catch (e) {
    return _error(HttpStatus.unauthorized, e.message);
  } on StateError {
    return _error(
      HttpStatus.internalServerError,
      'Authentication service is not configured correctly.',
    );
  } catch (_) {
    stderr.writeln('Firebase authentication failed unexpectedly.');
    return _error(
      HttpStatus.serviceUnavailable,
      'Authentication service is temporarily unavailable.',
    );
  }

  try {
    final permissions = await d.permissions();
    final me = await permissions.signedIn(user.uid, role);
    if (me == null) {
      return _error(
        HttpStatus.forbidden,
        'An active ${role.value} account is required.',
      );
    }
    return await body(_Session(role, me, permissions, d));
  } on ChatDisabled catch (e) {
    return _error(HttpStatus.serviceUnavailable, e.message);
  } on ChatDuplicateConflict catch (e) {
    return _error(HttpStatus.conflict, e.message);
  } on ChatNotFound catch (e) {
    return _error(HttpStatus.notFound, e.message);
  } on ChatDataException catch (e) {
    stderr.writeln('Chat data is inconsistent: ${e.message}');
    return _error(
      HttpStatus.internalServerError,
      'Chat data is inconsistent. Please contact support.',
    );
  } on ChatSetupException catch (e) {
    stderr.writeln('Chat is not set up correctly: ${e.message}');
    return _error(
      HttpStatus.internalServerError,
      'Chat is not configured correctly.',
    );
  } on FirebaseAdminException catch (e) {
    stderr.writeln('Chat is not set up correctly: ${e.message}');
    return _error(
      HttpStatus.internalServerError,
      'Chat is not configured correctly.',
    );
  } on FirestoreException catch (e) {
    stderr.writeln('Chat store request failed: ${e.message}');
    return _error(
      HttpStatus.serviceUnavailable,
      'Chat is temporarily unavailable. Please try again.',
    );
  } catch (e) {
    // Never echo database errors (they can contain SQL or credentials).
    stderr.writeln('Chat database operation failed: ${e.runtimeType}');
    return _error(
      HttpStatus.serviceUnavailable,
      'Chat is temporarily unavailable. Please try again.',
    );
  }
}

final _clientMessageId = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

// Same shape as the store's message ids: "{senderUserId}-{clientMessageId}".
final _messageId = RegExp(r'^[0-9]{1,10}-[A-Za-z0-9_-]{16,64}$');

class _SendRequest {
  const _SendRequest(
    this.clientMessageId,
    this.messageText,
    this.receiverId,
    this.bookingId,
  );

  factory _SendRequest.parse(Map<String, dynamic> body) {
    final clientMessageId = body['clientMessageId'];
    if (clientMessageId is! String ||
        !_clientMessageId.hasMatch(clientMessageId)) {
      throw const FormatException(
        'clientMessageId must be 16-64 letters, digits, "_" or "-".',
      );
    }
    final text = body['messageText'];
    if (text is! String) {
      throw const FormatException('messageText is required.');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('messageText cannot be empty.');
    }
    if (trimmed.length > maxChatMessageLength) {
      throw const FormatException(
        'messageText must be $maxChatMessageLength characters or fewer.',
      );
    }
    return _SendRequest(
      clientMessageId,
      trimmed,
      _optionalId(body, 'receiverId'),
      _optionalId(body, 'bookingId'),
    );
  }

  final String clientMessageId;
  final String messageText;
  final int? receiverId;
  final int? bookingId;
}

/// A positive integer field, or null when it is missing or null.
int? _optionalId(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value == null) return null;
  if (value is! int || value <= 0) {
    throw FormatException('$key must be a positive whole number.');
  }
  return value;
}

/// A positive integer query parameter, or null when it is missing.
int? _optionalQueryId(RequestContext context, String key) {
  final raw = context.request.uri.queryParameters[key];
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw FormatException('$key must be a positive whole number.');
  }
  return value;
}

/// The JSON object body.
Future<Map<String, dynamic>> _readBody(RequestContext context) async {
  final text = await context.request.body();
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('Request body must be valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Request body must be a JSON object.');
  }
  return decoded;
}

Response _error(int status, String message) =>
    Response.json(statusCode: status, body: {'error': message});
