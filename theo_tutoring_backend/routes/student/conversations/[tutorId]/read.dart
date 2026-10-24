import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// PUT /student/conversations/{tutorUserId}/read -> marks the tutor's
// messages to this student as read.
Future<Response> onRequest(RequestContext context, String tutorId) =>
    handleChatRead(
      context,
      ChatRole.student,
      tutorId,
      ChatDependencies.production(),
    );
