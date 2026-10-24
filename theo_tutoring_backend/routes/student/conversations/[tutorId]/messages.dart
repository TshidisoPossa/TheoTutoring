import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// GET  /student/conversations/{tutorUserId}/messages -> the conversation.
// POST /student/conversations/{tutorUserId}/messages -> send a message.
Future<Response> onRequest(RequestContext context, String tutorId) =>
    handleChatMessages(
      context,
      ChatRole.student,
      tutorId,
      ChatDependencies.production(),
    );
