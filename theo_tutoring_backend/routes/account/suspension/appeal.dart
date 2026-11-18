import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleSubmitAppeal(context);

/// POST /account/suspension/appeal {"explanation": "..."}
///
/// The signed-in, suspended student or tutor appeals their active
/// suspension. The account is identified only by the Firebase token; the
/// body may contain nothing but the explanation. One appeal per suspension
/// (409 `appeal_exists`); an account that is not suspended gets 409
/// `not_suspended`. Sending an appeal never changes the account: only an
/// administrator's decision can lift the suspension.
Future<Response> handleSubmitAppeal(
  RequestContext context, {
  Future<FirebaseUser> Function(String?)? tokenVerifier,
  AccountSuspensionRepository? repository,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only POST requests are supported.'},
    );
  }
  try {
    // Who is asking, before reading anything they sent
    final user = await (tokenVerifier ?? verifyFirebaseToken)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    final Object? body;
    try {
      body = await context.request.json();
    } on Object {
      return _bad('A JSON body is required.');
    }
    if (body is! Map || body.keys.any((k) => k != 'explanation')) {
      return _bad('Send only your explanation.');
    }
    final explanation = requireText(
      body['explanation'],
      field: 'Your explanation',
      min: appealExplanationMinLength,
      max: appealExplanationMaxLength,
    );
    final appeal = await (repository ?? MySqlAccountSuspensionRepository())
        .submitAppeal(user.uid, explanation);
    return Response.json(statusCode: HttpStatus.created, body: appeal);
  } on AuthTokenException catch (e) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': e.message},
    );
  } on SuspensionValidation catch (e) {
    return _bad(e.message);
  } on SuspensionNotFound {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'No student or tutor account was found.'},
    );
  } on SuspensionConflict catch (e) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': e.message, 'code': e.code},
    );
  } catch (error) {
    stderr.writeln('Appeal submission failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Your appeal could not be sent. Please try again.'},
    );
  }
}

Response _bad(String message) => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {'error': message},
);
