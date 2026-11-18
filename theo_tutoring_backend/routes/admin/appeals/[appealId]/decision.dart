import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context, String appealId) =>
    handleAppealDecision(context, appealId);

/// POST /admin/appeals/{appealId}/decision
///   {"decision": "approve" | "reject", "note": "..."}
///
/// Approve lifts the suspension and restores the account's previous status;
/// reject keeps it suspended (the rejection is final for that suspension).
/// A rejection needs a note for the user; an approval's note is optional.
/// The administrator needs the manage permission for that kind of account.
/// A decided appeal cannot be decided again (409 `appeal_already_decided`).
///
/// The decision is saved first; then the user is notified. The response is
/// the decided appeal plus `notificationDelivered` (and a `warning` when it
/// was not: the user still sees the decision on their suspension screen, and
/// the notice is retried when they next open it).
Future<Response> handleAppealDecision(
  RequestContext context,
  String appealId, {
  AdminResolver? adminResolver,
  AccountSuspensionRepository? repository,
  AccountNoticeSender? noticeSender,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only POST requests are supported.'},
    );
  }
  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    final roles = appealRolesFor(admin);
    if (roles.isEmpty) {
      throw const AdminPermissionDenied('admin.students.manage');
    }

    final id = int.tryParse(appealId);
    if (id == null || id < 1) return _bad('Invalid appeal id.');
    final Object? body;
    try {
      body = await context.request.json();
    } on Object {
      return _bad('A JSON body is required.');
    }
    final decision = body is Map ? body['decision'] : null;
    if (decision != 'approve' && decision != 'reject') {
      return _bad('decision must be approve or reject.');
    }
    final approve = decision == 'approve';
    final rawNote = (body! as Map)['note'];
    final noteGiven = rawNote is String && rawNote.trim().isNotEmpty;
    final String? note;
    if (approve && !noteGiven) {
      note = null;
    } else {
      note = requireText(
        rawNote,
        field: approve ? 'The note' : 'A reason for the rejection',
        min: appealDecisionNoteMinLength,
        max: appealDecisionNoteMaxLength,
      );
    }

    final store = repository ?? MySqlAccountSuspensionRepository();
    final result = await store.decideAppeal(
      admin: admin,
      appealId: id,
      approve: approve,
      note: note,
      roles: roles,
    );
    final delivered = await deliverAccountNotice(
      result.notice,
      store,
      sender: noticeSender,
    );
    return Response.json(
      body: {
        'appeal': result.appeal,
        'notificationDelivered': delivered,
        if (!delivered)
          'warning':
              'The decision was saved, but the notification could not be '
              'delivered right now. The user will see the decision when they '
              'next open the app.',
      },
    );
  } on AuthTokenException catch (e) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': e.message},
    );
  } on AdminAccessDenied catch (e) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': e.message},
    );
  } on SuspensionValidation catch (e) {
    return _bad(e.message);
  } on SuspensionNotFound catch (e) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': e.message},
    );
  } on SuspensionConflict catch (e) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': e.message, 'code': e.code},
    );
  } catch (error) {
    stderr.writeln('Appeal decision failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The decision could not be saved.'},
    );
  }
}

Response _bad(String message) => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {'error': message},
);
