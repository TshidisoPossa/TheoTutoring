import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAccountSuspension(context);

/// GET /account/suspension: the signed-in student's or tutor's latest
/// suspension and their appeal, for the suspended-account screen.
///
/// This is one of only two routes a suspended account may use (with
/// POST /account/suspension/appeal). Who the caller is comes only from the
/// Firebase token, so it can only ever return the caller's own suspension;
/// it never changes the account. Admins and unknown users get 404.
///
/// {"role": "student", "accountStatus": "Suspended",
///  "suspension": {"suspensionId", "reason", "suspendedAt", "status",
///                 "liftedAt", "liftReason"} | null,
///  "appeal": {"appealId", "explanation", "submittedAt", "status",
///             "decisionNote", "decidedAt"} | null,
///  "canAppeal": true, "explanationMinLength": 20,
///  "explanationMaxLength": 2000}
Future<Response> handleAccountSuspension(
  RequestContext context, {
  Future<FirebaseUser> Function(String?)? tokenVerifier,
  AccountSuspensionRepository? repository,
  AccountNoticeSender? noticeSender,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }
  try {
    final user = await (tokenVerifier ?? verifyFirebaseToken)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    final store = repository ?? MySqlAccountSuspensionRepository();
    final body = await store.suspensionFor(user.uid);
    if (body == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'No student or tutor account was found.'},
      );
    }
    // Send any notice Firestore missed when it was made (never throws)
    await retryUndeliveredNotices(user.uid, store, sender: noticeSender);
    return Response.json(body: body);
  } on AuthTokenException catch (e) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': e.message},
    );
  } catch (error) {
    stderr.writeln('Account suspension lookup failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Your account details could not be loaded.'},
    );
  }
}
