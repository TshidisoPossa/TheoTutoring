import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/email_verification.dart';

// POST /auth/verification/verify {"code": "123456"}  ->  marks the signed-in
// user's email verified in Firebase (see lib/email_verification.dart).
Future<Response> onRequest(RequestContext context) =>
    handleVerifyCode(context);
