import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';
import 'student_chat_models.dart';

/// The clientMessageId was already used for a different message (409).
class StudentChatConflictException implements Exception {
  const StudentChatConflictException();
}

/// Chat is switched off or temporarily unavailable (503).
class StudentChatUnavailableException implements Exception {
  const StudentChatUnavailableException();
}

class StudentChatService {
  StudentChatService({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken;

  final http.Client _client;
  final Future<String?> Function() _tokenProvider;
  static final Random _random = Random.secure();

  static Future<String?> _firebaseToken() =>
      FirebaseAuth.instance.currentUser?.getIdToken() ??
      Future<String?>.value();

  /// A new idempotency key for one message: reuse it when retrying that
  /// message, so the backend never stores it twice.
  static String newClientMessageId() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);

  Never _fail(String what, http.Response response) {
    if (response.statusCode == 503) {
      throw const StudentChatUnavailableException();
    }
    throw Exception('$what failed: ${response.statusCode}');
  }

  /// GET /student/conversations.
  Future<List<StudentChatContact>> getConversations() async {
    final response = await _client
        .get(_uri('/student/conversations'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      _fail('Loading conversations', response);
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map(
          (item) => StudentChatContact.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  /// GET /student/conversations/{tutorId}/messages[?beforeSeq=]: newest
  /// page, or the page older than [beforeSeq], oldest first.
  Future<StudentChatMessagePage> getMessagesPage(
    int tutorId, {
    int? beforeSeq,
  }) async {
    final response = await _client
        .get(
          _uri(
            '/student/conversations/$tutorId/messages',
            beforeSeq == null ? null : {'beforeSeq': '$beforeSeq'},
          ),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _fail('Loading messages', response);
    final data = jsonDecode(response.body) as List<dynamic>;
    final next = response.headers['x-next-before-seq'];
    return StudentChatMessagePage(
      messages: [
        for (final item in data)
          StudentChatMessage.fromJson(item as Map<String, dynamic>),
      ],
      nextBeforeSeq: next == null ? null : int.tryParse(next),
    );
  }

  /// POST /student/conversations/{tutorId}/messages. Retrying with the same
  /// [clientMessageId] returns the stored message instead of a duplicate.
  Future<StudentChatMessage> sendMessage({
    required int tutorId,
    required String messageText,
    required String clientMessageId,
  }) async {
    final response = await _client
        .post(
          _uri('/student/conversations/$tutorId/messages'),
          headers: await _headers(),
          body: jsonEncode({
            'clientMessageId': clientMessageId,
            'messageText': messageText,
            'receiverId': tutorId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 409) {
      throw const StudentChatConflictException();
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      _fail('Sending the message', response);
    }
    return StudentChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// PUT /student/conversations/{tutorId}/read: marks the tutor's messages
  /// read up to and including [upToMessageId].
  Future<void> markRead(int tutorId, String upToMessageId) async {
    final response = await _client
        .put(
          _uri('/student/conversations/$tutorId/read'),
          headers: await _headers(),
          body: jsonEncode({
            'tutorId': tutorId,
            'upToMessageId': upToMessageId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) _fail('Marking messages read', response);
  }
}
