import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// GET /tutor/chat-status?with={otherUserId}: whether this tutor's chat is
// suspended (a blocked message) and whether the other user's is.
Future<Response> onRequest(RequestContext context) => handleChatStatus(
  context,
  ChatRole.tutor,
  ChatDependencies.production(),
);
