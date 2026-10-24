import 'dart:math';

import 'package:flutter/material.dart';

import 'Services/tutor_chat_models.dart';
import 'Services/tutor_chat_service.dart';
import 'tutor_format.dart';

// ─── Chat list screen ───────────────────────────────────────────────────────

class TutorChatListScreen extends StatefulWidget {
  /// Tests pass a fake service; the app uses the real API.
  final TutorChatService? chatService;

  const TutorChatListScreen({super.key, this.chatService});

  @override
  State<TutorChatListScreen> createState() => _TutorChatListScreenState();
}

class _TutorChatListScreenState extends State<TutorChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final TutorChatService _chatService =
      widget.chatService ?? TutorChatService();
  String _searchQuery = '';

  List<TutorChatContact> _contacts = [];
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (widget.chatService == null) _chatService.close();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final contacts = await _chatService.getConversations();
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _openChat(TutorChatContact contact) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TutorChatScreen(contact: contact, chatService: _chatService),
      ),
    );
    // Reading the conversation clears its unread badge on the server.
    if (mounted) _loadContacts();
  }

  List<TutorChatContact> get _filtered {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.lastMessage.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  if (Navigator.canPop(context)) ...[
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.black87),
                    ),
                    const SizedBox(width: 12),
                  ],
                  const Text(
                    'Messages',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_outlined,
                          size: 18, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Search conversations…',
                    hintStyle:
                        TextStyle(color: Colors.grey[400], fontSize: 14),
                    prefixIcon:
                        Icon(Icons.search, color: Colors.grey[400], size: 20),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(child: _buildContactList()),
          ],
        ),
      ),
    );
  }

  Widget _buildContactList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _StatusMessage(
        text: 'Could not load conversations.\n$_loadError',
        onRetry: _loadContacts,
      );
    }
    final contacts = _filtered;
    if (contacts.isEmpty) {
      return _StatusMessage(
        text: _contacts.isEmpty
            ? 'No conversations yet'
            : 'No conversations match your search',
      );
    }
    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 76,
        color: Colors.grey[100],
      ),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return _ContactTile(
          contact: contact,
          onTap: () => _openChat(contact),
        );
      },
    );
  }
}

class _ContactTile extends StatelessWidget {
  final TutorChatContact contact;
  final VoidCallback onTap;

  const _ContactTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFD0E4FF),
              child: Text(
                contact.initials,
                style: const TextStyle(
                  color: Color(0xFF1457D9),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    contact.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: contact.unreadCount > 0
                          ? Colors.black87
                          : Colors.black45,
                      fontWeight: contact.unreadCount > 0
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Time + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  contact.time,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                if (contact.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1457D9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${contact.unreadCount}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chat conversation screen ───────────────────────────────────────────────

class TutorChatScreen extends StatefulWidget {
  final TutorChatContact contact;
  final TutorChatService chatService;

  const TutorChatScreen({
    super.key,
    required this.contact,
    required this.chatService,
  });

  @override
  State<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends State<TutorChatScreen> {
  static final Random _clientMessageRandom = Random.secure();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<TutorChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingOlder = false;
  int? _nextBeforeSeq;
  String? _pendingClientMessageId;
  String? _pendingMessageText;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final List<TutorChatMessage> messages;
    try {
      final page = await widget.chatService.getMessagesPage(
        widget.contact.userId,
      );
      messages = page.messages;
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _nextBeforeSeq = page.nextBeforeSeq;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error;
      });
      return;
    }
    await _markIncomingMessagesRead(messages);
  }

  Future<void> _loadOlderMessages() async {
    final beforeSeq = _nextBeforeSeq;
    if (beforeSeq == null || _isLoadingOlder) return;
    setState(() => _isLoadingOlder = true);
    try {
      final page = await widget.chatService.getMessagesPage(
        widget.contact.userId,
        beforeSeq: beforeSeq,
      );
      if (!mounted) return;
      final byId = {for (final message in _messages) message.messageId: message};
      for (final message in page.messages) {
        byId[message.messageId] = message;
      }
      final messages = byId.values.toList()
        ..sort((a, b) => a.seq.compareTo(b.seq));
      setState(() {
        _messages = messages;
        _nextBeforeSeq = page.nextBeforeSeq;
        _isLoadingOlder = false;
      });
      await _markIncomingMessagesRead(messages);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingOlder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load older messages. Try again.')),
      );
    }
  }

  Future<void> _markIncomingMessagesRead(
    List<TutorChatMessage> messages,
  ) async {
    TutorChatMessage? lastIncoming;
    for (final message in messages) {
      if (!message.isOutgoing &&
          (lastIncoming == null || message.seq > lastIncoming.seq)) {
        lastIncoming = message;
      }
    }
    if (lastIncoming == null) return;
    try {
      await widget.chatService.markConversationRead(
        widget.contact.userId,
        upToMessageId: lastIncoming.messageId,
      );
    } catch (error) {
      // The messages are on screen; only the unread badge is out of date.
      debugPrint('Marking conversation read failed: $error');
    }
  }

  String _newClientMessageId() => List<int>.generate(
    16,
    (_) => _clientMessageRandom.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  void _messageTextChanged(String value) {
    if (_pendingMessageText != null && value.trim() != _pendingMessageText) {
      _pendingMessageText = null;
      _pendingClientMessageId = null;
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;
    if (_pendingMessageText != text) {
      _pendingMessageText = text;
      _pendingClientMessageId = _newClientMessageId();
    }
    final clientMessageId = _pendingClientMessageId!;
    setState(() => _isSending = true);
    try {
      final sent = await widget.chatService.sendMessage(
        studentId: widget.contact.userId,
        messageText: text,
        clientMessageId: clientMessageId,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, sent];
        _isSending = false;
        if (_pendingClientMessageId == clientMessageId) {
          _pendingClientMessageId = null;
          _pendingMessageText = null;
        }
      });
      _messageController.clear();
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSending = false);
      final message = switch (error) {
        TutorChatConflictException() =>
          'This message conflicts with an earlier send. Check the chat before retrying.',
        TutorChatUnavailableException() =>
          'Chat is temporarily unavailable. Please retry your message.',
        _ => 'Message not sent. Please try again.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// "9:41 AM" in the device's time zone and clock format.
  String _timeLabel(String sentAt) {
    final sent = DateTime.tryParse(sentAt);
    if (sent == null) return sentAt;
    return TimeOfDay.fromDateTime(sent.toLocal()).format(context);
  }

  /// "Today" or the date of the first message, e.g. "Sat, 24 Oct 2026".
  String _dateLabel() {
    final first = DateTime.tryParse(_messages.first.sentAt)?.toLocal();
    if (first == null) return 'Today';
    final now = DateTime.now();
    if (first.year == now.year &&
        first.month == now.month &&
        first.day == now.day) {
      return 'Today';
    }
    return formatLongDate(first.toIso8601String());
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMessageList()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: Colors.black87),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFD0E4FF),
            child: Text(
              widget.contact.initials,
              style: const TextStyle(
                color: Color(0xFF1457D9),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.contact.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  widget.contact.isOnline ? 'Online' : 'Offline',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: const Icon(Icons.phone_outlined,
                color: Colors.black54, size: 22),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {},
            child: const Icon(Icons.more_vert,
                color: Colors.black54, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _StatusMessage(
        text: 'Could not load messages.\n$_loadError',
        onRetry: _loadMessages,
      );
    }
    if (_messages.isEmpty) {
      return const _StatusMessage(text: 'No messages yet. Say hello!');
    }
    final hasOlderMessages = _nextBeforeSeq != null;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + 1 + (hasOlderMessages ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasOlderMessages && index == 0) {
          return Align(
            child: TextButton(
              onPressed: _isLoadingOlder ? null : _loadOlderMessages,
              child: _isLoadingOlder
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load earlier messages'),
            ),
          );
        }
        final messageIndex = index - (hasOlderMessages ? 1 : 0);
        if (messageIndex == 0) {
          return _DateDivider(label: _dateLabel());
        }
        final msg = _messages[messageIndex - 1];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _MessageBubble(
            message: msg,
            time: _timeLabel(msg.sentAt),
            initials: widget.contact.initials,
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 4),
              child: Icon(Icons.attach_file_outlined,
                  color: Colors.grey[400], size: 22),
            ),
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 96),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _messageController,
                maxLines: null,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle:
                      TextStyle(color: Colors.grey[400], fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  isDense: true,
                ),
                onChanged: _messageTextChanged,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF1457D9),
                shape: BoxShape.circle,
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

}

// ─── Reusable widgets ───────────────────────────────────────────────────────

/// Centred grey text for loading errors and empty lists, with an optional
/// retry button.
class _StatusMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _StatusMessage({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black45),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  final String label;
  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[200])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[400],
                fontWeight: FontWeight.w500,
                letterSpacing: .04,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[200])),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final TutorChatMessage message;
  final String time;
  final String initials;

  const _MessageBubble({
    required this.message,
    required this.time,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: message.isOutgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: message.isOutgoing
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!message.isOutgoing) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFD0E4FF),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Color(0xFF1457D9),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.68,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: message.isOutgoing
                      ? const Color(0xFF1457D9)
                      : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(
                        message.isOutgoing ? 18 : 4),
                    bottomRight: Radius.circular(
                        message.isOutgoing ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: message.isOutgoing
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
              ),
            ),
            if (message.isOutgoing) const SizedBox(width: 4),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(
            top: 4,
            left: message.isOutgoing ? 0 : 44,
            right: message.isOutgoing ? 4 : 0,
          ),
          child: Text(
            time,
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }
}
