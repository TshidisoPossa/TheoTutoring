import 'dart:convert';

import 'package:test/test.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_store.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';

import 'support/fake_firestore.dart';

// Planners are tested directly. The store is tested against a fake
// Firestore (a fake HTTP client, no network) that enforces what the store
// relies on the server for: a transaction's commit aborts if anything it
// read has changed, and every write precondition is checked. Real
// Firestore behaviour is confirmed later by the emulator test.

const _project = 'theo-test';
const _root = 'projects/$_project/databases/(default)/documents';

final _student = ChatParty(userId: 10, firebaseUid: 'uid-lerato');
final _tutor = ChatParty(userId: 1, firebaseUid: 'uid-theo');
const _cid = 's10_t1';
final _t0 = DateTime.utc(2026, 10, 24, 12);

String _client(int n) => 'client-message-${n.toString().padLeft(4, '0')}';

ChatSendCommand _send(
  ChatRole sender,
  int n, {
  String text = 'Hello',
  int? bookingId,
}) => ChatSendCommand(
  student: _student,
  tutor: _tutor,
  senderRole: sender,
  clientMessageId: _client(n),
  text: text,
  senderName: sender == ChatRole.student ? 'Lerato' : 'Theo',
  bookingId: bookingId,
);

ChatReadCommand _read(ChatRole reader, String upTo) => ChatReadCommand(
  studentUserId: _student.userId,
  tutorUserId: _tutor.userId,
  readerRole: reader,
  upToMessageId: upTo,
);

String _msgId(ChatRole sender, int n) => chatMessageId(
  sender == ChatRole.student ? _student.userId : _tutor.userId,
  _client(n),
);

// ─── Helpers for planner tests ──────────────────────────────────────────────

FirestoreDocument _doc(String path, Map<String, Object?> fields) =>
    FirestoreDocument(path: path, fields: fields, updateTime: 'ut-$path');

final _enabled = _doc(chatConfigPath, {'enabled': true});

/// The conversation after applying a plan's writes, as a document.
FirestoreDocument _conversationAfter(
  ChatSendWrite plan, {
  String updateTime = 'ut-next',
}) {
  final write = plan.writes.firstWhere(
    (w) => w.path == 'conversations/$_cid',
  );
  return FirestoreDocument(
    path: write.path,
    fields: write.fields!,
    updateTime: updateTime,
  );
}

FirestoreDocument _messageAfter(ChatSendWrite plan) {
  final write = plan.writes.first;
  return FirestoreDocument(
    path: write.path,
    fields: write.fields!,
    updateTime: 'ut-msg',
  );
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
  group('commands', () {
    test('reject invalid ids, text and bookings', () {
      for (final build in <void Function()>[
        () => _send(ChatRole.student, 1, text: '   '),
        () => _send(ChatRole.student, 1, text: 'a' * 2001),
        () => _send(ChatRole.student, 1, bookingId: 0),
        () => ChatSendCommand(
          student: _student,
          tutor: _tutor,
          senderRole: ChatRole.student,
          clientMessageId: 'short',
          text: 'Hi',
          senderName: 'L',
        ),
        () => ChatSendCommand(
          student: _student,
          tutor: _tutor,
          senderRole: ChatRole.student,
          clientMessageId: '../../conversations/x',
          text: 'Hi',
          senderName: 'L',
        ),
        () => ChatParty(userId: 0, firebaseUid: 'x'),
        () => ChatParty(userId: 1, firebaseUid: ' '),
        () => _read(ChatRole.tutor, 'not-an-id'),
        () => ChatReadCommand(
          studentUserId: 1,
          tutorUserId: 1,
          readerRole: ChatRole.tutor,
          upToMessageId: _msgId(ChatRole.student, 1),
        ),
      ]) {
        expect(build, throwsArgumentError);
      }
    });

    test('text is trimmed and ids are derived', () {
      final cmd = _send(ChatRole.tutor, 7, text: '  Hi  ');
      expect(cmd.text, 'Hi');
      expect(cmd.conversationId, _cid);
      expect(cmd.messageId, '1-${_client(7)}');
    });
  });

  group('planChatSend', () {
    test('missing, disabled or non-boolean config refuses', () {
      for (final config in [
        null,
        _doc(chatConfigPath, {'enabled': false}),
        _doc(chatConfigPath, {'enabled': 'true'}),
        _doc(chatConfigPath, {}),
      ]) {
        final plan = planChatSend(
          config: config,
          conversation: null,
          existing: null,
          command: _send(ChatRole.student, 1),
          now: _t0,
        );
        expect(
          plan,
          isA<ChatSendRefused>().having(
            (p) => p.error,
            'error',
            isA<ChatDisabled>(),
          ),
        );
      }
    });

    test('the first message creates everything, guarded server-side', () {
      final plan =
          planChatSend(
                config: _enabled,
                conversation: null,
                existing: null,
                command: _send(ChatRole.student, 1, bookingId: 100),
                now: _t0,
              )
              as ChatSendWrite;

      expect(plan.notify, isTrue);
      expect(plan.message.seq, 1);
      expect(plan.message.counts, (student: 1, tutor: 0));
      expect(plan.message.sentAt, _t0);
      expect(plan.writes.map((w) => w.path), [
        'conversations/$_cid/messages/${_msgId(ChatRole.student, 1)}',
        'conversations/$_cid',
        'chatOutbox/m_${_cid}_${_msgId(ChatRole.student, 1)}',
        'chatOutbox/n_${_cid}_1',
      ]);
      for (final w in plan.writes) {
        expect(w.precondition?.exists, isFalse, reason: w.path);
        expect(w.transforms, isEmpty, reason: 'no server-time transforms');
      }
      final conversation = plan.writes[1].fields!;
      expect(conversation['lastSeq'], 1);
      expect(conversation['sent'], {'student': 1, 'tutor': 0});
      expect(conversation['unread'], {'student': 0, 'tutor': 1});
      expect(conversation['lastSentAt'], _t0);
      expect(conversation['studentUid'], 'uid-lerato');
      final notify = plan.writes.last.fields!;
      expect(notify['receiverUid'], 'uid-theo');
      expect(notify['senderName'], 'Lerato');
      expect(notify.containsKey('text'), isFalse, reason: 'no preview');
    });

    test('later messages chain sequence, counters and burst state', () {
      final first =
          planChatSend(
                config: _enabled,
                conversation: null,
                existing: null,
                command: _send(ChatRole.student, 1),
                now: _t0,
              )
              as ChatSendWrite;
      final second =
          planChatSend(
                config: _enabled,
                conversation: _conversationAfter(first, updateTime: 'ut-1'),
                existing: null,
                command: _send(ChatRole.student, 2),
                now: _t0,
              )
              as ChatSendWrite;
      final reply =
          planChatSend(
                config: _enabled,
                conversation: _conversationAfter(second, updateTime: 'ut-2'),
                existing: null,
                command: _send(ChatRole.tutor, 3),
                now: _t0,
              )
              as ChatSendWrite;

      expect(second.message.seq, 2);
      expect(second.notify, isFalse, reason: 'tutor already has unread');
      expect(second.writes, hasLength(3));
      expect(second.writes[1].precondition?.updateTime, 'ut-1');
      expect(second.writes[1].fields!['unread'], {'student': 0, 'tutor': 2});

      expect(reply.message.seq, 3);
      expect(reply.message.counts, (student: 2, tutor: 1));
      expect(reply.notify, isTrue, reason: 'student had nothing unread');
      expect(reply.writes[1].fields!['unread'], {'student': 1, 'tutor': 2});
    });

    test('a repeat with the same payload replays; anything else conflicts', () {
      final first =
          planChatSend(
                config: _enabled,
                conversation: null,
                existing: null,
                command: _send(ChatRole.student, 1, bookingId: 100),
                now: _t0,
              )
              as ChatSendWrite;
      ChatSendPlan again(ChatSendCommand command) => planChatSend(
        config: _enabled,
        conversation: _conversationAfter(first),
        existing: _messageAfter(first),
        command: command,
        now: _t0.add(const Duration(minutes: 5)),
      );

      expect(
        again(_send(ChatRole.student, 1, bookingId: 100, text: ' Hello ')),
        isA<ChatSendReplay>().having((p) => p.message.sentAt, 'sentAt', _t0),
      );
      for (final different in [
        _send(ChatRole.student, 1, bookingId: 100, text: 'Bye'),
        _send(ChatRole.student, 1),
      ]) {
        expect(
          again(different),
          isA<ChatSendRefused>().having(
            (p) => p.error,
            'error',
            isA<ChatDuplicateConflict>(),
          ),
        );
      }
    });

    test('the kill switch wins over a replay', () {
      final first =
          planChatSend(
                config: _enabled,
                conversation: null,
                existing: null,
                command: _send(ChatRole.student, 1),
                now: _t0,
              )
              as ChatSendWrite;
      expect(
        planChatSend(
          config: null,
          conversation: _conversationAfter(first),
          existing: _messageAfter(first),
          command: _send(ChatRole.student, 1),
          now: _t0,
        ),
        isA<ChatSendRefused>(),
      );
    });

    test('long messages keep a 200-character preview', () {
      final plan =
          planChatSend(
                config: _enabled,
                conversation: null,
                existing: null,
                command: _send(ChatRole.student, 1, text: 'x' * 500),
                now: _t0,
              )
              as ChatSendWrite;
      expect(plan.writes[1].fields!['lastMessage'], 'x' * chatPreviewLength);
      expect(plan.message.text, 'x' * 500);
    });

    test('inconsistent or foreign conversations are refused', () {
      final first =
          planChatSend(
                config: _enabled,
                conversation: null,
                existing: null,
                command: _send(ChatRole.student, 1),
                now: _t0,
              )
              as ChatSendWrite;
      final good = _conversationAfter(first).fields;
      for (final fields in [
        {...good, 'lastSeq': 5},
        {...good, 'tutorUid': 'someone-else'},
        {...good, 'sent': 'x'},
        {
          ...good,
          'readCount': {'student': 0, 'tutor': 9},
        },
      ]) {
        expect(
          () => planChatSend(
            config: _enabled,
            conversation: _doc('conversations/$_cid', fields),
            existing: null,
            command: _send(ChatRole.student, 2),
            now: _t0,
          ),
          throwsA(isA<ChatDataException>()),
        );
      }
      expect(
        () => planChatSend(
          config: _enabled,
          conversation: _doc('conversations/s99_t1', good),
          existing: null,
          command: _send(ChatRole.student, 2),
          now: _t0,
        ),
        throwsA(isA<ChatDataException>()),
      );
    });
  });

  group('planChatMarkRead', () {
    // Student sends 1 and 2, tutor replies 3.
    late ChatSendWrite s1;
    late ChatSendWrite s2;
    late ChatSendWrite t3;
    setUp(() {
      s1 =
          planChatSend(
                config: _enabled,
                conversation: null,
                existing: null,
                command: _send(ChatRole.student, 1),
                now: _t0,
              )
              as ChatSendWrite;
      s2 =
          planChatSend(
                config: _enabled,
                conversation: _conversationAfter(s1),
                existing: null,
                command: _send(ChatRole.student, 2),
                now: _t0,
              )
              as ChatSendWrite;
      t3 =
          planChatSend(
                config: _enabled,
                conversation: _conversationAfter(s2),
                existing: null,
                command: _send(ChatRole.tutor, 3),
                now: _t0,
              )
              as ChatSendWrite;
    });

    ChatReadPlan plan(
      ChatRole reader,
      ChatSendWrite upTo, {
      FirestoreDocument? config,
      Map<String, Object?>? conversationFields,
      FirestoreDocument? outbox,
      bool missingMessage = false,
    }) => planChatMarkRead(
      config: config ?? _enabled,
      conversation: _doc(
        'conversations/$_cid',
        conversationFields ?? _conversationAfter(t3).fields,
      ),
      upTo: missingMessage ? null : _messageAfter(upTo),
      readOutbox: outbox,
      command: _read(reader, upTo.message.messageId),
      now: _t0,
    );

    test('disabled, missing conversation and missing message refuse', () {
      expect(
        plan(ChatRole.tutor, s2, config: _doc(chatConfigPath, {})),
        isA<ChatReadRefused>().having((p) => p.error, 'e', isA<ChatDisabled>()),
      );
      expect(
        planChatMarkRead(
          config: _enabled,
          conversation: null,
          upTo: _messageAfter(s1),
          readOutbox: null,
          command: _read(ChatRole.tutor, s1.message.messageId),
          now: _t0,
        ),
        isA<ChatReadRefused>().having((p) => p.error, 'e', isA<ChatNotFound>()),
      );
      expect(
        plan(ChatRole.tutor, s2, missingMessage: true),
        isA<ChatReadRefused>().having((p) => p.error, 'e', isA<ChatNotFound>()),
      );
    });

    test('reading up to a message from the other side', () {
      final p = plan(ChatRole.tutor, s1) as ChatReadWrite;
      expect(p.markedRead, 1);
      expect(p.unread, 1, reason: 'message 2 is still unread');
      final conversation = p.writes.first;
      expect(conversation.updateMask, ['readCount.tutor', 'unread.tutor']);
      expect(conversation.fields, {
        'readCount': {'tutor': 1},
        'unread': {'tutor': 1},
      });
      expect(
        conversation.precondition?.updateTime,
        'ut-conversations/$_cid',
      );
      final outbox = p.writes.last;
      expect(outbox.path, 'chatOutbox/r_${_cid}_tutor');
      expect(outbox.precondition?.exists, isFalse);
      expect(outbox.fields, containsPair('target', 1));
      expect(outbox.fields, containsPair('doneThrough', 0));
    });

    test('reading up to your own message reads what came before it', () {
      final p = plan(ChatRole.tutor, t3) as ChatReadWrite;
      expect(p.markedRead, 2);
      expect(p.unread, 0);
    });

    test('never moves backwards', () {
      final after = _conversationAfter(t3).fields;
      final read = {
        ...after,
        'readCount': {'student': 0, 'tutor': 2},
        'unread': {'student': 1, 'tutor': 0},
      };
      expect(
        plan(ChatRole.tutor, s1, conversationFields: read),
        isA<ChatReadUnchanged>().having((p) => p.unread, 'unread', 0),
      );
    });

    test('an existing read entry only moves its target', () {
      final p =
          plan(
                ChatRole.tutor,
                s2,
                outbox: _doc('chatOutbox/r_${_cid}_tutor', {
                  'kind': 'read',
                  'target': 1,
                  'doneThrough': 0,
                }),
              )
              as ChatReadWrite;
      final outbox = p.writes.last;
      expect(outbox.updateMask, ['target']);
      expect(outbox.fields, {'target': 2});
      expect(
        outbox.precondition?.updateTime,
        'ut-chatOutbox/r_${_cid}_tutor',
      );
    });

    test('a message from another conversation is rejected', () {
      final foreign = FirestoreDocument(
        path: 'conversations/s99_t1/messages/${s1.message.messageId}',
        fields: _messageAfter(s1).fields,
        updateTime: 'x',
      );
      expect(
        () => planChatMarkRead(
          config: _enabled,
          conversation: _conversationAfter(t3),
          upTo: foreign,
          readOutbox: null,
          command: _read(ChatRole.tutor, s1.message.messageId),
          now: _t0,
        ),
        throwsA(isA<ChatDataException>()),
      );
    });
  });

  group('FirestoreChatStore', () {
    late FakeFirestore fake;
    late FirestoreChatStore store;
    var now = _t0;

    setUp(() {
      fake = FakeFirestore()..enableChat();
      now = _t0;
      store = FirestoreChatStore(fake.rest(), clock: () => now);
    });

    Map<String, Object?> conversation() => fake.fields('conversations/$_cid')!;

    test('send reads config, chat and message in one transaction', () async {
      final result = await store.send(_send(ChatRole.student, 1));

      expect(result.created, isTrue);
      expect(fake.operations, ['beginTransaction', 'batchGet', 'commit']);
      final batch = jsonDecode(fake.requests[1].body) as Map<String, dynamic>;
      expect(batch['transaction'], 'tx-1');
      expect(batch['documents'], [
        '$_root/$chatConfigPath',
        '$_root/conversations/$_cid',
        '$_root/conversations/$_cid/messages/${_msgId(ChatRole.student, 1)}',
      ]);
      expect(fake.commitBodies.single['transaction'], 'tx-1');
    });

    test('sentAt is the backend clock, never the commit time', () async {
      now = DateTime.utc(2026, 10, 24, 12, 34, 56, 789);
      final result = await store.send(_send(ChatRole.student, 1));
      final stored = fake.fields(
        'conversations/$_cid/messages/${_msgId(ChatRole.student, 1)}',
      )!;
      expect(result.message.sentAt, now);
      expect(stored['sentAt'], now);
      expect(conversation()['lastSentAt'], now);
    });

    test('a repeated send replays without writing', () async {
      await store.send(_send(ChatRole.student, 1));
      now = now.add(const Duration(minutes: 1));
      final again = await store.send(_send(ChatRole.student, 1));

      expect(again.created, isFalse);
      expect(again.message.sentAt, _t0);
      expect(fake.commits, 1);
      expect(fake.operations.last, 'rollback');
      expect(fake.paths('conversations/$_cid/messages/'), hasLength(1));
    });

    test('a different payload with the same id is a conflict', () async {
      await store.send(_send(ChatRole.student, 1));
      await expectLater(
        store.send(_send(ChatRole.student, 1, text: 'Changed')),
        throwsA(isA<ChatDuplicateConflict>()),
      );
      expect(fake.commits, 1);
      expect(fake.operations.last, 'rollback');
    });

    test('missing or disabled config refuses and writes nothing', () async {
      fake.docs.remove(chatConfigPath);
      await expectLater(
        store.send(_send(ChatRole.student, 1)),
        throwsA(isA<ChatDisabled>()),
      );
      fake.enableChat(enabled: false);
      await expectLater(
        store.send(_send(ChatRole.student, 1)),
        throwsA(isA<ChatDisabled>()),
      );
      expect(fake.commits, 0);
      expect(fake.paths('conversations/'), isEmpty);
      expect(fake.paths('chatOutbox/'), isEmpty);
    });

    test('a concurrent send gets the next sequence number (retried)', () async {
      fake.beforeCommit = (n) {
        if (n == 1) {
          // Another backend instance commits message 1 first.
          final docs = fake.docs;
          final other =
              planChatSend(
                    config: _enabled,
                    conversation: docs.containsKey('conversations/$_cid')
                        ? _doc('conversations/$_cid', conversation())
                        : null,
                    existing: null,
                    command: _send(ChatRole.tutor, 9),
                    now: _t0,
                  )
                  as ChatSendWrite;
          fake.apply(other.writes);
        }
      };
      final result = await store.send(_send(ChatRole.student, 1));

      expect(fake.commitFailures, ['ABORTED']);
      expect(result.message.seq, 2);
      expect(result.message.counts, (student: 1, tutor: 1));
      expect(conversation()['lastSeq'], 2);
      expect(conversation()['sent'], {'student': 1, 'tutor': 1});
      expect(conversation()['unread'], {'student': 1, 'tutor': 1});
      expect(fake.paths('conversations/$_cid/messages/'), hasLength(2));
    });

    test('preconditions alone stop a lost update (server-side, without '
        'read-set checks)', () async {
      fake = FakeFirestore(checkReadSet: false)..enableChat();
      store = FirestoreChatStore(fake.rest(), clock: () => now);
      await store.send(_send(ChatRole.student, 1));
      fake.beforeCommit = (n) {
        if (n == 2) {
          final other =
              planChatSend(
                    config: _enabled,
                    conversation: _doc('conversations/$_cid', conversation()),
                    existing: null,
                    command: _send(ChatRole.tutor, 9),
                    now: _t0,
                  )
                  as ChatSendWrite;
          fake.apply(other.writes);
        }
      };
      final result = await store.send(_send(ChatRole.student, 2));

      expect(fake.commitFailures, ['FAILED_PRECONDITION']);
      expect(result.message.seq, 3);
      expect(conversation()['sent'], {'student': 2, 'tutor': 1});
    });

    test(
      'the same clientMessageId sent twice at once stores one message',
      () async {
        fake.beforeCommit = (n) {
          if (n == 1) {
            final twin =
                planChatSend(
                      config: _enabled,
                      conversation: null,
                      existing: null,
                      command: _send(ChatRole.student, 1),
                      now: _t0,
                    )
                    as ChatSendWrite;
            fake.apply(twin.writes);
          }
        };
        final result = await store.send(_send(ChatRole.student, 1));

        expect(result.created, isFalse, reason: 'the twin won; this replays');
        expect(fake.paths('conversations/$_cid/messages/'), hasLength(1));
        expect(fake.paths('chatOutbox/m_'), hasLength(1));
        expect(fake.paths('chatOutbox/n_'), hasLength(1));
        expect(conversation()['lastSeq'], 1);
      },
    );

    test('switching chat off during a send stops it (config is in the '
        'read set)', () async {
      fake.beforeCommit = (n) {
        if (n == 1) fake.enableChat(enabled: false);
      };
      await expectLater(
        store.send(_send(ChatRole.student, 1)),
        throwsA(isA<ChatDisabled>()),
      );
      expect(fake.commitFailures, ['ABORTED']);
      expect(fake.paths('conversations/'), isEmpty);
    });

    test('a commit whose reply is lost is replayed by the retry', () async {
      fake.loseNextCommitReply = true;
      await expectLater(
        store.send(_send(ChatRole.student, 1)),
        throwsA(isA<FirestoreUnavailable>()),
      );
      final retry = await store.send(_send(ChatRole.student, 1));
      expect(retry.created, isFalse);
      expect(fake.paths('conversations/$_cid/messages/'), hasLength(1));
    });

    test('constant interference ends in FirestoreRetryExhausted', () async {
      store = FirestoreChatStore(fake.rest(maxAttempts: 3), clock: () => now);
      fake.beforeCommit = (_) => fake.enableChat(); // touches the read set
      await expectLater(
        store.send(_send(ChatRole.student, 1)),
        throwsA(isA<FirestoreRetryExhausted>()),
      );
      expect(fake.commitFailures, ['ABORTED', 'ABORTED', 'ABORTED']);
      expect(fake.paths('conversations/'), isEmpty);
    });

    test('notifications are queued once per unread burst', () async {
      await store.send(_send(ChatRole.student, 1));
      await store.send(_send(ChatRole.student, 2));
      expect(fake.paths('chatOutbox/n_'), ['chatOutbox/n_${_cid}_1']);

      await store.markRead(_read(ChatRole.tutor, _msgId(ChatRole.student, 2)));
      await store.send(_send(ChatRole.student, 3));
      expect(fake.paths('chatOutbox/n_'), [
        'chatOutbox/n_${_cid}_1',
        'chatOutbox/n_${_cid}_3',
      ]);
      expect(fake.paths('chatOutbox/m_'), hasLength(3));
    });

    test('mark-read moves forward, keeps the read entry pending', () async {
      await store.send(_send(ChatRole.student, 1));
      await store.send(_send(ChatRole.student, 2));

      final first = await store.markRead(
        _read(ChatRole.tutor, _msgId(ChatRole.student, 1)),
      );
      const entry = 'chatOutbox/r_${_cid}_tutor';
      final created = fake.fields(entry)!;
      now = now.add(const Duration(minutes: 10));
      final second = await store.markRead(
        _read(ChatRole.tutor, _msgId(ChatRole.student, 2)),
      );
      final backwards = await store.markRead(
        _read(ChatRole.tutor, _msgId(ChatRole.student, 1)),
      );

      expect((first.markedRead, first.unread), (1, 1));
      expect((second.markedRead, second.unread), (1, 0));
      expect((backwards.markedRead, backwards.unread), (0, 0));
      expect(conversation()['readCount'], {'student': 0, 'tutor': 2});
      expect(conversation()['unread'], {'student': 0, 'tutor': 0});
      expect(fake.fields(entry), {
        ...created,
        'target': 2,
      }, reason: 'doneThrough and firstPendingAt are kept');
      expect(fake.operations.last, 'rollback', reason: 'nothing to write');
    });

    test('mark-read racing a new message leaves the new one unread', () async {
      await store.send(_send(ChatRole.student, 1));
      fake.beforeCommit = (n) {
        if (n == 2) {
          final next =
              planChatSend(
                    config: _enabled,
                    conversation: _doc('conversations/$_cid', conversation()),
                    existing: null,
                    command: _send(ChatRole.student, 2),
                    now: _t0,
                  )
                  as ChatSendWrite;
          fake.apply(next.writes);
        }
      };
      final result = await store.markRead(
        _read(ChatRole.tutor, _msgId(ChatRole.student, 1)),
      );

      expect(fake.commitFailures, ['ABORTED']);
      expect(result.unread, 1);
      expect(conversation()['readCount'], {'student': 0, 'tutor': 1});
      expect(conversation()['unread'], {'student': 0, 'tutor': 1});
    });

    test(
      'mark-read is refused when chat is off or the message is unknown',
      () async {
        await store.send(_send(ChatRole.student, 1));
        await expectLater(
          store.markRead(_read(ChatRole.tutor, _msgId(ChatRole.student, 5))),
          throwsA(isA<ChatNotFound>()),
        );
        fake.enableChat(enabled: false);
        await expectLater(
          store.markRead(_read(ChatRole.tutor, _msgId(ChatRole.student, 1))),
          throwsA(isA<ChatDisabled>()),
        );
        expect(conversation()['readCount'], {'student': 0, 'tutor': 0});
      },
    );

    test('corrupt stored data surfaces without retrying', () async {
      fake.put('conversations/$_cid', {'lastSeq': 'oops'});
      await expectLater(
        store.send(_send(ChatRole.student, 1)),
        throwsA(isA<ChatDataException>()),
      );
      expect(fake.commits, 0);
      expect(fake.operations, ['beginTransaction', 'batchGet', 'rollback']);
    });

    test('no write ever uses server-side transforms', () async {
      await store.send(_send(ChatRole.student, 1));
      await store.markRead(_read(ChatRole.tutor, _msgId(ChatRole.student, 1)));
      for (final body in fake.commitBodies) {
        for (final w in (body['writes'] as List).cast<Map<String, dynamic>>()) {
          expect(w.containsKey('updateTransforms'), isFalse);
          expect(w.containsKey('currentDocument'), isTrue);
        }
      }
    });

    test('messages page oldest first with read state', () async {
      for (var i = 1; i <= 3; i++) {
        await store.send(_send(ChatRole.student, i));
      }
      await store.markRead(_read(ChatRole.tutor, _msgId(ChatRole.student, 2)));

      final latest = await store.messages(10, 1, limit: 2);
      expect(latest.messages.map((m) => m.seq), [2, 3]);
      expect(latest.messages.map(latest.conversation!.isRead), [true, false]);
      expect(latest.nextBefore, 2);

      final older = await store.messages(10, 1, beforeSeq: 2, limit: 2);
      expect(older.messages.map((m) => m.seq), [1]);
      expect(older.nextBefore, isNull);

      expect((await store.messages(10, 2)).messages, isEmpty);
    });

    test('conversations page newest first with a cursor', () async {
      final other = ChatParty(userId: 11, firebaseUid: 'uid-sipho');
      await store.send(_send(ChatRole.student, 1));
      now = now.add(const Duration(minutes: 1));
      await store.send(
        ChatSendCommand(
          student: other,
          tutor: _tutor,
          senderRole: ChatRole.student,
          clientMessageId: _client(2),
          text: 'Hi from Sipho',
          senderName: 'Sipho',
        ),
      );

      final first = await store.conversations(1, ChatRole.tutor, limit: 1);
      expect(first.conversations.single.studentUserId, 11);
      final second = await store.conversations(
        1,
        ChatRole.tutor,
        cursor: first.nextCursor,
        limit: 1,
      );
      expect(second.conversations.single.studentUserId, 10);
      final third = await store.conversations(
        1,
        ChatRole.tutor,
        cursor: second.nextCursor,
        limit: 1,
      );
      expect(third.conversations, isEmpty);
      expect(third.nextCursor, isNull);

      final mine = await store.conversations(10, ChatRole.student);
      expect(mine.conversations.map((c) => c.tutorUserId), [1]);
      expect(await store.unreadTotal(1, ChatRole.tutor), 2);
      expect(await store.unreadTotal(10, ChatRole.student), 0);
      expect(
        () => store.conversations(1, ChatRole.tutor, cursor: 'garbage'),
        throwsArgumentError,
      );
    });

    test('hasConversation is what link().hasMessages must use', () async {
      expect(await store.hasConversation(10, 1), isFalse);
      await store.send(_send(ChatRole.student, 1));
      expect(await store.hasConversation(10, 1), isTrue);
      expect(await store.hasConversation(11, 1), isFalse);
    });
  }, skip: _productionSkip);
}
