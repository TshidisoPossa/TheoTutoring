import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// GET /student/conversations/unread-count -> {unreadCount} from tutors
// (the badge on the student's Chat tab).
Future<Response> onRequest(RequestContext context) => handleChatUnreadCount(
  context,
  ChatRole.student,
  ChatDependencies.production(),
);
