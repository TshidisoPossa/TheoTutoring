import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/chat.dart';
import 'package:theo_tutoring_backend/chat_handlers.dart';

// GET /tutor/me -> {userId, name} of the signed-in Active tutor.
Future<Response> onRequest(RequestContext context) =>
    handleChatMe(context, ChatRole.tutor, ChatDependencies.production());
