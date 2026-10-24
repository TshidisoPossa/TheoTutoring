import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// GET /tutor/conversations/unread-count -> {unreadCount} from students.
Future<Response> onRequest(RequestContext context) => handleChatUnreadCount(
  context,
  ChatRole.tutor,
  ChatDependencies.production(),
);
