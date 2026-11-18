import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';

/// One blocked chat message and the sender's chat suspension
/// (backend lib/chat_moderation.dart).
class ChatModerationCase {
  const ChatModerationCase({
    required this.userId,
    required this.role,
    required this.name,
    required this.status,
    required this.reason,
    required this.flaggedText,
    required this.otherName,
    required this.flaggedAt,
    this.flagCount = 1,
    this.appeal,
    this.appealedAt,
    this.decidedBy,
    this.decisionNote,
  });

  factory ChatModerationCase.fromJson(Map<String, dynamic> j) =>
      ChatModerationCase(
        userId: (j['userId'] as num?)?.toInt() ?? 0,
        role: j['role'] as String? ?? '',
        name: j['name'] as String? ?? 'Unknown user',
        status: j['status'] as String? ?? 'suspended',
        reason: j['reason'] as String? ?? '',
        flaggedText: j['flaggedText'] as String? ?? '',
        otherName: j['otherName'] as String? ?? '',
        flaggedAt: DateTime.tryParse('${j['flaggedAt']}')?.toLocal(),
        flagCount: (j['flagCount'] as num?)?.toInt() ?? 1,
        appeal: j['appeal'] as String?,
        appealedAt: DateTime.tryParse('${j['appealedAt']}')?.toLocal(),
        decidedBy: j['decidedBy'] as String?,
        decisionNote: j['decisionNote'] as String?,
      );

  final int userId;
  final String role; // student or tutor
  final String name;

  /// suspended, appealed, lifted or upheld.
  final String status;
  final String reason;
  final String flaggedText;
  final String otherName;
  final DateTime? flaggedAt;
  final int flagCount;
  final String? appeal;
  final DateTime? appealedAt;
  final String? decidedBy;
  final String? decisionNote;

  /// Waiting for an admin (suspended or explained).
  bool get isOpen => status == 'suspended' || status == 'appealed';

  String get statusLabel => switch (status) {
    'appealed' => 'Explanation received',
    'suspended' => 'Awaiting explanation',
    'lifted' => 'Chat restored',
    'upheld' => 'Kept suspended',
    _ => status,
  };
}

class AdminChatModerationService {
  AdminChatModerationService({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider =
           tokenProvider ??
           (() async => FirebaseAuth.instance.currentUser?.getIdToken());

  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String _error(http.Response r, String fallback) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['error'] is String) return body['error'];
    } on FormatException {
      // fall through
    }
    return fallback;
  }

  /// GET /admin/chat-moderation: open cases first.
  Future<List<ChatModerationCase>> cases() async {
    final r = await _client
        .get(
          Uri.parse('$apiBaseUrl/admin/chat-moderation'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw Exception(_error(r, 'Chat moderation could not be loaded.'));
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return [
      for (final c in body['cases'] as List? ?? const [])
        if (c is Map<String, dynamic>) ChatModerationCase.fromJson(c),
    ];
  }

  /// POST /admin/chat-moderation/{userId}/decision: [lift] restores chat;
  /// otherwise it stays suspended ([note] is the reason the user sees).
  Future<ChatModerationCase> decide(
    int userId, {
    required bool lift,
    String? note,
  }) async {
    final r = await _client
        .post(
          Uri.parse('$apiBaseUrl/admin/chat-moderation/$userId/decision'),
          headers: await _headers(),
          body: jsonEncode({
            'decision': lift ? 'lift' : 'keep',
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw Exception(_error(r, 'The decision could not be saved.'));
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ChatModerationCase.fromJson(body['case'] as Map<String, dynamic>);
  }
}
