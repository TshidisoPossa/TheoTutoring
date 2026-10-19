// lib/Pages/Tutor/Services/tutor_chat_service.dart

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'tutor_chat_models.dart';

class TutorChatService {
  static const String _baseUrl = 'http://localhost:8080';

  // ─── Auth header ────────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers() async {
    final token =
        await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ─── Low-level helpers ───────────────────────────────────────────────────────

  Future<dynamic> _get(String path) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception(
        'GET $path failed: ${response.statusCode} ${response.body}');
  }

  Future<dynamic> _post(
      String path, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
      body: json.encode(body),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      if (response.body.isEmpty) return null;
      return json.decode(response.body);
    }
    throw Exception(
        'POST $path failed: ${response.statusCode} ${response.body}');
  }

  Future<void> _put(
      String path, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
      body: json.encode(body),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'PUT $path failed: ${response.statusCode} ${response.body}');
    }
  }

  // ─── Current user ID helper ──────────────────────────────────────────────────

  /// Returns the backend UserID for the signed-in tutor.
  /// The backend resolves the Firebase UID from the JWT and returns the
  /// MySQL UserID; cache it locally if you call this frequently.
  Future<int> _currentUserId() async {
    final data = await _get('/tutor/me');
    return data['userId'] as int;
  }

  // ─── Conversation list ───────────────────────────────────────────────────────

  /// GET /tutor/conversations
  ///
  /// Returns the list of students the signed-in tutor has active
  /// conversations with, ordered by most recent message.
  Future<List<TutorChatContact>> getConversations() async {
    final data = await _get('/tutor/conversations');
    final list = data as List<dynamic>;
    return list
        .map((e) =>
            TutorChatContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Message history ─────────────────────────────────────────────────────────

  /// GET /tutor/conversations/{studentId}/messages
  ///
  /// Returns all messages exchanged between the signed-in tutor and
  /// [studentId], newest last (chronological order).
  ///
  /// Firestore is the live source of truth; the backend may return
  /// messages mirrored from its MySQL Messaging audit table.
  Future<List<TutorChatMessage>> getMessages(int studentId) async {
    final currentId = await _currentUserId();
    final data =
        await _get('/tutor/conversations/$studentId/messages');
    final list = data as List<dynamic>;
    return list
        .map((e) => TutorChatMessage.fromJson(
            e as Map<String, dynamic>, currentId))
        .toList();
  }

  // ─── Send a message ──────────────────────────────────────────────────────────

  /// POST /tutor/conversations/{studentId}/messages
  ///
  /// Sends [messageText] to [studentId].  Optionally attach a [bookingId]
  /// to link the message to a specific session (used for session-card
  /// messages).
  ///
  /// Returns the saved [TutorChatMessage] (with its assigned MessageID).
  Future<TutorChatMessage> sendMessage({
    required int studentId,
    required String messageText,
    int? bookingId,
  }) async {
    final request = TutorSendMessageRequest(
      receiverId: studentId,
      bookingId: bookingId,
      messageText: messageText,
    );
    final currentId = await _currentUserId();
    final data = await _post(
      '/tutor/conversations/$studentId/messages',
      request.toJson(),
    );
    return TutorChatMessage.fromJson(
        data as Map<String, dynamic>, currentId);
  }

  // ─── Mark messages as read ───────────────────────────────────────────────────

  /// PUT /tutor/conversations/{studentId}/read
  ///
  /// Marks all unread messages from [studentId] as read.
  Future<void> markConversationRead(int studentId) async {
    await _put(
      '/tutor/conversations/$studentId/read',
      TutorMarkReadRequest(studentId: studentId).toJson(),
    );
  }

  // ─── Unread count ────────────────────────────────────────────────────────────

  /// GET /tutor/conversations/unread-count
  ///
  /// Returns the total number of unread messages across all student
  /// conversations.  Useful for the nav-bar badge.
  Future<int> getTotalUnreadCount() async {
    final data = await _get('/tutor/conversations/unread-count');
    return data['unreadCount'] as int? ?? 0;
  }
}
