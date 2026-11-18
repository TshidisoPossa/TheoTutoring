import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Chat moderation in the app (backend lib/chat_moderation.dart). Messages
// with contact details (emails, phone numbers, other apps) or abuse are
// blocked by the server and the sender's chat is suspended until an admin
// reviews it. The sender can explain; the other person sees that the
// sender's chat is suspended.

/// The signed-in user's chat moderation state.
class ChatModerationState {
  const ChatModerationState({
    required this.suspended,
    required this.status,
    this.reason,
    this.canAppeal = false,
    this.appeal,
    this.decisionNote,
  });

  static const clear = ChatModerationState(suspended: false, status: 'clear');

  factory ChatModerationState.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return clear;
    return ChatModerationState(
      suspended: json['suspended'] == true,
      status: json['status'] as String? ?? 'clear',
      reason: json['reason'] as String?,
      canAppeal: json['canAppeal'] == true,
      appeal: json['appeal'] as String?,
      decisionNote: json['decisionNote'] as String?,
    );
  }

  final bool suspended;

  /// clear, suspended, appealed, lifted or upheld.
  final String status;

  /// What was blocked, e.g. "a phone number".
  final String? reason;
  final bool canAppeal;
  final String? appeal;

  /// The admin's note when they kept the suspension.
  final String? decisionNote;

  bool get waitingForAdmin => status == 'appealed';
}

/// GET /{role}/chat-status?with=otherUserId.
class ChatStatusResult {
  const ChatStatusResult({required this.me, required this.otherSuspended});

  final ChatModerationState me;
  final bool otherSuspended;
}

/// The server refused a message: it was blocked (contact details or abuse)
/// or the sender's chat is suspended.
class ChatMessageBlockedException implements Exception {
  const ChatMessageBlockedException(this.message, this.state);

  final String message;
  final ChatModerationState state;

  @override
  String toString() => message;

  /// The refusal in [response], or null if it is not a moderation one.
  static ChatMessageBlockedException? from(http.Response response) {
    if (response.statusCode != 403 && response.statusCode != 422) return null;
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final code = body['code'];
      if (code != 'message_blocked' && code != 'chat_suspended') return null;
      return ChatMessageBlockedException(
        body['error'] as String? ?? 'Message not sent.',
        ChatModerationState.fromJson(body['chatStatus']),
      );
    } on FormatException {
      return null;
    }
  }
}

/// Shared moderation calls for the student and tutor chat services.
class ChatModerationApi {
  const ChatModerationApi({
    required this.base,
    required this.client,
    required this.headers,
  });

  /// e.g. "$apiBaseUrl/student".
  final String base;
  final http.Client client;
  final Future<Map<String, String>> Function() headers;

  Future<ChatStatusResult> status({int? withUserId}) async {
    final response = await client
        .get(
          Uri.parse('$base/chat-status').replace(
            queryParameters: withUserId == null ? null : {'with': '$withUserId'},
          ),
          headers: await headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Loading chat status failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatStatusResult(
      me: ChatModerationState.fromJson(body['me']),
      otherSuspended: body['otherSuspended'] == true,
    );
  }

  Future<ChatModerationState> appeal(String explanation) async {
    final response = await client
        .post(
          Uri.parse('$base/chat-appeal'),
          headers: await headers(),
          body: jsonEncode({'explanation': explanation}),
        )
        .timeout(const Duration(seconds: 15));
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (response.statusCode != 200 || body is! Map<String, dynamic>) {
      throw Exception(
        body is Map<String, dynamic> && body['error'] is String
            ? body['error']
            : 'Your explanation could not be sent.',
      );
    }
    return ChatModerationState.fromJson(body['chatStatus']);
  }
}

/// Shown instead of the message box while the user's chat is suspended:
/// why, and a button to explain to the admin.
class ChatSuspendedPanel extends StatelessWidget {
  const ChatSuspendedPanel({
    required this.state,
    required this.onExplain,
    super.key,
  });

  final ChatModerationState state;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF3A2A12) : const Color(0xFFFFF4E5);
    final fg = dark ? const Color(0xFFFFD08A) : const Color(0xFF8A4B00);
    final reason = state.reason;
    final String detail;
    if (state.waitingForAdmin) {
      detail =
          'Your explanation has been sent. An admin will review it and '
          'let you know.';
    } else if (state.status == 'upheld') {
      detail =
          'An admin reviewed it and your chat stays suspended.'
          '${state.decisionNote == null ? '' : ' Reason: ${state.decisionNote}'}';
    } else {
      detail =
          'A message you sent contained ${reason ?? 'content that is not '
              'allowed'}, so it was not delivered. Sharing contact details '
          'or abusive language is not allowed on TheoTutoring.';
    }
    return Material(
      color: bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.block_rounded, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your chat is suspended',
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(detail, style: TextStyle(color: fg, fontSize: 13)),
              if (state.canAppeal) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('explain-to-admin'),
                  onPressed: onExplain,
                  style: FilledButton.styleFrom(backgroundColor: fg),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Explain to the admin'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown above the messages when the other person's chat is suspended.
class OtherChatSuspendedBanner extends StatelessWidget {
  const OtherChatSuspendedBanner({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      color: dark ? const Color(0xFF2B3446) : const Color(0xFFEFF3FB),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: dark ? Colors.white70 : const Color(0xFF475569),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "$name's chat is suspended while an admin reviews a message. "
              "They can't send messages right now.",
              style: TextStyle(
                fontSize: 12.5,
                color: dark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for the explanation; returns it, or null if cancelled.
Future<String?> showChatAppealDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _AppealDialog());

class _AppealDialog extends StatefulWidget {
  const _AppealDialog();

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().length >= 10;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Explain to the admin'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tell the admin what happened. They will read your blocked message '
          'and this explanation, then decide whether to restore your chat.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLength: 1000,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'At least 10 characters',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _valid
            ? () => Navigator.pop(context, _controller.text.trim())
            : null,
        child: const Text('Send explanation'),
      ),
    ],
  );
}
