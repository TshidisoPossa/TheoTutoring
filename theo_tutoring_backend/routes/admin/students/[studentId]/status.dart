import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_students.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context, String studentId) =>
    handleStudentStatus(context, studentId);

/// PATCH /admin/students/{studentId}/status
///   {"status": "Suspended", "reason": "..."} (reason only when suspending)
///
/// Super Admin only. Suspending records who, why and when, and notifies the
/// student; leaving Suspended ends that suspension. The response is the
/// student, plus `notificationDelivered` (and a `warning`) after a
/// suspension: if Firestore could not be reached the suspension still
/// stands, and the notice is sent again when the student next opens the app.
Future<Response> handleStudentStatus(
  RequestContext context,
  String studentId, {
  AdminResolver? adminResolver,
  StudentRosterRepository? repository,
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
    requireAdminPermission(admin, 'admin.students.manage');

    final id = int.tryParse(studentId);
    final Object? body;
    try {
      body = await context.request.json();
    } on Object {
      return _bad('A JSON body is required.');
    }
    final status = body is Map ? body['status'] : null;
    if (id == null || id < 1) return _bad('Invalid student id.');
    if (status is! String || !rosterSettableStatuses.contains(status)) {
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
      role: 'student',
      profileId: id,
      status: status,
      reason: reason,
    );
    final notice = change.notice;
    final delivered = notice == null
        ? null
        : await deliverAccountNotice(notice, store, sender: noticeSender);
    final student = await (repository ?? MySqlStudentRosterRepository()).find(
      id,
    );
    return Response.json(
      body: {
        ...student,
        if (delivered != null) 'notificationDelivered': delivered,
        if (delivered == false)
          'warning':
              'The student was suspended, but the notification could not be '
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
    return _studentNotFound();
  } on StudentNotFound {
    return _studentNotFound();
  } catch (error) {
    stderr.writeln('Student status update failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The student status could not be updated.'},
    );
  }
}

Response _studentNotFound() => Response.json(
  statusCode: HttpStatus.notFound,
  body: {'error': 'Student not found.'},
);

Response _bad(String message) => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {'error': message},
);
