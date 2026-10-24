import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// GET /tutor/conversations -> the students this tutor has messages with.
Future<Response> onRequest(RequestContext context) => handleChatConversations(
  context,
  ChatRole.tutor,
  ChatDependencies.production(),
);
