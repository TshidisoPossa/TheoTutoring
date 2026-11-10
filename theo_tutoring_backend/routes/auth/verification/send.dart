import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/email_verification.dart';

// POST /auth/verification/send  ->  emails the signed-in user a new 6-digit
// code (see lib/email_verification.dart).
Future<Response> onRequest(RequestContext context) =>
    handleSendVerificationCode(context);
