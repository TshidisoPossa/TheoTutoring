import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../../../services/chat_moderation.dart';
import 'tutor_chat_models.dart';

class TutorChatConflictException implements Exception {
  const TutorChatConflictException();
}

class TutorChatUnavailableException implements Exception {
  const TutorChatUnavailableException();
}

class TutorChatService {
  TutorChatService({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken;

  final http.Client _client;
  final Future<String?> Function() _tokenProvider;
  int? _userId;
  final Map<int, TutorChatMessage> _latestMessages = {};
  static final Random _random = Random.secure();

  static Future<String?> _firebaseToken() =>
      FirebaseAuth.instance.currentUser?.getIdToken() ??
      Future<String?>.value();

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> _authorizedGet(Uri uri) async =>
      _client.get(uri, headers: await _headers());

  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response = await _authorizedGet(uri);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception(
      'GET $path failed: ${response.statusCode} ${response.body}',
    );
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('$apiBaseUrl$path'),
      headers: await _headers(),
      body: json.encode(body),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      if (response.body.isEmpty) return null;
      return json.decode(response.body);
    }
    if (response.statusCode == 409) {
      throw const TutorChatConflictException();
    }
    if (response.statusCode == 503) {
      throw const TutorChatUnavailableException();
    }
    // Contact details or abuse, or a suspended chat (moderation)
    if (ChatMessageBlockedException.from(response) case final blocked?) {
      throw blocked;
    }
    throw Exception(
      'POST $path failed: ${response.statusCode} ${response.body}',
    );
  }

  ChatModerationApi get _moderation => ChatModerationApi(
    base: '$apiBaseUrl/tutor',
    client: _client,
    headers: _headers,
  );

  /// GET /tutor/chat-status: the tutor's own chat state, and whether
  /// [studentId]'s chat is suspended.
  Future<ChatStatusResult> chatStatus({int? studentId}) =>
      _moderation.status(withUserId: studentId);

  /// POST /tutor/chat-appeal: the tutor's explanation for the admin.
  Future<ChatModerationState> appealChatSuspension(String explanation) =>
      _moderation.appeal(explanation);

  Future<void> _put(String path, Map<String, dynamic> body) async {
    final response = await _client.put(
      Uri.parse('$apiBaseUrl$path'),
      headers: await _headers(),
      body: json.encode(body),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'PUT $path failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  String _newClientMessageId() => List<int>.generate(
    16,
    (_) => _random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  /// Resolves and caches the backend UserID for the signed-in tutor.
  Future<int> _currentUserId() async {
    final cached = _userId;
    if (cached != null) return cached;
    final data = await _get('/tutor/me');
    return _userId = data['userId'] as int;
  }

  /// GET /tutor/conversations.
  Future<List<TutorChatContact>> getConversations() async {
    final data = await _get('/tutor/conversations');
    return (data as List<dynamic>)
        .map((e) => TutorChatContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Loads a page of messages, optionally older than [beforeSeq].
  Future<TutorChatMessagePage> getMessagesPage(
    int studentId, {
    int? beforeSeq,
  }) async {
    final currentId = await _currentUserId();
    final uri = Uri.parse('$apiBaseUrl/tutor/conversations/$studentId/messages')
        .replace(
          queryParameters: beforeSeq == null
              ? null
              : {'beforeSeq': beforeSeq.toString()},
        );
    final response = await _authorizedGet(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'GET ${uri.path} failed: ${response.statusCode} ${response.body}',
      );
    }
    final list = json.decode(response.body) as List<dynamic>;
    final messages = list
        .map(
          (e) =>
              TutorChatMessage.fromJson(e as Map<String, dynamic>, currentId),
        )
        .toList();
    for (final message in messages) {
      final latest = _latestMessages[studentId];
      if (latest == null || message.seq > latest.seq) {
        _latestMessages[studentId] = message;
      }
    }
    final cursor = response.headers['x-next-before-seq'];
    return TutorChatMessagePage(
      messages: messages,
      nextBeforeSeq: cursor == null ? null : int.tryParse(cursor),
    );
  }

  /// Compatibility helper returning the first page's messages.
  Future<List<TutorChatMessage>> getMessages(int studentId) async =>
      (await getMessagesPage(studentId)).messages;

  /// Sends a message with a caller-supplied or generated idempotency key.
  Future<TutorChatMessage> sendMessage({
    required int studentId,
    required String messageText,
    String? clientMessageId,
    int? bookingId,
  }) async {
    final request = TutorSendMessageRequest(
      receiverId: studentId,
      messageText: messageText,
      clientMessageId: clientMessageId ?? _newClientMessageId(),
      bookingId: bookingId,
    );
    final currentId = await _currentUserId();
    final data = await _post(
      '/tutor/conversations/$studentId/messages',
      request.toJson(),
    );
    final message = TutorChatMessage.fromJson(
      data as Map<String, dynamic>,
      currentId,
    );
    _latestMessages[studentId] = message;
    return message;
  }

  /// Marks through [upToMessageId], or the latest loaded message, as read.
  Future<void> markConversationRead(
    int studentId, {
    String? upToMessageId,
  }) async {
    final messageId = upToMessageId ?? _latestMessages[studentId]?.messageId;
    if (messageId == null) return;
    await _put(
      '/tutor/conversations/$studentId/read',
      TutorMarkReadRequest(upToMessageId: messageId).toJson(),
    );
  }

  /// GET /tutor/conversations/unread-count.
  Future<int> getTotalUnreadCount() async {
    final data = await _get('/tutor/conversations/unread-count');
    return data['unreadCount'] as int? ?? 0;
  }

  void close() => _client.close();
}
