import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_chat_moderation.dart';

// POST /admin/chat-moderation/{userId}/decision
// {"decision": "lift" | "keep", "note": "..."}: lift or keep the user's
// chat suspension; the user is told.
Future<Response> onRequest(RequestContext context, String userId) =>
    handleAdminChatModerationDecision(context, userId);
