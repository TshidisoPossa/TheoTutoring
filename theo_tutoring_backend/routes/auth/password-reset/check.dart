import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/password_reset.dart';

Future<Response> onRequest(RequestContext context) =>
    handlePasswordResetCheck(context);
