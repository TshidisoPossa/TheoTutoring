import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_audit.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';
import 'package:theo_tutoring_backend/chat_outbox.dart';
import 'package:theo_tutoring_backend/chat_store.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';
import 'package:theo_tutoring_backend/notifications.dart';

import 'support/fake_firestore.dart';

// The outbox worker against the fake Firestore (no network) and an
// in-memory audit table that can be made to fail.

class _FakeAudit implements ChatAuditSink {
  final rows = <String, bool>{}; // FirestoreMessageID -> IsRead
  final batches = <int>[];
  int records = 0;
  bool failRecord = false;
  final failFor = <String>{};
  bool failMarkRead = false;

  @override
  Future<void> recordMessage(ChatAuditMessage m) async {
    records++;
    if (failRecord || failFor.contains(m.firestoreMessageId)) {
      throw Exception('MySQL is down');
    }
    rows[m.firestoreMessageId] =
        (rows[m.firestoreMessageId] ?? false) || m.isRead;
  }

  @override
  Future<Set<String>> presentIds(List<String> ids) async {
    expect(ids.length, lessThanOrEqualTo(maxChatAuditBatch));
    return ids.where(rows.containsKey).toSet();
  }

  @override
  Future<int> markRead(List<String> ids) async {
    expect(ids.length, lessThanOrEqualTo(maxChatAuditBatch));
    if (failMarkRead) throw Exception('MySQL is down');
    batches.add(ids.length);
    var changed = 0;
    for (final id in ids) {
      if (rows[id] == false) {
        rows[id] = true;
        changed++;
      }
    }
    return changed;
  }
}

final _t0 = DateTime.utc(2026, 10, 24, 12);
final _student = ChatParty(userId: 10, firebaseUid: 'uid-lerato');
final _tutor = ChatParty(userId: 1, firebaseUid: 'uid-theo');
const _cid = 's10_t1';

String _client(int n) => 'client-$n-'.padRight(20, 'x');

class _World {
  final firestore = FakeFirestore()..enableChat();
  final audit = _FakeAudit();
  DateTime now = _t0;
  late final store = FirestoreChatStore(firestore.rest(), clock: () => now);
  late final notifications = NotificationStore(
    projectId: fakeFirestoreProject,
    accessToken: () async => 'token',
    client: firestore.client,
  );
  late final worker = ChatOutboxWorker(
    rest: firestore.rest(),
    audit: audit,
    notifications: notifications,
    clock: () => now,
  );

  Future<StoredChatMessage> send(
    int n, {
    ChatRole from = ChatRole.student,
  }) async => (await store.send(
    ChatSendCommand(
      student: _student,
      tutor: _tutor,
      senderRole: from,
      clientMessageId: _client(n),
      text: 'Message $n',
      senderName: from == ChatRole.student ? 'Lerato' : 'Theo',
    ),
  )).message;

  Future<void> readUpTo(StoredChatMessage m, {ChatRole by = ChatRole.tutor}) =>
      store.markRead(
        ChatReadCommand(
          studentUserId: 10,
          tutorUserId: 1,
          readerRole: by,
          upToMessageId: m.messageId,
        ),
      );

  FirestoreDocument entry(String id) => FirestoreDocument(
    path: 'chatOutbox/$id',
    fields: firestore.fields('chatOutbox/$id')!,
    updateTime: firestore.docs['chatOutbox/$id']!.updateTime,
  );

  bool has(String id) => firestore.docs.containsKey('chatOutbox/$id');

  Future<ChatOutboxOutcome> process(String id) => worker.process(entry(id));

  String m(StoredChatMessage msg) => 'm_${_cid}_${msg.messageId}';

  String audited(StoredChatMessage msg) => '$_cid/${msg.messageId}';

  List<String> get notificationsSent =>
      firestore.paths('notifications/').toList();
}

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
  group('outbox', () {
    group('message audit', () {
      test(
        'records the row, then deletes the entry; repeats are harmless',
        () async {
          final w = _World();
          final msg = await w.send(1);
          final stale = w.entry(w.m(msg));

          expect(await w.process(w.m(msg)), ChatOutboxOutcome.done);
          expect(w.audit.rows, {w.audited(msg): false});
          expect(w.has(w.m(msg)), isFalse);

          // A second worker holding the same entry: same row, still done.
          expect(await w.worker.process(stale), ChatOutboxOutcome.done);
          expect(w.audit.rows, hasLength(1));
        },
      );

      test('a MySQL failure keeps the entry; the retry finishes it', () async {
        final w = _World();
        final msg = await w.send(1);
        w.audit.failRecord = true;
        await expectLater(w.process(w.m(msg)), throwsException);
        expect(w.has(w.m(msg)), isTrue, reason: 'MySQL must succeed first');

        w.audit.failRecord = false;
        expect(await w.process(w.m(msg)), ChatOutboxOutcome.done);
        expect(w.audit.rows.keys, [w.audited(msg)]);
      });

      test('a message already read when audited is recorded as read', () async {
        final w = _World();
        final msg = await w.send(1);
        await w.readUpTo(msg);
        await w.process(w.m(msg));
        expect(w.audit.rows[w.audited(msg)], isTrue);
      });
    });

    group('read audit', () {
      test(
        'waits for missing rows, keeps firstPendingAt, then completes',
        () async {
          final w = _World();
          final msgs = [for (var i = 1; i <= 3; i++) await w.send(i)];
          await w.process(w.m(msgs[0])); // only message 1 is audited
          w.now = _t0.add(const Duration(minutes: 5));
          await w.readUpTo(msgs[2]);
          const read = 'r_${_cid}_tutor';
          final firstPendingAt = w.firestore.fields(
            'chatOutbox/$read',
          )!['firstPendingAt'];

          expect(await w.process(read), ChatOutboxOutcome.waiting);
          expect(w.audit.rows[w.audited(msgs[0])], isTrue);
          expect(w.firestore.fields('chatOutbox/$read'), {
            'kind': 'read',
            'conversationId': _cid,
            'readerRole': 'tutor',
            'target': 3,
            'doneThrough': 1, // stopped before the first missing row
            'firstPendingAt': firstPendingAt,
          });

          await w.process(w.m(msgs[1]));
          await w.process(w.m(msgs[2]));
          expect(await w.process(read), ChatOutboxOutcome.done);
          expect(w.audit.rows.values, everyElement(isTrue));
          expect(w.has(read), isFalse);
        },
      );

      test('a newer read target arriving mid-way is not lost', () async {
        final w = _World();
        final msgs = [for (var i = 1; i <= 2; i++) await w.send(i)];
        for (final m in msgs) {
          await w.process(w.m(m));
        }
        await w.readUpTo(msgs[0]);
        const read = 'r_${_cid}_tutor';
        var interfered = false;
        // Just before the entry's delete is committed.
        w.firestore.beforeCommit = (_) {
          final writes = w.firestore.commitBodies.last['writes'] as List;
          final deletes = writes.any(
            (x) =>
                (x as Map)['delete'] == '$fakeFirestoreRoot/chatOutbox/$read',
          );
          if (deletes && !interfered) {
            interfered = true; // another mark-read raises the target
            w.firestore.apply([
              const FirestoreWrite.update(
                'chatOutbox/$read',
                {'target': 2},
                updateMask: ['target'],
              ),
            ]);
          }
        };

        expect(await w.process(read), ChatOutboxOutcome.waiting);
        expect(w.firestore.fields('chatOutbox/$read')!['target'], 2);
        expect(await w.process(read), ChatOutboxOutcome.done);
        expect(w.audit.rows.values, [true, true]);
      });

      test(
        'a mark-read failure keeps progress unchanged for the retry',
        () async {
          final w = _World();
          final msg = await w.send(1);
          await w.process(w.m(msg));
          await w.readUpTo(msg);
          const read = 'r_${_cid}_tutor';
          w.audit.failMarkRead = true;
          await expectLater(w.process(read), throwsException);
          expect(w.firestore.fields('chatOutbox/$read')!['doneThrough'], 0);

          w.audit.failMarkRead = false;
          expect(await w.process(read), ChatOutboxOutcome.done);
        },
      );

      test('works in batches of at most 200 messages', () async {
        final w = _World();
        final msgs = [for (var i = 1; i <= 250; i++) await w.send(i)];
        for (final m in msgs) {
          await w.process(w.m(m));
        }
        await w.readUpTo(msgs.last);

        expect(await w.process('r_${_cid}_tutor'), ChatOutboxOutcome.done);
        expect(w.audit.batches, [200, 50]);
        expect(w.audit.rows.values, everyElement(isTrue));
      });
    });

    group('fake Firestore', () {
      test('does not mask conditional DELETE query parameters', () async {
        final w = _World();
        final msg = await w.send(1);
        final entry = w.entry(w.m(msg));
        // As in the emulator, the query-string condition never matches...
        await expectLater(
          w.firestore.rest().delete(
            entry.path,
            precondition: FirestorePrecondition.updateTime(entry.updateTime),
          ),
          throwsA(isA<FirestoreConflict>()),
        );
        expect(w.has(w.m(msg)), isTrue);
        // ...while the same condition in a commit body works.
        await w.firestore.rest().commit([
          FirestoreWrite.delete(
            entry.path,
            precondition: FirestorePrecondition.updateTime(entry.updateTime),
          ),
        ]);
        expect(w.has(w.m(msg)), isFalse);
      });
    });

    group('notifications', () {
      test(
        'one notification per burst, with a fixed id and no preview',
        () async {
          final w = _World();
          final msg = await w.send(1);
          final stale = w.entry('n_${_cid}_1');

          expect(await w.process('n_${_cid}_1'), ChatOutboxOutcome.done);
          const path = 'notifications/uid-theo/items/msg-s10_t1-1';
          expect(w.notificationsSent, [path]);
          final fields = w.firestore.fields(path)!;
          expect(fields['type'], 'NewMessage');
          expect(fields['body'], 'You have a new message from Lerato.');
          expect(fields.values.whereType<String>(), isNot(contains(msg.text)));

          // A duplicate run finds the notification already there.
          expect(await w.worker.process(stale), ChatOutboxOutcome.done);
          expect(w.notificationsSent, [path]);
        },
      );

      test('skipped when the message was already read', () async {
        final w = _World();
        final msg = await w.send(1);
        await w.readUpTo(msg);
        expect(await w.process('n_${_cid}_1'), ChatOutboxOutcome.done);
        expect(w.notificationsSent, isEmpty);
        expect(w.has('n_${_cid}_1'), isFalse);
      });
    });

    group('runOnce', () {
      test(
        'takes only old entries, at most limit, and isolates failures',
        () async {
          final w = _World();
          final a = await w.send(1);
          final b = await w.send(2);
          w.now = _t0.add(const Duration(minutes: 1));
          await w.send(3); // young: left for its own request

          w.now = _t0.add(const Duration(minutes: 2, seconds: 30));
          final first = await w.worker.runOnce(limit: 2);
          expect((first.done, first.waiting, first.failed), (2, 0, 0));
          expect(w.has(w.m(a)), isFalse);
          expect(w.has(w.m(b)), isTrue);

          w.audit.failFor.add(w.audited(b));
          w.now = _t0.add(const Duration(minutes: 5));
          final second = await w.worker.runOnce();
          expect(second.failed, 1, reason: 'message b fails');
          expect(second.done, 1, reason: 'message c still goes through');
          expect(w.has(w.m(b)), isTrue);

          w.audit.failFor.clear();
          w.now = _t0.add(const Duration(minutes: 10));
          final last = await w.worker.runOnce();
          expect(last.failed, 0);
          expect(w.firestore.paths('chatOutbox/'), isEmpty);
        },
      );

      test('refuses batch sizes above 200', () {
        expect(
          () => _World().worker.runOnce(limit: maxChatAuditBatch + 1),
          throwsArgumentError,
        );
      });
    });

    group('handlers', () {
      Future<FirebaseUser> verify(String? h) async => FirebaseUser(
        uid: h!.substring('Bearer token-'.length),
        email: null,
        emailVerified: true,
      );

      ChatDependencies deps(_World w, {ChatOutboxFactory? outbox}) =>
          ChatDependencies(
            verifyToken: verify,
            permissions: () async => _Permissions(),
            store: () async => w.store,
            audit: () async => throw StateError('handlers must not open it'),
            outbox: outbox ?? () async => w.worker,
            clock: () => _t0,
          );

      test('a send processes its own entries', () async {
        final w = _World();
        final response = await handleChatMessages(
          _post({'clientMessageId': _client(1), 'messageText': 'Hi'}),
          ChatRole.student,
          '1',
          deps(w),
        );
        expect(response.statusCode, 201);
        expect(w.audit.rows, hasLength(1));
        expect(w.notificationsSent, hasLength(1));
        expect(w.firestore.paths('chatOutbox/'), isEmpty);
      });

      test('outbox failures never fail the send', () async {
        final w = _World();
        w.audit.failRecord = true;
        final failing = await handleChatMessages(
          _post({'clientMessageId': _client(1), 'messageText': 'Hi'}),
          ChatRole.student,
          '1',
          deps(w),
        );
        final noWorker = await handleChatMessages(
          _post({'clientMessageId': _client(2), 'messageText': 'Hi'}),
          ChatRole.student,
          '1',
          deps(w, outbox: () async => throw StateError('cannot open')),
        );
        expect(failing.statusCode, 201);
        expect(noWorker.statusCode, 201);
        expect(w.firestore.paths('chatOutbox/m_'), hasLength(2));
      });
    });
  }, skip: _productionSkip);
}

class _MockContext extends Mock implements RequestContext {}

RequestContext _post(Object body) {
  final context = _MockContext();
  when(() => context.request).thenReturn(
    Request(
      'POST',
      Uri.parse('http://localhost/student/conversations/1/messages'),
      headers: {'Authorization': 'Bearer token-uid-lerato'},
      body: jsonEncode(body),
    ),
  );
  return context;
}

class _Permissions implements ChatPermissions {
  ChatParticipant _of(int id, ChatRole role) => ChatParticipant(
    userId: id,
    name: id == 10 ? 'Lerato' : 'Theo',
    role: role,
    firebaseUid: id == 10 ? 'uid-lerato' : 'uid-theo',
    isPublicTutor: role == ChatRole.tutor,
  );

  @override
  Future<ChatParticipant?> signedIn(String uid, ChatRole role) async =>
      uid == 'uid-lerato' && role == ChatRole.student ? _of(10, role) : null;

  @override
  Future<ChatParticipant?> participant(int userId, ChatRole role) async =>
      userId == 1 && role == ChatRole.tutor ? _of(1, role) : null;

  @override
  Future<bool> hasBooking({
    required int studentUserId,
    required int tutorUserId,
  }) async => false;

  @override
  Future<bool> bookingBelongsTo(
    int bookingId, {
    required int studentUserId,
    required int tutorUserId,
  }) async => false;

  @override
  Future<Map<int, ChatParticipant>> profiles(
    List<int> userIds,
    ChatRole role,
  ) async => {};
}
