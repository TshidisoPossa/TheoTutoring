import 'dart:io';

import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_audit.dart';
import 'package:theo_tutoring_backend/chat_store.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Works through chatOutbox (written by FirestoreChatStore in the same
// transaction as each change):
//   m_{cid}_{messageId}  record the message in the MySQL audit table
//   r_{cid}_{role}       mark audit rows read up to `target`
//   n_{cid}_{seq}        create the "New message" notification
//
// Everything is safe to repeat. An entry is deleted only if it still has
// the update time this worker read (so a newer change is never lost), and
// only after its MySQL or notification write succeeded. firstPendingAt is
// never written. Called best-effort after each send/mark-read, and by
// runOnce for anything left behind.

/// Entries older than this are picked up by [ChatOutboxWorker.runOnce]
/// (younger ones are normally handled by the request that wrote them).
const chatOutboxMinAge = Duration(minutes: 2);

/// What one [ChatOutboxWorker.process] call did.
enum ChatOutboxOutcome {
  /// Done and deleted (or already gone).
  done,

  /// Left for later: a needed audit row does not exist yet, or the entry
  /// changed while being processed.
  waiting,
}

/// Totals for one [ChatOutboxWorker.runOnce].
class ChatOutboxReport {
  /// Creates a report.
  const ChatOutboxReport({
    required this.done,
    required this.waiting,
    required this.failed,
  });

  /// Entries finished.
  final int done;

  /// Entries left for a later run.
  final int waiting;

  /// Entries whose processing threw (left in place).
  final int failed;
}

/// Processes chat outbox entries.
class ChatOutboxWorker {
  /// Creates a worker. Tests pass their own [clock].
  ChatOutboxWorker({
    required FirestoreRest rest,
    required ChatAuditSink audit,
    required NotificationStore notifications,
    DateTime Function()? clock,
  }) : _rest = rest,
       _audit = audit,
       _notifications = notifications,
       _clock = clock ?? DateTime.now;

  final FirestoreRest _rest;
  final ChatAuditSink _audit;
  final NotificationStore _notifications;
  final DateTime Function() _clock;

  /// Most attempts to advance one read entry that keeps changing.
  static const _readAttempts = 5;

  /// Processes up to [limit] (at most [maxChatAuditBatch]) entries older
  /// than [chatOutboxMinAge], oldest first. A failing entry is left in
  /// place and does not stop the others.
  Future<ChatOutboxReport> runOnce({int limit = maxChatAuditBatch}) async {
    if (limit < 1 || limit > maxChatAuditBatch) {
      throw ArgumentError.value(limit, 'limit');
    }
    final cutoff = _clock().toUtc().subtract(chatOutboxMinAge);
    final entries = await _rest.runQuery({
      'from': [
        {'collectionId': 'chatOutbox'},
      ],
      'where': {
        'fieldFilter': {
          'field': {'fieldPath': 'firstPendingAt'},
          'op': 'LESS_THAN',
          'value': encodeFirestoreValue(cutoff),
        },
      },
      'orderBy': [
        {
          'field': {'fieldPath': 'firstPendingAt'},
          'direction': 'ASCENDING',
        },
      ],
      'limit': limit,
    });
    var done = 0;
    var waiting = 0;
    var failed = 0;
    for (final entry in entries) {
      try {
        switch (await process(entry)) {
          case ChatOutboxOutcome.done:
            done++;
          case ChatOutboxOutcome.waiting:
            waiting++;
        }
      } on Object catch (e) {
        failed++;
        stderr.writeln('Chat outbox ${entry.path} failed: ${e.runtimeType}');
      }
    }
    return ChatOutboxReport(done: done, waiting: waiting, failed: failed);
  }

  /// Processes the entries a send just wrote (best effort: never throws).
  Future<void> afterSend(StoredChatMessage message) => _quietly([
    'chatOutbox/m_${message.conversationId}_${message.messageId}',
    'chatOutbox/n_${message.conversationId}_${message.seq}',
  ]);

  /// Processes the entry a mark-read just wrote (best effort: never
  /// throws).
  Future<void> afterRead(String conversationId, ChatRole reader) =>
      _quietly(['chatOutbox/r_${conversationId}_${reader.value}']);

  Future<void> _quietly(List<String> paths) async {
    for (final path in paths) {
      try {
        final entry = await _rest.get(path);
        if (entry != null) await process(entry);
      } on Object catch (e) {
        // The entry stays; runOnce retries it later.
        stderr.writeln('Chat outbox $path deferred: ${e.runtimeType}');
      }
    }
  }

  /// Processes one entry.
  Future<ChatOutboxOutcome> process(FirestoreDocument entry) {
    final id = entry.path.split('/').last;
    if (!entry.path.startsWith('chatOutbox/')) {
      throw ArgumentError.value(entry.path, 'entry', 'Not an outbox entry');
    }
    return switch (entry.fields['kind']) {
      'message' when id.startsWith('m_') => _message(entry),
      'read' when id.startsWith('r_') => _read(entry),
      'notify' when id.startsWith('n_') => _notify(entry),
      _ => throw ChatDataException('Outbox entry ${entry.path} is malformed.'),
    };
  }

  // ─── Message audit ────────────────────────────────────────────────────

  Future<ChatOutboxOutcome> _message(FirestoreDocument entry) async {
    final cid = _string(entry, 'conversationId');
    final messageId = _string(entry, 'messageId');
    final docs = await _rest.batchGet([
      'conversations/$cid',
      'conversations/$cid/messages/$messageId',
    ]);
    final conversation = docs['conversations/$cid'];
    final messageDoc = docs['conversations/$cid/messages/$messageId'];
    if (conversation == null || messageDoc == null) {
      throw ChatDataException('Outbox ${entry.path} points at nothing.');
    }
    final state = ChatConversationState.fromDocument(conversation);
    final message = StoredChatMessage.fromDocument(messageDoc);
    // MySQL first: the entry is only deleted once the row exists.
    await _audit.recordMessage(
      ChatAuditMessage(
        firestoreMessageId: '$cid/$messageId',
        senderId: message.senderId,
        receiverId: message.receiverId,
        messageText: message.text,
        sentAt: message.sentAt,
        isRead: state.isRead(message),
        bookingId: message.bookingId,
      ),
    );
    return _deleteIfUnchanged(entry);
  }

  // ─── Read audit ───────────────────────────────────────────────────────

  Future<ChatOutboxOutcome> _read(FirestoreDocument first) async {
    var entry = first;
    for (var attempt = 0; attempt < _readAttempts; attempt++) {
      final cid = _string(entry, 'conversationId');
      final reader = _role(entry, 'readerRole');
      final author = reader.other; // whose messages were read
      final target = _int(entry, 'target');
      final doneThrough = _int(entry, 'doneThrough');
      if (doneThrough >= target) return _deleteIfUnchanged(entry);

      // The author's messages with counts.author in (doneThrough, target],
      // in order: each has a different count, so pages never overlap.
      final countField = 'counts.${author.value}';
      final page = [
        for (final doc in await _rest.runQuery({
          'from': [
            {'collectionId': 'messages'},
          ],
          'where': {
            'compositeFilter': {
              'op': 'AND',
              'filters': [
                _filter('senderRole', 'EQUAL', author.value),
                _filter(countField, 'GREATER_THAN', doneThrough),
                _filter(countField, 'LESS_THAN_OR_EQUAL', target),
              ],
            },
          },
          'orderBy': [
            {
              'field': {'fieldPath': countField},
              'direction': 'ASCENDING',
            },
          ],
          'limit': maxChatAuditBatch,
        }, parent: 'conversations/$cid'))
          StoredChatMessage.fromDocument(doc),
      ];
      if (page.any((m) => m.senderRole != author || m.conversationId != cid)) {
        throw ChatDataException('Read audit query for $cid is wrong.');
      }

      // Only rows that exist can be marked; stop at the first missing one
      // (its message entry will create it, then this entry continues).
      final ids = [for (final m in page) '$cid/${m.messageId}'];
      final present = await _audit.presentIds(ids);
      var reached = doneThrough;
      final ready = <String>[];
      for (final m in page) {
        if (!present.contains('$cid/${m.messageId}')) break;
        ready.add('$cid/${m.messageId}');
        reached = _countOf(m, author);
      }
      final complete =
          page.length < maxChatAuditBatch && ready.length == ids.length;
      if (complete) reached = target;
      if (ready.isNotEmpty) await _audit.markRead(ready);

      if (reached == doneThrough) return ChatOutboxOutcome.waiting;
      // Record progress only if nobody changed the entry meanwhile.
      try {
        final result = await _rest.commit([
          FirestoreWrite.update(
            entry.path,
            {'doneThrough': reached},
            updateMask: const ['doneThrough'],
            precondition: FirestorePrecondition.updateTime(entry.updateTime),
          ),
        ]);
        entry = FirestoreDocument(
          path: entry.path,
          fields: {...entry.fields, 'doneThrough': reached},
          updateTime: result.updateTimes.single ?? entry.updateTime,
        );
      } on FirestoreConflict {
        final fresh = await _rest.get(entry.path);
        if (fresh == null) return ChatOutboxOutcome.done;
        entry = fresh; // redo from its state; markRead is safe to repeat
      } on FirestoreNotFound {
        return ChatOutboxOutcome.done;
      }
      if (!complete && ready.length < ids.length) {
        return ChatOutboxOutcome.waiting;
      }
    }
    return ChatOutboxOutcome.waiting;
  }

  // ─── Notifications ────────────────────────────────────────────────────

  Future<ChatOutboxOutcome> _notify(FirestoreDocument entry) async {
    final cid = _string(entry, 'conversationId');
    final messageId = _string(entry, 'messageId');
    final seq = _int(entry, 'seq');
    final docs = await _rest.batchGet([
      'conversations/$cid',
      'conversations/$cid/messages/$messageId',
    ]);
    final conversation = docs['conversations/$cid'];
    final messageDoc = docs['conversations/$cid/messages/$messageId'];
    if (conversation == null || messageDoc == null) {
      throw ChatDataException('Outbox ${entry.path} points at nothing.');
    }
    final message = StoredChatMessage.fromDocument(messageDoc);
    if (message.seq != seq) {
      throw ChatDataException('Outbox ${entry.path} does not match.');
    }
    // Already read: nothing to tell the receiver.
    if (!ChatConversationState.fromDocument(conversation).isRead(message)) {
      await _notifications.createWithId(
        uid: _string(entry, 'receiverUid'),
        id: chatNotificationId(cid, seq),
        type: NotificationType.newMessage,
        title: 'New message',
        body: 'You have a new message from ${_string(entry, 'senderName')}.',
      );
    }
    return _deleteIfUnchanged(entry);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// Deletes [entry] only if it still has the update time read.
  /// The condition travels in a commit's body: the Firestore emulator
  /// ignores update-time conditions sent as DELETE query parameters.
  Future<ChatOutboxOutcome> _deleteIfUnchanged(FirestoreDocument entry) async {
    try {
      await _rest.commit([
        FirestoreWrite.delete(
          entry.path,
          precondition: FirestorePrecondition.updateTime(entry.updateTime),
        ),
      ]);
      return ChatOutboxOutcome.done;
    } on FirestoreNotFound {
      return ChatOutboxOutcome.done; // another worker finished it
    } on FirestoreConflict {
      // Changed (e.g. a newer read target) or already gone.
      return await _rest.get(entry.path) == null
          ? ChatOutboxOutcome.done
          : ChatOutboxOutcome.waiting;
    }
  }

  static Map<String, Object?> _filter(String field, String op, Object value) =>
      {
        'fieldFilter': {
          'field': {'fieldPath': field},
          'op': op,
          'value': encodeFirestoreValue(value),
        },
      };

  static int _countOf(StoredChatMessage m, ChatRole role) =>
      role == ChatRole.student ? m.counts.student : m.counts.tutor;

  static String _string(FirestoreDocument entry, String key) {
    final value = entry.fields[key];
    if (value is! String || value.isEmpty) {
      throw ChatDataException('Outbox ${entry.path} has no $key.');
    }
    return value;
  }

  static int _int(FirestoreDocument entry, String key) {
    final value = entry.fields[key];
    if (value is! int || value < 0) {
      throw ChatDataException('Outbox ${entry.path} has no $key.');
    }
    return value;
  }

  static ChatRole _role(FirestoreDocument entry, String key) =>
      switch (entry.fields[key]) {
        'student' => ChatRole.student,
        'tutor' => ChatRole.tutor,
        _ => throw ChatDataException('Outbox ${entry.path} has no $key.'),
      };
}

/// Notification id for message [seq] of conversation [cid]: the same on
/// every retry, so a notification is created at most once.
String chatNotificationId(String cid, int seq) => 'msg-$cid-$seq';
