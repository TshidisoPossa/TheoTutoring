import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/chat_moderation.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

// The admin Chat Moderation page: every blocked chat message, with the
// sender's explanation, and the decision to lift or keep their chat
// suspension (lib/chat_moderation.dart).
//
//   GET  /admin/chat-moderation                        admin.reports.read
//   POST /admin/chat-moderation/{userId}/decision      admin.reports.resolve
//        {"decision": "lift" | "keep", "note": "..."}

/// Opens the moderation records; tests pass a fake.
typedef ChatModerationStoreFactory = Future<ChatModerationStore> Function();

/// Tells the user about the decision; tests pass a fake.
typedef ChatDecisionNotifier = Future<void> Function(ChatModerationRecord r);

Future<ChatModerationStore> _defaultStore() async =>
    FirestoreChatModerationStore(FirestoreRest.fromEnvironment());

/// GET /admin/chat-moderation: open cases first (suspended, then
/// explained), then decided ones, newest first within each.
Future<Response> handleAdminChatModerationList(
  RequestContext context, {
  AdminResolver? adminResolver,
  ChatModerationStoreFactory? storeFactory,
}) async {
  if (context.request.method != HttpMethod.get) {
    return jsonError(HttpStatus.methodNotAllowed, 'Only GET is supported.');
  }
  return _asAdmin(context, 'admin.reports.read', adminResolver, (_) async {
    final records = await (storeFactory ?? _defaultStore)().then(
      (store) => store.all(),
    );
    int rank(ChatModerationRecord r) => switch (r.status) {
      ChatModerationStatus.appealed => 0,
      ChatModerationStatus.suspended => 1,
      ChatModerationStatus.upheld => 2,
      _ => 3,
    };
    final sorted = [...records]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : b.flaggedAt.compareTo(a.flaggedAt);
      });
    return Response.json(
      body: {
        'open': records.where((r) => r.isSuspended).length,
        'cases': [for (final r in sorted) r.toAdminJson()],
      },
    );
  });
}

/// POST /admin/chat-moderation/{userId}/decision.
Future<Response> handleAdminChatModerationDecision(
  RequestContext context,
  String rawUserId, {
  AdminResolver? adminResolver,
  ChatModerationStoreFactory? storeFactory,
  ChatDecisionNotifier? notifyUser,
  DateTime Function()? clock,
}) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(HttpStatus.methodNotAllowed, 'Only POST is supported.');
  }
  final userId = int.tryParse(rawUserId);
  if (userId == null || userId <= 0) {
    return jsonError(HttpStatus.badRequest, 'Invalid user id.');
  }
  return _asAdmin(context, 'admin.reports.resolve', adminResolver, (
    admin,
  ) async {
    final bool lift;
    final String? note;
    try {
      final body = await readJsonObject(context);
      final decision = body['decision'];
      if (decision != 'lift' && decision != 'keep') {
        throw const FormatException('decision must be "lift" or "keep".');
      }
      lift = decision == 'lift';
      note = optionalString(body, 'note', maxLength: 1000);
      if (!lift && (note == null || note.trim().length < 5)) {
        throw const FormatException(
          'Please tell the user why their chat stays suspended.',
        );
      }
    } on FormatException catch (e) {
      return jsonError(HttpStatus.badRequest, e.message);
    }
    try {
      final record = await decideChatSuspension(
        await (storeFactory ?? _defaultStore)(),
        userId: userId,
        lift: lift,
        adminName: admin.name,
        note: note,
        now: (clock ?? DateTime.now)().toUtc(),
      );
      var notified = true;
      try {
        await (notifyUser ?? _notifyUser)(record);
      } catch (e) {
        notified = false;
        stderr.writeln('Could not tell user $userId about the decision: $e');
      }
      return Response.json(
        body: {'case': record.toAdminJson(), 'userNotified': notified},
      );
    } on ChatModerationException catch (e) {
      return jsonError(e.statusCode, e.message);
    }
  });
}

Future<Response> _asAdmin(
  RequestContext context,
  String permission,
  AdminResolver? adminResolver,
  Future<Response> Function(AdminIdentity admin) body,
) async {
  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, permission);
    return await body(admin);
  } on AuthTokenException catch (e) {
    return jsonError(HttpStatus.unauthorized, e.message);
  } on AdminPermissionDenied {
    return jsonError(
      HttpStatus.forbidden,
      'You do not have permission to review chat messages.',
    );
  } on AdminAccessDenied catch (e) {
    return jsonError(HttpStatus.forbidden, e.message);
  } on FirestoreException catch (e) {
    stderr.writeln('Chat moderation store failed: $e');
    return jsonError(
      HttpStatus.serviceUnavailable,
      'Chat moderation is temporarily unavailable.',
    );
  } catch (e) {
    stderr.writeln('Chat moderation request failed: $e');
    return jsonError(
      HttpStatus.internalServerError,
      'Chat moderation could not be loaded.',
    );
  }
}

/// "Your chat has been restored" / "Your chat is still suspended".
Future<void> _notifyUser(ChatModerationRecord record) async {
  final result = await (await getConnection()).execute(
    'SELECT FirebaseUid FROM `user` WHERE UserId = :id',
    {'id': record.userId},
  );
  final uid = result.rows.isEmpty
      ? null
      : result.rows.first.str('FirebaseUid');
  if (uid == null || uid.isEmpty) return;
  final restored = record.status == ChatModerationStatus.lifted;
  final note = record.decisionNote;
  await NotificationStore.fromFirebaseAdmin().create(
    uid: uid,
    type: restored
        ? NotificationType.chatRestored
        : NotificationType.chatSuspensionKept,
    title: restored ? 'Chat restored' : 'Chat still suspended',
    body: restored
        ? 'An admin reviewed your blocked message and restored your chat.'
              '${note == null ? '' : ' Note: $note'}'
        : 'An admin reviewed your blocked message and your chat stays '
              'suspended.${note == null ? '' : ' Reason: $note'}',
  );
}
