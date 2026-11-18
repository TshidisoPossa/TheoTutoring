import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_chat_moderation.dart';

// GET /admin/chat-moderation: blocked chat messages and chat suspensions.
Future<Response> onRequest(RequestContext context) =>
    handleAdminChatModerationList(context);
