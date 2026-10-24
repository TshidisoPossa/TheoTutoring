import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// GET  /tutor/conversations/{studentUserId}/messages -> the conversation.
// POST /tutor/conversations/{studentUserId}/messages -> send a message.
Future<Response> onRequest(RequestContext context, String studentId) =>
    handleChatMessages(
      context,
      ChatRole.tutor,
      studentId,
      ChatDependencies.production(),
    );
