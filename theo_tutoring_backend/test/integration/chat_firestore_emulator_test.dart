import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_audit.dart';
import 'package:theo_tutoring_backend/chat_outbox.dart';
import 'package:theo_tutoring_backend/chat_store.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Chat against the real Firestore emulator. Run from theo_tutoring_backend:
//
//   firebase emulators:exec --only firestore --project demo-theotutoring
//     "dart test test/integration/chat_firestore_emulator_test.dart"
//
// with THEO_REQUIRE_FIRESTORE_EMULATOR=1 set when a skip must count as a
// failure (CI). Without emulator settings the tests are skipped; with
// invalid settings, or any project other than demo-theotutoring, they fail.
// Only the emulator is ever contacted: clients are built from the resolved
// emulator endpoint (and FirestoreRest refuses anything else in emulator
// mode); MySQL is replaced by in-memory fakes and FirebaseAdmin is never
// used.

const _project = 'demo-theotutoring';
const _requireVariable = 'THEO_REQUIRE_FIRESTORE_EMULATOR';

/// The emulator to use, or why the tests must skip or fail.
final ({FirestoreEndpoint? endpoint, String? skip, String? failure}) _setup =
    () {
      final required = Platform.environment[_requireVariable] == '1';
      final FirestoreEndpoint endpoint;
      try {
        endpoint = FirestoreEndpoint.resolve();
      } on FirestoreEndpointException catch (e) {
        return (endpoint: null, skip: null, failure: e.message);
      }
      if (!endpoint.isEmulator) {
        const reason =
            'Firestore emulator settings are absent '
            '($firestoreEmulatorHostVariable / '
            '$firestoreEmulatorProjectVariable).';
        return required
            ? (
                endpoint: null,
                skip: null,
                failure: '$reason $_requireVariable=1.',
              )
            : (endpoint: null, skip: reason, failure: null);
      }
      if (endpoint.projectId != _project) {
        return (
          endpoint: null,
          skip: null,
          failure:
              '$firestoreEmulatorProjectVariable must be $_project for these '
              'tests.',
        );
      }
      return (endpoint: endpoint, skip: null, failure: null);
    }();

FirestoreEndpoint get _emulator => _setup.endpoint!;

FirestoreRest _rest({int maxAttempts = FirestoreRest.defaultMaxAttempts}) =>
    FirestoreRest(
      projectId: _emulator.projectId!,
      accessToken: () async => _emulator.accessToken!,
      baseUri: _emulator.baseUri,
      maxAttempts: maxAttempts,
    );

/// Deletes every document in the demo project (emulator-only endpoint).
Future<void> _wipe() async {
  final base = _emulator.baseUri;
  expect(base.host, '127.0.0.1', reason: 'never wipe anything else');
  final response = await http.delete(
    base.replace(
      path: '/emulator/v1/projects/$_project/databases/(default)/documents',
    ),
  );
  expect(response.statusCode, 200, reason: 'emulator wipe failed');
}

Future<void> _setChat({required bool enabled}) => _rest().commit([
  FirestoreWrite.update(chatConfigPath, {'enabled': enabled}),
]);

class _FakeAudit implements ChatAuditSink {
  final rows = <String, bool>{};

  @override
  Future<void> recordMessage(ChatAuditMessage m) async =>
      rows[m.firestoreMessageId] =
          (rows[m.firestoreMessageId] ?? false) || m.isRead;

  @override
  Future<Set<String>> presentIds(List<String> ids) async =>
      ids.where(rows.containsKey).toSet();

  @override
  Future<int> markRead(List<String> ids) async {
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

final _student = ChatParty(userId: 10, firebaseUid: 'uid-lerato');
final _tutor = ChatParty(userId: 1, firebaseUid: 'uid-theo');
const _cid = 's10_t1';

String _client(String name) => 'client-$name-'.padRight(20, 'x');

ChatSendCommand _send(ChatRole from, String name, {String text = 'Hello'}) =>
    ChatSendCommand(
      student: _student,
      tutor: _tutor,
      senderRole: from,
      clientMessageId: _client(name),
      text: text,
      senderName: from == ChatRole.student ? 'Lerato' : 'Theo',
    );

ChatReadCommand _readUpTo(StoredChatMessage m, ChatRole by) => ChatReadCommand(
  studentUserId: 10,
  tutorUserId: 1,
  readerRole: by,
  upToMessageId: m.messageId,
);

void main() {
  if (_setup.failure case final failure?) {
    test('Firestore emulator settings', () => fail(failure));
    return;
  }

  group(
    'chat on the Firestore emulator',
    () {
      late FirestoreChatStore store;

      setUp(() async {
        await _wipe();
        await _setChat(enabled: true);
        store = FirestoreChatStore(_rest());
      });

      test('targets only the local emulator with the emulator token', () {
        expect(_emulator.baseUri, Uri.http('127.0.0.1:8085'));
        expect(_emulator.accessToken, 'owner');
        expect(_emulator.projectId, _project);
      });

      test('send, replay and conflicting duplicate', () async {
        final first = await store.send(_send(ChatRole.student, 'a'));
        final replay = await store.send(_send(ChatRole.student, 'a'));
        expect(first.created, isTrue);
        expect(replay.created, isFalse);
        expect(replay.message.messageId, first.message.messageId);
        await expectLater(
          store.send(_send(ChatRole.student, 'a', text: 'Different')),
          throwsA(isA<ChatDuplicateConflict>()),
        );
        final page = await store.messages(10, 1);
        expect(page.messages, hasLength(1));
      });

      // A realistic burst: both people typing at once, in two waves. Every
      // send must succeed (the retry jitter spreads contending commits).
      test('concurrent sends all succeed with unique sequence numbers and '
          'consistent counters', () async {
        final results = <ChatSendResult>[];
        for (final wave in [
          [ChatRole.student, ChatRole.tutor, ChatRole.student],
          [ChatRole.tutor, ChatRole.student, ChatRole.tutor],
        ]) {
          results.addAll(
            await Future.wait([
              for (final (i, role) in wave.indexed)
                store.send(_send(role, 'w${results.length}-$i')),
            ]),
          );
        }
        expect(results.every((r) => r.created), isTrue);
        expect(results.map((r) => r.message.seq).toSet(), {1, 2, 3, 4, 5, 6});

        final state = (await store.conversation(10, 1))!;
        expect(state.lastSeq, 6);
        expect(state.sent, (student: 3, tutor: 3));
        expect(state.unread, (student: 3, tutor: 3));
        final page = await store.messages(10, 1);
        expect(page.messages.map((m) => m.seq), [1, 2, 3, 4, 5, 6]);
        for (final m in page.messages) {
          expect(m.counts.student + m.counts.tutor, m.seq, reason: m.messageId);
        }
        for (final role in ChatRole.values) {
          int countOf(StoredChatMessage m) =>
              role == ChatRole.student ? m.counts.student : m.counts.tutor;
          expect(
            [
              for (final m in page.messages)
                if (m.senderRole == role) countOf(m),
            ],
            [1, 2, 3],
          );
        }
      });

      test(
        'the same clientMessageId sent concurrently stores one message',
        () async {
          final outcomes = await Future.wait([
            for (var i = 0; i < 5; i++)
              store
                  .send(_send(ChatRole.student, 'same'))
                  .then<Object>((r) => r)
                  .catchError((Object e) => e),
          ]);
          final sent = outcomes.whereType<ChatSendResult>().toList();
          expect(sent.where((r) => r.created), hasLength(1));
          expect(sent.map((r) => r.message.messageId).toSet(), hasLength(1));
          // Anything else may only be giving up under contention.
          expect(
            outcomes.where((o) => o is! ChatSendResult),
            everyElement(isA<FirestoreRetryExhausted>()),
          );
          expect((await store.messages(10, 1)).messages, hasLength(1));
        },
      );

      test('mark-read racing new messages keeps counters consistent', () async {
        final first = (await store.send(_send(ChatRole.student, 'r0'))).message;
        await Future.wait([
          store.markRead(_readUpTo(first, ChatRole.tutor)),
          for (var i = 1; i <= 4; i++)
            store.send(_send(ChatRole.student, 'r$i')),
        ]);
        final state = (await store.conversation(10, 1))!;
        expect(state.sent.student, 5);
        expect(state.readCount.tutor, 1);
        expect(state.unread.tutor, 4);

        // Never backwards.
        final again = await store.markRead(_readUpTo(first, ChatRole.tutor));
        expect(again.markedRead, 0);
      });

      test('kill switch: missing or disabled config refuses writes', () async {
        final sent = await store.send(_send(ChatRole.student, 'k0'));
        await _setChat(enabled: false);
        await expectLater(
          store.send(_send(ChatRole.student, 'k1')),
          throwsA(isA<ChatDisabled>()),
        );
        await expectLater(
          store.markRead(_readUpTo(sent.message, ChatRole.tutor)),
          throwsA(isA<ChatDisabled>()),
        );
        await _rest().delete(chatConfigPath);
        await expectLater(
          store.send(_send(ChatRole.student, 'k2')),
          throwsA(isA<ChatDisabled>()),
        );
        expect((await store.messages(10, 1)).messages, hasLength(1));

        await _setChat(enabled: true);
        expect(
          (await store.send(_send(ChatRole.student, 'k3'))).created,
          isTrue,
        );
      });

      test(
        'kill switch racing sends: nothing commits once it is off',
        () async {
          final racing = Future.wait([
            for (var i = 0; i < 6; i++)
              store
                  .send(_send(ChatRole.student, 'z$i'))
                  .then<Object>((r) => r)
                  .catchError((Object e) => e),
          ]);
          await _setChat(enabled: false);
          final outcomes = await racing;
          expect(
            outcomes.where((o) => o is! ChatSendResult),
            everyElement(
              anyOf(isA<ChatDisabled>(), isA<FirestoreRetryExhausted>()),
            ),
          );
          final before = (await store.messages(10, 1)).messages.length;
          await expectLater(
            store.send(_send(ChatRole.student, 'after')),
            throwsA(isA<ChatDisabled>()),
          );
          expect((await store.messages(10, 1)).messages, hasLength(before));
        },
      );

      test(
        'outbox: audit rows and one notification, then entries are gone',
        () async {
          final audit = _FakeAudit();
          final worker = ChatOutboxWorker(
            rest: _rest(),
            audit: audit,
            notifications: NotificationStore(
              projectId: _emulator.projectId!,
              accessToken: () async => _emulator.accessToken!,
              baseUri: _emulator.baseUri,
            ),
          );
          final a = (await store.send(_send(ChatRole.student, 'o1'))).message;
          final b = (await store.send(_send(ChatRole.student, 'o2'))).message;
          await worker.afterSend(a);
          await worker.afterSend(b);
          await worker.afterSend(a); // repeat: harmless
          await store.markRead(_readUpTo(b, ChatRole.tutor));
          await worker.afterRead(_cid, ChatRole.tutor);

          expect(audit.rows, {
            '$_cid/${a.messageId}': true,
            '$_cid/${b.messageId}': true,
          });
          final outbox = await _rest().runQuery({
            'from': [
              {'collectionId': 'chatOutbox'},
            ],
          });
          expect(outbox, isEmpty);
          final notification = await _rest().get(
            'notifications/uid-theo/items/${chatNotificationId(_cid, 1)}',
          );
          expect(notification, isNotNull);
          expect(
            await _rest().get(
              'notifications/uid-theo/items/${chatNotificationId(_cid, 2)}',
            ),
            isNull,
            reason: 'one notification per unread burst',
          );
        },
      );

      test('security rules refuse direct, unauthenticated access', () async {
        final url = _emulator.baseUri.replace(
          path:
              '/v1/projects/$_project/databases/(default)/documents/'
              '$chatConfigPath',
        );
        final response = await http.get(url); // no owner token
        expect(response.statusCode, 403, reason: response.body);
      });
    },
    skip: _setup.skip ?? false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
