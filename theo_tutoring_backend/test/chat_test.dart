import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_audit.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';
import 'package:theo_tutoring_backend/chat_moderation.dart';
import 'package:theo_tutoring_backend/chat_store.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';

import 'support/fake_firestore.dart';

// Handler tests. Permissions come from an in-memory MySQL stand-in; messages
// go through the real FirestoreChatStore against the shared fake Firestore
// (no network). The audit factory throws in every test, so no handler path
// can write the MySQL Messaging table.

class _MockContext extends Mock implements RequestContext {}

// ─── In-memory stand-in for the User/Booking tables ─────────────────────────

class _User {
  const _User(
    this.id,
    this.uid,
    this.role,
    this.name, {
    this.status = 'Active',
    this.approved = true,
  });

  final int id;
  final String uid;
  final ChatRole role;
  final String name;
  final String status;
  final bool approved;
}

class _Booking {
  const _Booking(this.id, this.studentUserId, this.tutorUserId);
  final int id;
  final int studentUserId;
  final int tutorUserId;
}

class _FakePermissions implements ChatPermissions {
  _FakePermissions({required this.users, required this.bookings});

  final List<_User> users;
  final List<_Booking> bookings;

  _User? _user(int id) => users.where((u) => u.id == id).firstOrNull;

  ChatParticipant _participant(_User u) => ChatParticipant(
    userId: u.id,
    name: u.name,
    role: u.role,
    firebaseUid: u.uid,
    isActive: u.status == 'Active',
    isPublicTutor:
        u.role == ChatRole.tutor && u.status == 'Active' && u.approved,
  );

  @override
  Future<ChatParticipant?> signedIn(String firebaseUid, ChatRole role) async {
    final u = users
        .where(
          (u) => u.uid == firebaseUid && u.role == role && u.status == 'Active',
        )
        .firstOrNull;
    return u == null ? null : _participant(u);
  }

  @override
  Future<ChatParticipant?> participant(int userId, ChatRole role) async {
    final u = _user(userId);
    return u == null || u.role != role ? null : _participant(u);
  }

  @override
  Future<bool> hasBooking({
    required int studentUserId,
    required int tutorUserId,
  }) async => bookings.any(
    (b) => b.studentUserId == studentUserId && b.tutorUserId == tutorUserId,
  );

  @override
  Future<bool> bookingBelongsTo(
    int bookingId, {
    required int studentUserId,
    required int tutorUserId,
  }) async => bookings.any(
    (b) =>
        b.id == bookingId &&
        b.studentUserId == studentUserId &&
        b.tutorUserId == tutorUserId,
  );

  @override
  Future<Map<int, ChatParticipant>> profiles(
    List<int> userIds,
    ChatRole role,
  ) async => {
    for (final id in userIds)
      if (_user(id) case final u? when u.role == role) id: _participant(u),
  };
}

// ─── Test data ──────────────────────────────────────────────────────────────

const _tutor = 1; // Theo, Active + Approved, booked by Lerato
const _otherTutor = 2; // Active + Approved, booked by Sipho
const _pendingTutor = 3; // AccountStatus Pending
const _unapprovedTutor = 4; // Active but not Approved
const _lerato = 10; // student with a booking and messages with Theo
const _sipho = 11; // student with no link to Theo
const _suspended = 12; // suspended student who booked Theo

final _now = DateTime.utc(2026, 10, 24, 12);

// The '-' ends the name, so 'm1' and 'm10' can never pad to the same id.
String _client(String name) => 'client-$name-'.padRight(20, 'x');

String _id(int sender, String name) => chatMessageId(sender, _client(name));

const _users = [
  _User(_tutor, 'uid-theo', ChatRole.tutor, 'Theo Tutor'),
  _User(_otherTutor, 'uid-other-tutor', ChatRole.tutor, 'Other Tutor'),
  _User(
    _pendingTutor,
    'uid-pending',
    ChatRole.tutor,
    'Pending Tutor',
    status: 'Pending',
  ),
  _User(
    _unapprovedTutor,
    'uid-unapproved',
    ChatRole.tutor,
    'Unapproved Tutor',
    approved: false,
  ),
  _User(_lerato, 'uid-lerato', ChatRole.student, 'Lerato Phiri'),
  _User(_sipho, 'uid-sipho', ChatRole.student, 'Sipho Khumalo'),
  _User(
    _suspended,
    'uid-suspended',
    ChatRole.student,
    'Suspended Student',
    status: 'Suspended',
  ),
];

const _bookings = [
  _Booking(100, _lerato, _tutor),
  _Booking(200, _sipho, _otherTutor),
  _Booking(300, _suspended, _tutor),
];

/// The fake Firestore, the store on it, the permissions and the clock.
class _World {
  _World() : firestore = FakeFirestore()..enableChat();

  final FakeFirestore firestore;
  final permissions = _FakePermissions(users: _users, bookings: _bookings);
  DateTime now = _now;
  late final store = FirestoreChatStore(
    firestore.rest(),
    clock: () => now,
  );

  ChatParty party(int userId) => ChatParty(
    userId: userId,
    firebaseUid: _users.firstWhere((u) => u.id == userId).uid,
  );

  /// Stores a message directly (as the app would through the API).
  Future<void> seed(
    int student,
    int tutor,
    ChatRole from,
    String name,
    String text, {
    Duration ago = Duration.zero,
  }) async {
    final previous = now;
    now = _now.subtract(ago);
    await store.send(
      ChatSendCommand(
        student: party(student),
        tutor: party(tutor),
        senderRole: from,
        clientMessageId: _client(name),
        text: text,
        senderName: 'seed',
      ),
    );
    now = previous;
  }

  int get messageCount =>
      firestore.docs.keys.where((p) => p.contains('/messages/')).length;

  Map<String, Object?> conversation(int student, int tutor) =>
      firestore.fields('conversations/${chatConversationId(student, tutor)}')!;
}

/// Lerato and Theo: L1 (read by Theo), T1, L2 (unread). Sipho and the
/// other tutor: one message.
Future<_World> _seeded() async {
  final w = _World();
  await w.seed(
    _lerato,
    _tutor,
    ChatRole.student,
    'l1',
    'Are you free on Thursday?',
    ago: const Duration(hours: 3),
  );
  await w.seed(
    _lerato,
    _tutor,
    ChatRole.tutor,
    't1',
    'Yes, 3pm works.',
    ago: const Duration(hours: 2),
  );
  await w.seed(
    _lerato,
    _tutor,
    ChatRole.student,
    'l2',
    'Great, see you then!',
    ago: const Duration(hours: 2),
  );
  await w.store.markRead(
    ChatReadCommand(
      studentUserId: _lerato,
      tutorUserId: _tutor,
      readerRole: ChatRole.tutor,
      upToMessageId: _id(_lerato, 'l1'),
    ),
  );
  await w.seed(
    _sipho,
    _otherTutor,
    ChatRole.student,
    's1',
    'Private to the other tutor',
  );
  return w;
}

// Tokens are "token-<firebase uid>"; anything else is rejected.
Future<FirebaseUser> _verify(String? header) async {
  if (header == null || !header.startsWith('Bearer token-')) {
    throw const AuthTokenException('You must be signed in.');
  }
  return FirebaseUser(
    uid: header.substring('Bearer token-'.length),
    email: null,
    emailVerified: true,
  );
}

/// Every factory is a fake, and the audit table may never be opened: no
/// test can reach MySQL, production Firestore or the Messaging table.
ChatDependencies _deps(
  _World world, {
  ChatTokenVerifier verify = _verify,
  ChatStoreFactory? store,
  ChatModerationStore? moderation,
  List<ChatModerationRecord>? flagged,
}) => ChatDependencies(
  verifyToken: verify,
  permissions: () async => world.permissions,
  store: store ?? () async => world.store,
  audit: () async => throw StateError('handlers must not open the audit'),
  moderation: moderation == null ? null : () async => moderation,
  onFlagged: flagged?.add,
  clock: () => _now,
);

/// Chat moderation records in memory.
class _ModerationMemory implements ChatModerationStore {
  final records = <int, ChatModerationRecord>{};

  @override
  Future<ChatModerationRecord?> get(int userId) async => records[userId];

  @override
  Future<Map<int, ChatModerationRecord>> getMany(Iterable<int> ids) async => {
    for (final id in ids)
      if (records[id] case final r?) id: r,
  };

  @override
  Future<void> save(ChatModerationRecord record) async =>
      records[record.userId] = record;

  @override
  Future<List<ChatModerationRecord>> all() async => records.values.toList();
}

RequestContext _context(
  String method,
  String path, {
  String? uid,
  Object? body,
}) {
  final context = _MockContext();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {if (uid != null) 'Authorization': 'Bearer token-$uid'},
      body: body == null ? null : (body is String ? body : jsonEncode(body)),
    ),
  );
  return context;
}

Future<(int, dynamic, Map<String, String>)> _call(
  Future<Response> response,
) async {
  final r = await response;
  final text = await r.body();
  return (r.statusCode, text.isEmpty ? null : jsonDecode(text), r.headers);
}

Future<(int, dynamic)> _send(Future<Response> response) async {
  final (status, body, _) = await _call(response);
  return (status, body);
}

Future<(int, dynamic)> _messages(
  _World w,
  ChatRole role,
  String uid,
  int otherId, {
  String query = '',
}) => _send(
  handleChatMessages(
    _context('GET', '/x/$otherId/messages$query', uid: uid),
    role,
    '$otherId',
    _deps(w),
  ),
);

Future<(int, dynamic)> _post(
  _World w,
  ChatRole role,
  String uid,
  int otherId,
  Object? body,
) => _send(
  handleChatMessages(
    _context('POST', '/x/$otherId/messages', uid: uid, body: body),
    role,
    '$otherId',
    _deps(w),
  ),
);

Map<String, Object?> _sendBody(
  String name,
  String text, {
  int? receiverId,
  int? bookingId,
}) => {
  'clientMessageId': _client(name),
  'messageText': text,
  'receiverId': ?receiverId,
  'bookingId': ?bookingId,
};

Future<(int, dynamic)> _read(
  _World w,
  ChatRole role,
  String uid,
  int otherId, {
  Object? body,
}) => _send(
  handleChatRead(
    _context('PUT', '/x/$otherId/read', uid: uid, body: body),
    role,
    '$otherId',
    _deps(w),
  ),
);

final Object _productionSkip = () {
  try {
    return FirestoreEndpoint.resolve().isEmulator
        ? 'Real settings are in Firestore emulator mode'
        : false;
  } on FirestoreEndpointException {
    return 'Real Firestore settings are invalid';
  }
}();

void main() {
  group('authentication', () {
    final endpoints =
        <String, Future<Response> Function(RequestContext, ChatDependencies)>{
          'GET /tutor/me': (c, d) => handleChatMe(c, ChatRole.tutor, d),
          'GET /tutor/conversations': (c, d) =>
              handleChatConversations(c, ChatRole.tutor, d),
          'GET /tutor/conversations/unread-count': (c, d) =>
              handleChatUnreadCount(c, ChatRole.tutor, d),
          'GET /tutor/conversations/10/messages': (c, d) =>
              handleChatMessages(c, ChatRole.tutor, '10', d),
          'GET /student/conversations': (c, d) =>
              handleChatConversations(c, ChatRole.student, d),
          'GET /student/conversations/1/messages': (c, d) =>
              handleChatMessages(c, ChatRole.student, '1', d),
        };

    for (final MapEntry(key: name, value: call) in endpoints.entries) {
      test('$name without a token is 401', () async {
        final (status, body) = await _send(
          call(_context('GET', '/'), _deps(_World())),
        );
        expect(status, 401);
        expect(body, {'error': 'You must be signed in.'});
      });
    }

    test('POST and PUT without a token are 401 and change nothing', () async {
      final w = await _seeded();
      final before = Map.of(w.firestore.docs);
      final (sendStatus, _) = await _send(
        handleChatMessages(
          _context('POST', '/', body: _sendBody('x1', 'hi')),
          ChatRole.student,
          '$_tutor',
          _deps(w),
        ),
      );
      final (readStatus, _) = await _send(
        handleChatRead(
          _context('PUT', '/', body: {'upToMessageId': _id(_lerato, 'l2')}),
          ChatRole.tutor,
          '$_lerato',
          _deps(w),
        ),
      );
      expect(sendStatus, 401);
      expect(readStatus, 401);
      expect(w.firestore.docs, before);
    });

    test('Firebase misconfiguration is 500, outages are 503', () async {
      Future<int> statusWith(ChatTokenVerifier verify) async {
        final (status, _) = await _send(
          handleChatConversations(
            _context('GET', '/', uid: 'uid-theo'),
            ChatRole.tutor,
            _deps(_World(), verify: verify),
          ),
        );
        return status;
      }

      expect(
        await statusWith((_) async => throw StateError('no project id')),
        500,
      );
      expect(await statusWith((_) async => throw Exception('network')), 503);
    });

    test('a student token cannot use tutor routes, and vice versa', () async {
      final w = _World();
      final (asTutor, tutorBody) = await _send(
        handleChatConversations(
          _context('GET', '/', uid: 'uid-lerato'),
          ChatRole.tutor,
          _deps(w),
        ),
      );
      final (asStudent, _) = await _send(
        handleChatConversations(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.student,
          _deps(w),
        ),
      );
      expect(asTutor, 403);
      expect(tutorBody, {'error': 'An active tutor account is required.'});
      expect(asStudent, 403);
    });

    test('accounts that are not Active are refused', () async {
      final w = _World();
      final (pending, _) = await _send(
        handleChatMe(
          _context('GET', '/', uid: 'uid-pending'),
          ChatRole.tutor,
          _deps(w),
        ),
      );
      final (suspended, _) = await _send(
        handleChatConversations(
          _context('GET', '/', uid: 'uid-suspended'),
          ChatRole.student,
          _deps(w),
        ),
      );
      expect(pending, 403);
      expect(suspended, 403);
    });

    test('wrong methods are 405', () async {
      final (status, _) = await _send(
        handleChatRead(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          '$_lerato',
          _deps(_World()),
        ),
      );
      expect(status, 405);
    });

    test('GET /tutor/me returns the tutor user id', () async {
      final (status, body) = await _send(
        handleChatMe(
          _context('GET', '/tutor/me', uid: 'uid-theo'),
          ChatRole.tutor,
          _deps(_World()),
        ),
      );
      expect(status, 200);
      expect(body, {'userId': _tutor, 'name': 'Theo Tutor'});
    });
  });

  group('authorization', () {
    test('a tutor cannot read or message an unrelated student', () async {
      final w = await _seeded();
      final before = Map.of(w.firestore.docs);

      final (readStatus, readBody) = await _messages(
        w,
        ChatRole.tutor,
        'uid-theo',
        _sipho,
      );
      final (sendStatus, _) = await _post(
        w,
        ChatRole.tutor,
        'uid-theo',
        _sipho,
        _sendBody('x1', 'Cold message'),
      );
      final (markStatus, _) = await _read(
        w,
        ChatRole.tutor,
        'uid-theo',
        _sipho,
        body: {'upToMessageId': _id(_sipho, 's1')},
      );

      expect(readStatus, 403);
      expect(readBody, {'error': 'You are not part of this conversation.'});
      expect(sendStatus, 403);
      expect(markStatus, 403);
      expect(w.firestore.docs, before);
    });

    test("another tutor cannot read Theo and Lerato's messages", () async {
      final w = await _seeded();
      final (status, _) = await _messages(
        w,
        ChatRole.tutor,
        'uid-other-tutor',
        _lerato,
      );
      expect(status, 403);
    });

    test('a student only ever sees their own conversation', () async {
      // Sipho may open a chat with Theo (a public tutor) but sees none of
      // Lerato's messages with him.
      final (status, body) = await _messages(
        await _seeded(),
        ChatRole.student,
        'uid-sipho',
        _tutor,
      );
      expect(status, 200);
      expect(body, isEmpty);
    });

    test('a tutor may reply to a first message at once: the conversation in '
        'Firestore is the link, not a MySQL audit row', () async {
      final w = await _seeded();
      final (asked, _) = await _post(
        w,
        ChatRole.student,
        'uid-sipho',
        _tutor,
        _sendBody('q1', 'Are you available for Physics?'),
      );
      expect(asked, 201);

      // Sipho has no booking with Theo, and nothing has been audited.
      final (reply, _) = await _post(
        w,
        ChatRole.tutor,
        'uid-theo',
        _sipho,
        _sendBody('a1', 'Yes, I am.'),
      );
      expect(reply, 201);
    });

    test('students cannot message tutors who are not approved', () async {
      final (status, _) = await _post(
        _World(),
        ChatRole.student,
        'uid-sipho',
        _unapprovedTutor,
        _sendBody('x1', 'Hello'),
      );
      expect(status, 403);
    });

    test('nobody can message an inactive account, but history stays '
        'readable', () async {
      final w = _World();
      await w.seed(
        _suspended,
        _tutor,
        ChatRole.student,
        'old',
        'Before my suspension',
      );
      final (send, sendBody) = await _post(
        w,
        ChatRole.tutor,
        'uid-theo',
        _suspended,
        _sendBody('x1', 'Hello'),
      );
      final (read, readBody) = await _messages(
        w,
        ChatRole.tutor,
        'uid-theo',
        _suspended,
      );
      expect(send, 403);
      expect(sendBody, {'error': 'You cannot send messages to this user.'});
      expect(read, 200);
      expect(readBody, hasLength(1));
    });

    test('the path id must be a user with the other role', () async {
      final w = _World();
      final (asTutorId, body) = await _messages(
        w,
        ChatRole.student,
        'uid-lerato',
        _sipho,
      );
      final (missing, _) = await _messages(w, ChatRole.tutor, 'uid-theo', 999);
      final (bad, _) = await _send(
        handleChatMessages(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          'abc',
          _deps(w),
        ),
      );
      expect(asTutorId, 404);
      expect(body, {'error': 'Tutor not found.'});
      expect(missing, 404);
      expect(bad, 400);
    });
  }, skip: _productionSkip);

  group('sending', () {
    test('stores a new message and returns it with 201', () async {
      final w = await _seeded();
      final (status, body) = await _post(
        w,
        ChatRole.tutor,
        'uid-theo',
        _lerato,
        _sendBody('t2', '  Bring your textbook.  ', receiverId: _lerato),
      );

      expect(status, 201);
      expect(body, {
        'messageId': _id(_tutor, 't2'),
        'seq': 4,
        'senderId': _tutor,
        'receiverId': _lerato,
        'messageText': 'Bring your textbook.',
        'sentAt': '2026-10-24T12:00:00.000Z',
        'isOutgoing': true,
        'bookingId': null,
        'isRead': false,
      });
      expect(w.conversation(_lerato, _tutor)['lastSeq'], 4);
      expect(w.messageCount, 5);
    });

    test('the same clientMessageId and content replays with 200', () async {
      final w = await _seeded();
      final first = await _post(
        w,
        ChatRole.student,
        'uid-lerato',
        _tutor,
        _sendBody('l3', 'One more thing'),
      );
      w.now = _now.add(const Duration(minutes: 5));
      final again = await _post(
        w,
        ChatRole.student,
        'uid-lerato',
        _tutor,
        _sendBody('l3', 'One more thing'),
      );
      expect(first.$1, 201);
      expect(again.$1, 200);
      expect(again.$2, first.$2);
      expect(w.messageCount, 5);
    });

    test('the same clientMessageId with other content is 409', () async {
      final w = await _seeded();
      await _post(
        w,
        ChatRole.student,
        'uid-lerato',
        _tutor,
        _sendBody('l3', 'One more thing'),
      );
      final (status, body) = await _post(
        w,
        ChatRole.student,
        'uid-lerato',
        _tutor,
        _sendBody('l3', 'Something else'),
      );
      expect(status, 409);
      expect(body, {
        'error': 'clientMessageId was already used for a different message.',
      });
      expect(w.messageCount, 5);
    });

    test('a booking in this conversation can be attached', () async {
      final (status, body) = await _post(
        await _seeded(),
        ChatRole.student,
        'uid-lerato',
        _tutor,
        _sendBody('l3', 'About Thursday', bookingId: 100),
      );
      expect(status, 201);
      expect((body as Map)['bookingId'], 100);
    });

    test(
      'while chat is switched off, sends are 503 and store nothing',
      () async {
        final w = await _seeded();
        w.firestore.enableChat(enabled: false);
        final (status, body) = await _post(
          w,
          ChatRole.student,
          'uid-lerato',
          _tutor,
          _sendBody('l3', 'Hello?'),
        );
        expect(status, 503);
        expect(body, {'error': 'Chat is currently unavailable.'});
        expect(w.messageCount, 4);
      },
    );

    final invalid = <String, (Object?, String)>{
      'a missing clientMessageId': (
        {'messageText': 'hi'},
        'clientMessageId must be 16-64 letters, digits, "_" or "-".',
      ),
      'a short clientMessageId': (
        {'clientMessageId': 'abc', 'messageText': 'hi'},
        'clientMessageId must be 16-64 letters, digits, "_" or "-".',
      ),
      'a path in clientMessageId': (
        {'clientMessageId': '../../system/chatConfig', 'messageText': 'hi'},
        'clientMessageId must be 16-64 letters, digits, "_" or "-".',
      ),
      'missing text': (
        {'clientMessageId': _client('x'), 'bookingId': 100},
        'messageText is required.',
      ),
      'blank text': (_sendBody('x', '   '), 'messageText cannot be empty.'),
      'non-text': (
        {'clientMessageId': _client('x'), 'messageText': 42},
        'messageText is required.',
      ),
      'too long': (
        _sendBody('x', 'a' * (maxChatMessageLength + 1)),
        'messageText must be 2000 characters or fewer.',
      ),
      'invalid JSON': ('{not json', 'Request body must be valid JSON.'),
      'a JSON list': ([1, 2], 'Request body must be a JSON object.'),
      'a string bookingId': (
        {
          'clientMessageId': _client('x'),
          'messageText': 'hi',
          'bookingId': '1',
        },
        'bookingId must be a positive whole number.',
      ),
      'a different receiverId': (
        _sendBody('x', 'hi', receiverId: _sipho),
        'receiverId does not match this conversation.',
      ),
      "another pair's booking": (
        _sendBody('x', 'hi', bookingId: 200),
        'bookingId is not a booking in this conversation.',
      ),
    };

    for (final MapEntry(key: name, value: (body, error)) in invalid.entries) {
      test('rejects $name with 400 and stores nothing', () async {
        final w = await _seeded();
        final (status, response) = await _post(
          w,
          ChatRole.student,
          'uid-lerato',
          _tutor,
          body,
        );
        expect(status, 400);
        expect(response, {'error': error});
        expect(w.messageCount, 4);
      });
    }

    test('exactly $maxChatMessageLength characters is accepted', () async {
      final (status, _) = await _post(
        await _seeded(),
        ChatRole.student,
        'uid-lerato',
        _tutor,
        _sendBody('x', 'a' * maxChatMessageLength),
      );
      expect(status, 201);
    });
  }, skip: _productionSkip);

  group('moderation', () {
    Future<(int, dynamic)> post(
      _World w,
      _ModerationMemory mod,
      String text, {
      List<ChatModerationRecord>? flagged,
    }) => _send(
      handleChatMessages(
        _context(
          'POST',
          '/x/$_tutor/messages',
          uid: 'uid-lerato',
          body: _sendBody('m${text.hashCode.abs()}', text),
        ),
        ChatRole.student,
        '$_tutor',
        _deps(w, moderation: mod, flagged: flagged),
      ),
    );

    test('a message with a phone number is blocked and never stored',
        () async {
      final w = await _seeded();
      final mod = _ModerationMemory();
      final flagged = <ChatModerationRecord>[];
      final before = w.messageCount;
      final (status, body) = await post(
        w,
        mod,
        'Call me on 082 555 1234',
        flagged: flagged,
      );

      expect(status, 422);
      expect((body as Map)['code'], 'message_blocked');
      expect(body['error'], contains('a phone number'));
      expect(w.messageCount, before); // the tutor never gets it
      expect(mod.records[_lerato]!.isSuspended, isTrue);
      expect(mod.records[_lerato]!.flaggedText, 'Call me on 082 555 1234');
      expect(mod.records[_lerato]!.otherUserId, _tutor);
      expect(flagged.single.userId, _lerato); // the admins are told
    });

    test('a suspended sender cannot send even a clean message', () async {
      final w = await _seeded();
      final mod = _ModerationMemory();
      await post(w, mod, 'my email is lerato@gmail.com');
      final before = w.messageCount;
      final (status, body) = await post(w, mod, 'See you on Thursday');
      expect(status, 403);
      expect((body as Map)['code'], 'chat_suspended');
      expect(w.messageCount, before);
    });

    test('a clean message is sent as usual', () async {
      final w = await _seeded();
      final mod = _ModerationMemory();
      final (status, _) = await post(w, mod, 'See you on Thursday at 14:00');
      expect(status, 201);
      expect(mod.records, isEmpty);
    });

    test('chat status shows my suspension and the other side\'s', () async {
      final w = await _seeded();
      final mod = _ModerationMemory();
      await post(w, mod, 'add me on WhatsApp');

      final mine = await _send(
        handleChatStatus(
          _context('GET', '/student/chat-status?with=$_tutor', uid: 'uid-lerato'),
          ChatRole.student,
          _deps(w, moderation: mod),
        ),
      );
      expect(mine.$1, 200);
      expect(((mine.$2 as Map)['me'] as Map)['suspended'], isTrue);
      expect((mine.$2 as Map)['otherSuspended'], isFalse);

      // The tutor sees that Lerato's chat is suspended
      final theirs = await _send(
        handleChatStatus(
          _context('GET', '/tutor/chat-status?with=$_lerato', uid: 'uid-theo'),
          ChatRole.tutor,
          _deps(w, moderation: mod),
        ),
      );
      expect(((theirs.$2 as Map)['me'] as Map)['suspended'], isFalse);
      expect((theirs.$2 as Map)['otherSuspended'], isTrue);
    });

    test('the suspended user can send an explanation', () async {
      final w = await _seeded();
      final mod = _ModerationMemory();
      await post(w, mod, 'pay me directly next time');
      final (status, body) = await _send(
        handleChatAppeal(
          _context(
            'POST',
            '/student/chat-appeal',
            uid: 'uid-lerato',
            body: {'explanation': 'I meant through the app, sorry.'},
          ),
          ChatRole.student,
          _deps(w, moderation: mod),
        ),
      );
      expect(status, 200);
      expect(((body as Map)['chatStatus'] as Map)['status'], 'appealed');
      expect(mod.records[_lerato]!.appeal, 'I meant through the app, sorry.');
    });
  });

  group('retrieval', () {
    test(
      "returns the conversation oldest first, from the caller's side",
      () async {
        final w = await _seeded();
        final (tutorStatus, asTutor) = await _messages(
          w,
          ChatRole.tutor,
          'uid-theo',
          _lerato,
        );
        final (_, asStudent) = await _messages(
          w,
          ChatRole.student,
          'uid-lerato',
          _tutor,
        );

        expect(tutorStatus, 200);
        final tutorView = (asTutor as List).cast<Map<String, dynamic>>();
        expect(tutorView.map((m) => m['messageId']), [
          _id(_lerato, 'l1'),
          _id(_tutor, 't1'),
          _id(_lerato, 'l2'),
        ]);
        expect(tutorView.map((m) => m['seq']), [1, 2, 3]);
        expect(tutorView.map((m) => m['isOutgoing']), [false, true, false]);
        // Theo read L1 only; Lerato has not read T1.
        expect(tutorView.map((m) => m['isRead']), [true, false, false]);
        expect(tutorView.first['sentAt'], '2026-10-24T09:00:00.000Z');
        final studentView = (asStudent as List).cast<Map<String, dynamic>>();
        expect(studentView.map((m) => m['isOutgoing']), [true, false, true]);
      },
    );

    test('pages older messages with beforeSeq and X-Next-Before-Seq', () async {
      final w = _World();
      for (var i = 1; i <= chatMessagePageSize + 1; i++) {
        await w.seed(_lerato, _tutor, ChatRole.student, 'm$i', 'Message $i');
      }
      final (status, newest, headers) = await _call(
        handleChatMessages(
          _context('GET', '/x', uid: 'uid-theo'),
          ChatRole.tutor,
          '$_lerato',
          _deps(w),
        ),
      );
      expect(status, 200);
      expect((newest as List).cast<Map<String, dynamic>>().first['seq'], 2);
      expect(newest, hasLength(chatMessagePageSize));
      expect(headers['x-next-before-seq'], '2');

      final (_, older, olderHeaders) = await _call(
        handleChatMessages(
          _context('GET', '/x?beforeSeq=2', uid: 'uid-theo'),
          ChatRole.tutor,
          '$_lerato',
          _deps(w),
        ),
      );
      expect(
        (older as List).cast<Map<String, dynamic>>().map((m) => m['seq']),
        [1],
      );
      expect(olderHeaders.containsKey('x-next-before-seq'), isFalse);

      final (bad, _) = await _messages(
        w,
        ChatRole.tutor,
        'uid-theo',
        _lerato,
        query: '?beforeSeq=zero',
      );
      expect(bad, 400);
    });

    test('the tutor conversation list matches the app contract', () async {
      final (status, body) = await _send(
        handleChatConversations(
          _context('GET', '/tutor/conversations', uid: 'uid-theo'),
          ChatRole.tutor,
          _deps(await _seeded()),
        ),
      );
      expect(status, 200);
      expect(body, [
        {
          'conversationId': 's10_t1',
          'userId': _lerato,
          'name': 'Lerato Phiri',
          'initials': 'LP',
          'profilePhotoUrl': null,
          'lastMessage': 'Great, see you then!',
          'time': '2h ago',
          'lastMessageAt': '2026-10-24T10:00:00.000Z',
          'unreadCount': 1,
          'isOnline': false,
        },
      ]);
    });

    test('the student conversation list only shows their tutors', () async {
      final (status, body) = await _send(
        handleChatConversations(
          _context('GET', '/student/conversations', uid: 'uid-lerato'),
          ChatRole.student,
          _deps(await _seeded()),
        ),
      );
      expect(status, 200);
      final list = (body as List).cast<Map<String, dynamic>>();
      expect(list.map((c) => c['userId']), [_tutor]);
      expect(list.single['unreadCount'], 1);
    });

    test(
      'conversations page with X-Next-Cursor; bad cursors are 400',
      () async {
        final w = _World();
        final students = [
          for (var i = 0; i <= chatConversationPageSize; i++)
            _User(1000 + i, 'uid-s$i', ChatRole.student, 'Student $i'),
        ];
        final world = _World();
        final permissions = _FakePermissions(
          users: [..._users, ...students],
          bookings: _bookings,
        );
        for (final s in students) {
          await world.store.send(
            ChatSendCommand(
              student: ChatParty(userId: s.id, firebaseUid: s.uid),
              tutor: w.party(_tutor),
              senderRole: ChatRole.student,
              clientMessageId: _client('c${s.id}'),
              text: 'Hi',
              senderName: s.name,
            ),
          );
        }
        ChatDependencies deps() => ChatDependencies(
          verifyToken: _verify,
          permissions: () async => permissions,
          store: () async => world.store,
          audit: () async => throw StateError('audit opened'),
          clock: () => _now,
        );

        final (status, first, headers) = await _call(
          handleChatConversations(
            _context('GET', '/', uid: 'uid-theo'),
            ChatRole.tutor,
            deps(),
          ),
        );
        expect(status, 200);
        expect(first, hasLength(chatConversationPageSize));
        final cursor = headers['x-next-cursor']!;

        final (_, rest, restHeaders) = await _call(
          handleChatConversations(
            _context(
              'GET',
              '/?cursor=${Uri.encodeQueryComponent(cursor)}',
              uid: 'uid-theo',
            ),
            ChatRole.tutor,
            deps(),
          ),
        );
        expect(rest, hasLength(1));
        expect(restHeaders.containsKey('x-next-cursor'), isFalse);

        final (bad, badBody, _) = await _call(
          handleChatConversations(
            _context('GET', '/?cursor=garbage', uid: 'uid-theo'),
            ChatRole.tutor,
            deps(),
          ),
        );
        expect(bad, 400);
        expect(badBody, {'error': 'cursor is not valid.'});
      },
    );

    test('conversations with users missing from MySQL are left out', () async {
      final w = await _seeded();
      final ghostStore = FirestoreChatStore(
        w.firestore.rest(),
        clock: () => _now,
      );
      await ghostStore.send(
        ChatSendCommand(
          student: ChatParty(userId: 77, firebaseUid: 'uid-ghost'),
          tutor: w.party(_tutor),
          senderRole: ChatRole.student,
          clientMessageId: _client('ghost'),
          text: 'Boo',
          senderName: 'Ghost',
        ),
      );
      final (_, body) = await _send(
        handleChatConversations(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          _deps(w),
        ),
      );
      expect(
        (body as List).cast<Map<String, dynamic>>().map((c) => c['userId']),
        [_lerato],
      );
    });

    test('unread count only counts messages to the caller', () async {
      final w = await _seeded();
      Future<dynamic> unread(ChatRole role, String uid) async => (await _send(
        handleChatUnreadCount(_context('GET', '/', uid: uid), role, _deps(w)),
      )).$2;
      expect(await unread(ChatRole.tutor, 'uid-theo'), {'unreadCount': 1});
      expect(await unread(ChatRole.student, 'uid-lerato'), {'unreadCount': 1});
      expect(await unread(ChatRole.student, 'uid-sipho'), {'unreadCount': 0});
    });
  }, skip: _productionSkip);

  group('mark read', () {
    test('marks up to upToMessageId, never backwards', () async {
      final w = await _seeded();
      final (status, body) = await _read(
        w,
        ChatRole.tutor,
        'uid-theo',
        _lerato,
        body: {'studentId': _lerato, 'upToMessageId': _id(_lerato, 'l2')},
      );
      expect(status, 200);
      expect(body, {'markedRead': 1, 'unreadCount': 0});
      expect(w.conversation(_lerato, _tutor)['readCount'], {
        'student': 0,
        'tutor': 2,
      });

      final (_, again) = await _read(
        w,
        ChatRole.tutor,
        'uid-theo',
        _lerato,
        body: {'upToMessageId': _id(_lerato, 'l1')},
      );
      expect(again, {'markedRead': 0, 'unreadCount': 0});
    });

    test('the student side works too', () async {
      final w = await _seeded();
      final (status, body) = await _read(
        w,
        ChatRole.student,
        'uid-lerato',
        _tutor,
        body: {'upToMessageId': _id(_tutor, 't1')},
      );
      expect(status, 200);
      expect(body, {'markedRead': 1, 'unreadCount': 0});
    });

    final invalid = <String, (Object?, int, String)>{
      'no body': ('', 400, 'Request body must be valid JSON.'),
      'no upToMessageId': (
        {'studentId': _lerato},
        400,
        'upToMessageId is required.',
      ),
      'a malformed upToMessageId': (
        {'upToMessageId': '../system/chatConfig'},
        400,
        'upToMessageId is not valid.',
      ),
      'a body id that does not match the path': (
        {'studentId': _sipho, 'upToMessageId': _id(_lerato, 'l2')},
        400,
        'studentId does not match this conversation.',
      ),
      'an unknown message': (
        {'upToMessageId': _id(_lerato, 'zz')},
        404,
        'upToMessageId is not in this conversation.',
      ),
    };
    for (final MapEntry(key: name, value: (body, code, error))
        in invalid.entries) {
      test('rejects $name', () async {
        final w = await _seeded();
        final before = Map.of(w.firestore.docs);
        final (status, response) = await _read(
          w,
          ChatRole.tutor,
          'uid-theo',
          _lerato,
          body: body,
        );
        expect(status, code);
        expect(response, {'error': error});
        expect(w.firestore.docs, before);
      });
    }

    test('while chat is switched off, mark-read is 503', () async {
      final w = await _seeded();
      w.firestore.enableChat(enabled: false);
      final (status, _) = await _read(
        w,
        ChatRole.tutor,
        'uid-theo',
        _lerato,
        body: {'upToMessageId': _id(_lerato, 'l2')},
      );
      expect(status, 503);
    });
  }, skip: _productionSkip);

  group('store and setup failures', () {
    test('/me uses the permission checks only; the store and audit table '
        'are never opened', () async {
      final (status, body) = await _send(
        handleChatMe(
          _context('GET', '/tutor/me', uid: 'uid-theo'),
          ChatRole.tutor,
          ChatDependencies(
            verifyToken: _verify,
            permissions: () async => _World().permissions,
            store: () async => throw StateError('store opened'),
            audit: () async => throw StateError('audit opened'),
          ),
        ),
      );
      expect(status, 200);
      expect(body, {'userId': _tutor, 'name': 'Theo Tutor'});
    });

    test('a full send, read and list never touches the audit table', () async {
      final w = await _seeded();
      var auditOpened = 0;
      final deps = ChatDependencies(
        verifyToken: _verify,
        permissions: () async => w.permissions,
        store: () async => w.store,
        audit: () async {
          auditOpened++;
          throw StateError('audit opened');
        },
        clock: () => _now,
      );
      final calls = <Future<Response> Function()>[
        () => handleChatMessages(
          _context('POST', '/', uid: 'uid-lerato', body: _sendBody('l9', 'x')),
          ChatRole.student,
          '$_tutor',
          deps,
        ),
        () => handleChatRead(
          _context(
            'PUT',
            '/',
            uid: 'uid-theo',
            body: {'upToMessageId': _id(_lerato, 'l9')},
          ),
          ChatRole.tutor,
          '$_lerato',
          deps,
        ),
        () => handleChatMessages(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          '$_lerato',
          deps,
        ),
        () => handleChatConversations(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          deps,
        ),
        () => handleChatUnreadCount(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          deps,
        ),
      ];
      // One after another, as the app would.
      final statuses = [for (final c in calls) (await _send(c())).$1];
      expect(statuses, [201, 200, 200, 200, 200]);
      expect(auditOpened, 0);
    });

    test('setup problems are 500, not 503', () async {
      Future<(int, dynamic)> withStore(ChatStoreFactory store) => _send(
        handleChatConversations(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          _deps(_World(), store: store),
        ),
      );
      for (final failure in <Exception>[
        const ChatSetupException('x'),
        const FirebaseAdminException('service account missing'),
      ]) {
        final (status, body) = await withStore(() async => throw failure);
        expect(status, 500, reason: '$failure');
        expect(body, {'error': 'Chat is not configured correctly.'});
      }
    });

    test('Firestore outages are 503 and do not leak details', () async {
      final (status, body) = await _send(
        handleChatConversations(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          _deps(
            _World(),
            store: () async => throw const FirestoreUnavailable(
              'Firestore POST returned HTTP 503 secret-detail.',
            ),
          ),
        ),
      );
      expect(status, 503);
      expect(jsonEncode(body), isNot(contains('secret')));
    });

    test('inconsistent stored chats are 500 and do not leak details', () async {
      final w = await _seeded();
      w.firestore.put('conversations/s10_t1', {'lastSeq': 'oops'});
      final (status, body) = await _messages(
        w,
        ChatRole.tutor,
        'uid-theo',
        _lerato,
      );
      expect(status, 500);
      expect(body, {
        'error': 'Chat data is inconsistent. Please contact support.',
      });
    });

    test('MySQL failures are 503 and do not leak details', () async {
      final (status, body) = await _send(
        handleChatConversations(
          _context('GET', '/', uid: 'uid-theo'),
          ChatRole.tutor,
          ChatDependencies(
            verifyToken: _verify,
            permissions: () async =>
                throw Exception('Access denied for user root password=secret'),
            store: () async => throw StateError('not opened'),
            audit: () async => throw StateError('not opened'),
          ),
        ),
      );
      expect(status, 503);
      expect(jsonEncode(body), isNot(contains('secret')));
    });
  }, skip: _productionSkip);

  group('MySqlChatPermissions SQL', () {
    setUpAll(() => registerFallbackValue(<String, dynamic>{}));

    test('signedIn loads the Firebase UID of an Active user', () async {
      final (conn, calls) = _connection(
        rows: [
          {
            'UserId': '1',
            'Name': 'Theo Tutor',
            'ProfilePhoto': null,
            'FirebaseUid': 'uid-theo',
            'IsActive': '1',
            'IsApproved': '1',
          },
        ],
      );
      final me = await MySqlChatPermissions(
        conn,
      ).signedIn('uid-theo', ChatRole.tutor);

      final (sql, params) = calls.single;
      expect(params, {'uid': 'uid-theo', 'role': 'tutor'});
      expect(sql, contains('u.FirebaseUid'));
      expect(sql, contains("u.AccountStatus = 'Active'"));
      expect(sql, contains('JOIN tutorprofile p'));
      expect(me!.firebaseUid, 'uid-theo');
      expect(me.isPublicTutor, isTrue);
    });

    test('profiles uses one named parameter per (unique) id', () async {
      final (conn, calls) = _connection(
        rows: [
          {
            'UserId': '10',
            'Name': 'Lerato Phiri',
            'ProfilePhoto': 'https://res.cloudinary.com/x/a.jpg',
            'FirebaseUid': 'uid-lerato',
            'IsActive': '1',
            'IsApproved': '0',
          },
        ],
      );
      final found = await MySqlChatPermissions(
        conn,
      ).profiles([10, 12345, 10], ChatRole.student);

      final (sql, params) = calls.single;
      expect(sql, contains('u.UserId IN (:id0, :id1)'));
      expect(sql, isNot(contains('12345')));
      expect(params, {'role': 'student', 'id0': 10, 'id1': 12345});
      expect(found.keys, [10]);
      expect(found[10]!.firebaseUid, 'uid-lerato');
      expect(found[10]!.profilePhoto, 'https://res.cloudinary.com/x/a.jpg');
    });

    test('hasBooking asks Booking only, never the Messaging table', () async {
      final (conn, calls) = _connection(
        rows: [
          {'1': '1'},
        ],
      );
      final booked = await MySqlChatPermissions(
        conn,
      ).hasBooking(studentUserId: _lerato, tutorUserId: _tutor);

      final (sql, params) = calls.single;
      expect(booked, isTrue);
      expect(params, {'studentUserId': _lerato, 'tutorUserId': _tutor});
      expect(sql, contains('FROM booking b'));
      expect(sql, isNot(contains('Messaging')));
    });

    test('profiles rejects empty, oversized and invalid lookups', () async {
      final (conn, calls) = _connection();
      final permissions = MySqlChatPermissions(conn);
      expect(await permissions.profiles([], ChatRole.tutor), isEmpty);
      await expectLater(
        permissions.profiles([
          for (var i = 1; i <= maxChatProfileLookup + 1; i++) i,
        ], ChatRole.tutor),
        throwsArgumentError,
      );
      await expectLater(
        permissions.profiles([0], ChatRole.tutor),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });
  });

  group('MySqlChatAudit SQL', () {
    setUpAll(() => registerFallbackValue(<String, dynamic>{}));

    ChatAuditMessage message({
      String id = 's10_t1/10-abcdefghijklmnop',
      int sender = _lerato,
      int receiver = _tutor,
      String text = 'Hello',
      bool isRead = false,
      int? bookingId = 100,
    }) => ChatAuditMessage(
      firestoreMessageId: id,
      senderId: sender,
      receiverId: receiver,
      messageText: text,
      sentAt: DateTime.utc(2026, 10, 24, 9, 41, 7, 999),
      isRead: isRead,
      bookingId: bookingId,
    );

    test('recordMessage inserts once and only ever sets IsRead', () async {
      final (conn, calls) = _connection();
      await MySqlChatAudit(conn).recordMessage(message(isRead: true));

      final (sql, params) = calls.single;
      expect(sql, MySqlChatAudit.recordSql);
      expect(
        sql,
        contains('ON DUPLICATE KEY UPDATE IsRead = IsRead OR VALUES(IsRead)'),
      );
      expect(params, {
        'firestoreMessageId': 's10_t1/10-abcdefghijklmnop',
        'senderId': _lerato,
        'receiverId': _tutor,
        'bookingId': 100,
        'messageText': 'Hello',
        'sentAt': '2026-10-24 09:41:07',
        'isRead': 1,
      });
    });

    test('audit records reject values the table cannot hold', () {
      for (final build in <void Function()>[
        () => message(id: 'no-slash'),
        () => message(id: 's1_t2/../x'),
        () => message(id: 's1_t2/${'a' * 130}'),
        () => message(sender: _tutor),
        () => message(sender: 0),
        () => message(text: '   '),
        () => message(text: 'a' * (maxChatMessageLength + 1)),
        () => message(bookingId: 0),
      ]) {
        expect(build, throwsArgumentError);
      }
    });

    test('presentIds asks with one parameter per unique id', () async {
      final (conn, calls) = _connection(
        rows: [
          {'FirestoreMessageID': 's10_t1/10-a'},
        ],
      );
      final present = await MySqlChatAudit(
        conn,
      ).presentIds(['s10_t1/10-a', 's10_t1/1-b', 's10_t1/10-a']);

      final (sql, params) = calls.single;
      expect(sql, contains('FirestoreMessageID IN (:id0, :id1)'));
      expect(params, {'id0': 's10_t1/10-a', 'id1': 's10_t1/1-b'});
      expect(present, {'s10_t1/10-a'});
    });

    test('markRead only touches unread rows and reports the count', () async {
      final (conn, calls) = _connection(affected: 2);
      final changed = await MySqlChatAudit(
        conn,
      ).markRead(['s10_t1/1-a', 's10_t1/1-b']);

      final (sql, params) = calls.single;
      expect(sql, contains('SET IsRead = TRUE'));
      expect(sql, contains('WHERE IsRead = FALSE AND FirestoreMessageID IN'));
      expect(params, {'id0': 's10_t1/1-a', 'id1': 's10_t1/1-b'});
      expect(changed, 2);
    });

    test(
      'id lists: empty sends nothing; oversized or invalid is refused',
      () async {
        final (conn, calls) = _connection();
        final audit = MySqlChatAudit(conn);
        expect(await audit.presentIds([]), isEmpty);
        expect(await audit.markRead([]), 0);
        await expectLater(
          audit.markRead([
            for (var i = 0; i <= maxChatAuditBatch; i++) 's1_t2/1-$i',
          ]),
          throwsArgumentError,
        );
        await expectLater(
          audit.presentIds(["s1_t2/x' OR '1'='1"]),
          throwsArgumentError,
        );
        expect(calls, isEmpty);
      },
    );

    test('mySqlUtcDateTime is UTC to the second', () {
      expect(
        mySqlUtcDateTime(DateTime.parse('2026-10-24T11:41:07.999+02:00')),
        '2026-10-24 09:41:07',
      );
      expect(
        mySqlUtcDateTime(DateTime.utc(999, 1, 2, 3, 4, 5)),
        '0999-01-02 03:04:05',
      );
    });
  });

  group('default factories (child process)', () {
    test('in emulator mode the MySQL factories fail closed before connecting; '
        'the store points at the emulator', () async {
      final steps = await _runDefaultFactoryProbe({
        firestoreEmulatorHostVariable: '127.0.0.1:8085',
        firestoreEmulatorProjectVariable: 'demo-theotutoring',
      });
      expect(steps.keys, [
        'permissions',
        'store',
        'audit',
        'productionStore',
      ]);
      for (final step in ['permissions', 'audit']) {
        expect(
          steps[step],
          startsWith('REFUSED Firestore emulator mode is on'),
          reason: step,
        );
      }
      expect(steps['store'], 'OPENED');
      expect(steps['productionStore'], 'REFUSED requests=0 token=false');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('without emulator or injected credentials the default store refuses '
        'before Firestore IO', () async {
      final steps = await _runDefaultFactoryProbe(const {});
      expect(
        steps['store'],
        'REFUSED FIREBASE_SERVICE_ACCOUNT_FILE is not set',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'with invalid Firestore settings every factory fails closed',
      () async {
        final steps = await _runDefaultFactoryProbe({
          firestoreEmulatorHostVariable: '10.0.0.5:8085',
          firestoreEmulatorProjectVariable: 'demo-theotutoring',
        });
        for (final step in ['permissions', 'store', 'audit']) {
          expect(
            steps[step],
            startsWith('REFUSED Invalid Firestore settings'),
            reason: step,
          );
        }
        expect(steps['productionStore'], 'REFUSED requests=0 token=false');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('helpers', () {
    test('chatTimeLabel', () {
      String label(Duration ago) => chatTimeLabel(_now.subtract(ago), _now);
      expect(label(const Duration(seconds: 20)), 'Just now');
      expect(label(const Duration(minutes: 5)), '5m ago');
      expect(label(const Duration(hours: 2)), '2h ago');
      expect(label(const Duration(days: 3)), '3d ago');
      expect(label(const Duration(days: 10)), '14 Oct');
    });

    test('chatInitials', () {
      expect(chatInitials('Lerato Phiri'), 'LP');
      expect(chatInitials('  thabo  '), 'T');
      expect(chatInitials(''), '?');
    });
  });
}

// ─── MySQL stand-ins (no database) ──────────────────────────────────────────

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

/// A connection that records each query and answers every one with [rows]
/// and [affected].
(MySQLConnection, List<(String, Map<String, dynamic>?)>) _connection({
  List<Map<String, String?>> rows = const [],
  int affected = 0,
}) {
  final calls = <(String, Map<String, dynamic>?)>[];
  // Rows are built first: mocktail cannot stub inside another stub.
  final resultRows = [for (final values in rows) _row(values)];
  final result = _MockResult();
  when(() => result.rows).thenReturn(resultRows);
  when(() => result.affectedRows).thenReturn(BigInt.from(affected));
  final connection = _MockConnection();
  when(() => connection.execute(any(), any())).thenAnswer((invocation) async {
    calls.add((
      invocation.positionalArguments[0] as String,
      invocation.positionalArguments[1] as Map<String, dynamic>?,
    ));
    return result;
  });
  return (connection, calls);
}

ResultSetRow _row(Map<String, String?> values) {
  final row = _MockRow();
  when(row.assoc).thenReturn(values);
  when(() => row.str(any())).thenAnswer(
    (invocation) => values[invocation.positionalArguments.first as String],
  );
  return row;
}

// ─── Default-factory probe ──────────────────────────────────────────────────

/// Opens the default ChatDependencies factories in a child process with
/// [environment] added. The child runs in an empty temporary folder (no
/// .env) with the database pointed at a closed local port, so even a broken
/// guard could not reach a real database.
Future<Map<String, String>> _runDefaultFactoryProbe(
  Map<String, String> environment,
) async {
  final dir = Directory.systemTemp.createTempSync('chat_default_probe');
  try {
    const inheritedOsKeys = [
      'PATH',
      'SystemRoot',
      'WINDIR',
      'TEMP',
      'TMP',
      'HOME',
    ];
    final childEnvironment = <String, String>{
      for (final key in inheritedOsKeys)
        if (Platform.environment.containsKey(key))
          key: Platform.environment[key]!,
      'DB_HOST': '127.0.0.1',
      'DB_PORT': '9',
      'DB_NAME': 'no_database',
      'DB_USER': 'nobody',
      'DB_PASSWORD': '',
      ...environment,
    };
    File(
      '${dir.path}${Platform.pathSeparator}probe.dart',
    ).writeAsStringSync(_defaultFactoryProbe);
    final packages = File(
      '${Directory.current.path}/.dart_tool/package_config.json',
    ).absolute.path;
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['--packages=$packages', 'probe.dart'],
      workingDirectory: dir.path,
      environment: childEnvironment,
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return {
      for (final line in LineSplitter.split(result.stdout as String))
        if (line.contains(': '))
          line.substring(0, line.indexOf(': ')): line.substring(
            line.indexOf(': ') + 2,
          ),
    };
  } finally {
    dir.deleteSync(recursive: true);
  }
}

const _defaultFactoryProbe = r'''
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';
import 'package:theo_tutoring_backend/chat_moderation.dart';
import 'package:theo_tutoring_backend/chat_store.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';

Future<void> main() async {
  final deps = ChatDependencies.production();
  final factories = <(String, Future<Object> Function())>[
    ('permissions', deps.permissions),
    ('store', deps.store),
    ('audit', deps.audit),
  ];
  for (final (name, open) in factories) {
    try {
      await open();
      stdout.writeln('$name: OPENED');
    } on ChatSetupException catch (e) {
      stdout.writeln('$name: REFUSED ${e.message}');
    } on FirebaseAdminException catch (e) {
      stdout.writeln('$name: REFUSED ${e.message}');
    } on Object catch (e) {
      stdout.writeln('$name: ERROR ${e.runtimeType}');
    }
  }

  // A chat store aimed at production must be refused before its token is
  // asked for or any request is made.
  var tokenAsked = false;
  final requests = <http.BaseRequest>[];
  final client = MockClient((request) async {
    requests.add(request);
    return http.Response('{}', 200);
  });
  try {
    await FirestoreChatStore(
      FirestoreRest(
        projectId: 'theo-test',
        accessToken: () async {
          tokenAsked = true;
          return 'real-token';
        },
        client: client,
      ),
    ).hasConversation(10, 1);
    stdout.writeln('productionStore: SENT');
  } on FirestoreException {
    // Allowed outside emulator mode: the request reached the fake client.
    stdout.writeln('productionStore: SENT');
  } on FirebaseAdminException {
    stdout.writeln(
      'productionStore: REFUSED requests=${requests.length} token=$tokenAsked',
    );
  }
  exit(0); // a broken guard may leave a connection attempt behind
}
''';
