import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// POST /student/chat-appeal {"explanation": "..."}: the student's explanation
// of a blocked message, for the admin reviewing their chat suspension.
Future<Response> onRequest(RequestContext context) => handleChatAppeal(
  context,
  ChatRole.student,
  ChatDependencies.production(),
);
