import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_tutors.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context, String tutorId) =>
    handleTutorStatus(context, tutorId);

/// PATCH /admin/tutors/{tutorId}/status
///   {"status": "Suspended", "reason": "..."} (reason only when suspending)
///
/// Super Admin only. Tutors still in review are decided on the Applications
/// page instead (409). Suspending records who, why and when, and notifies the
/// tutor; leaving Suspended ends that suspension. The response is the tutor,
/// plus `notificationDelivered` (and a `warning`) after a suspension: if
/// Firestore could not be reached the suspension still stands, and the
/// notice is sent again when the tutor next opens the app.
Future<Response> handleTutorStatus(
  RequestContext context,
  String tutorId, {
  AdminResolver? adminResolver,
  TutorRosterRepository? repository,
  AccountSuspensionRepository? suspensions,
  AccountNoticeSender? noticeSender,
}) async {
  if (context.request.method != HttpMethod.patch) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only PATCH requests are supported.'},
    );
  }
  try {
    // Authorize before looking at the body or the target.
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.tutors.manage');

    final id = int.tryParse(tutorId);
    final Object? body;
    try {
      body = await context.request.json();
    } on Object {
      return _bad('A JSON body is required.');
    }
    final status = body is Map ? body['status'] : null;
    if (id == null || id < 1) return _bad('Invalid tutor id.');
    if (status is! String || !tutorRosterSettableStatuses.contains(status)) {
      return _bad('status must be Active, Suspended or Deactivated.');
    }
    final reason = status == 'Suspended'
        ? requireText(
            (body! as Map)['reason'],
            field: 'A suspension reason',
            min: suspensionReasonMinLength,
            max: suspensionReasonMaxLength,
          )
        : null;

    final store = suspensions ?? MySqlAccountSuspensionRepository();
    final change = await store.changeStatus(
      admin: admin,
      role: 'tutor',
      profileId: id,
      status: status,
      reason: reason,
      // Activating a tutor in review would skip the application approval
      allowedFrom: tutorRosterSettableStatuses,
    );
    final notice = change.notice;
    final delivered = notice == null
        ? null
        : await deliverAccountNotice(notice, store, sender: noticeSender);
    final tutor = await (repository ?? MySqlTutorRosterRepository()).find(id);
    return Response.json(
      body: {
        ...tutor,
        if (delivered != null) 'notificationDelivered': delivered,
        if (delivered == false)
          'warning':
              'The tutor was suspended, but the notification could not be '
              'delivered right now. They will see the suspension and reason '
              'when they next open the app.',
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
  } on SuspensionConflict catch (e) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': e.message, 'code': e.code},
    );
  } on SuspensionNotFound {
    return _tutorNotFound();
  } on TutorNotFound {
    return _tutorNotFound();
  } on AccountStatusLocked catch (e) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {
        'error':
            'This tutor is ${e.status} and has not been approved yet. '
            'Review them on the Applications page.',
      },
    );
  } catch (error) {
    stderr.writeln('Tutor status update failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The tutor status could not be updated.'},
    );
  }
}

Response _tutorNotFound() => Response.json(
  statusCode: HttpStatus.notFound,
  body: {'error': 'Tutor not found.'},
);

Response _bad(String message) => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {'error': message},
);
