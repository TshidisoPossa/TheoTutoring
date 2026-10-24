import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// PUT /tutor/conversations/{studentUserId}/read -> marks the student's
// messages to this tutor as read.
Future<Response> onRequest(RequestContext context, String studentId) =>
    handleChatRead(
      context,
      ChatRole.tutor,
      studentId,
      ChatDependencies.production(),
    );
