import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../services/chat_moderation.dart';
import '../../services/chat_unread.dart';
import 'Services/tutor_chat_models.dart';
import 'Services/tutor_chat_service.dart';
import 'tutor_format.dart';
import 'tutor_nav.dart';
import 'tutor_theme.dart';

// Light colours, or the dark ones when the tutor turned on Dark Mode
class _Palette {
  _Palette(BuildContext context) : _dk = context.tutorDark;

  final bool _dk;

  Color get surface => _dk ? TutorDark.card : Colors.white;
  Color get page => _dk ? TutorDark.background : const Color(0xFFF5F7FA);
  Color get field => _dk ? TutorDark.cardAlt : const Color(0xFFF5F5F5);
  Color get divider => _dk ? TutorDark.border : const Color(0xFFEEEEEE);
  Color get text => _dk ? TutorDark.text : Colors.black87;
  Color get textSoft => _dk ? TutorDark.textMuted : Colors.black54;
  Color get textFaint => _dk ? TutorDark.textMuted : Colors.black45;
  Color get hint => _dk ? TutorDark.textFaint : const Color(0xFFBDBDBD);
  Color get avatarBg => _dk ? TutorDark.blueTint : const Color(0xFFD0E4FF);
  Color get avatarText => _dk ? TutorDark.blueText : const Color(0xFF1457D9);
}

// ─── Chat list screen ───────────────────────────────────────────────────────

class TutorChatListScreen extends StatefulWidget {
  /// Tests pass a fake service; the app uses the real API.
  final TutorChatService? chatService;

  const TutorChatListScreen({super.key, this.chatService});

  @override
  State<TutorChatListScreen> createState() => _TutorChatListScreenState();
}

class _TutorChatListScreenState extends State<TutorChatListScreen> {
  _Palette get _c => _Palette(context);

  final TextEditingController _searchController = TextEditingController();
  late final TutorChatService _chatService =
      widget.chatService ?? TutorChatService();
  String _searchQuery = '';

  List<TutorChatContact> _contacts = [];
  bool _isLoading = true;
  Object? _loadError;

  /// How often the list quietly refreshes last messages and unread badges.
  static const refreshInterval = Duration(seconds: 5);

  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _refreshTimer = Timer.periodic(refreshInterval, (_) => _refreshQuietly());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    if (widget.chatService == null) _chatService.close();
    super.dispose();
  }

  /// Reloads the list without the loading spinner; errors keep the old list.
  Future<void> _refreshQuietly() async {
    if (_refreshing || _isLoading || _loadError != null || !mounted) return;
    _refreshing = true;
    try {
      final contacts = await _chatService.getConversations();
      if (mounted) setState(() => _contacts = contacts);
    } catch (_) {
      // The next tick tries again.
    } finally {
      _refreshing = false;
    }
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
      backgroundColor: _c.surface,
      // The tutor bottom bar, with Chats selected (as on every tutor page)
      bottomNavigationBar: const TutorChatsBottomBar(depth: 1),
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
                      child: Icon(Icons.arrow_back,
                          color: _c.text),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    'Messages',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _c.text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _c.field,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.edit_outlined,
                          size: 18, color: _c.textSoft),
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
                  color: _c.field,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  // Results filter as you type; Search just closes the keyboard
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: 14, color: _c.text),
                  decoration: InputDecoration(
                    hintText: 'Search conversations…',
                    hintStyle:
                        TextStyle(color: _c.hint, fontSize: 14),
                    prefixIcon:
                        Icon(Icons.search, color: _c.hint, size: 20),
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
        color: _c.field,
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
    final c = _Palette(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: c.surface,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: c.avatarBg,
              child: Text(
                contact.initials,
                style: TextStyle(
                  color: c.avatarText,
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text,
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
                          ? c.text
                          : c.textFaint,
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
                  style: TextStyle(fontSize: 11, color: c.hint),
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

  /// How often an open conversation checks for new messages. Chat goes
  /// through the backend over HTTP (no live connection), so the screen asks
  /// for the newest page on this timer and adds anything it has not shown.
  static const pollInterval = Duration(seconds: 3);

  @override
  State<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends State<TutorChatScreen> {
  _Palette get _c => _Palette(context);

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

  /// Moderation: the tutor's own chat (suspended after a blocked message)
  /// and whether the student's chat is suspended.
  ChatModerationState _myChat = ChatModerationState.clear;
  bool _otherSuspended = false;

  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadStatus();
    _pollTimer = Timer.periodic(
      TutorChatScreen.pollInterval,
      (_) => _pollNewMessages(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Adds messages that arrived since the last load (from the student, or
  /// sent from another device), in seq order, without duplicates.
  Future<void> _pollNewMessages() async {
    if (_polling || _isLoading || _isSending || _loadError != null) return;
    if (!mounted) return;
    _polling = true;
    _loadStatus(); // an admin may have decided meanwhile
    try {
      final page = await widget.chatService.getMessagesPage(
        widget.contact.userId,
      );
      if (!mounted) return;
      final known = {for (final m in _messages) m.messageId};
      final fresh = [
        for (final m in page.messages)
          if (!known.contains(m.messageId)) m,
      ];
      if (fresh.isEmpty) return;
      final atBottom =
          !_scrollController.hasClients ||
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 80;
      setState(() {
        _messages = [..._messages, ...fresh]
          ..sort((a, b) => a.seq.compareTo(b.seq));
      });
      if (atBottom || fresh.any((m) => m.isOutgoing)) _scrollToBottom();
      await _markIncomingMessagesRead(fresh);
    } catch (_) {
      // Quiet: the next tick tries again, and sending shows its own errors.
    } finally {
      _polling = false;
    }
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
      ChatUnread.instance.refresh(); // the Chats badge
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
        // A poll may already have added the stored copy.
        if (!_messages.any((m) => m.messageId == sent.messageId)) {
          _messages = [..._messages, sent];
        }
        _isSending = false;
        if (_pendingClientMessageId == clientMessageId) {
          _pendingClientMessageId = null;
          _pendingMessageText = null;
        }
      });
      _messageController.clear();
      _scrollToBottom();
    } on ChatMessageBlockedException catch (e) {
      // Blocked by moderation: never delivered, and the chat is suspended
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _myChat = e.state;
        _pendingClientMessageId = null;
        _pendingMessageText = null;
      });
      _messageController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
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

  /// Whether either chat is suspended (best effort: on failure nothing
  /// changes, and the server still refuses blocked messages).
  Future<void> _loadStatus() async {
    try {
      final status = await widget.chatService.chatStatus(
        studentId: widget.contact.userId,
      );
      if (!mounted) return;
      setState(() {
        _myChat = status.me;
        _otherSuspended = status.otherSuspended;
      });
    } catch (_) {}
  }

  /// "Explain to the admin": sends the tutor's explanation.
  Future<void> _explain() async {
    final explanation = await showChatAppealDialog(context);
    if (explanation == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final state = await widget.chatService.appealChatSuspension(explanation);
      if (!mounted) return;
      setState(() => _myChat = state);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Your explanation was sent to the admin.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
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
      backgroundColor: _c.page,
      // The same layout as the student side: header on top, the tutor
      // bottom bar (Chats selected) underneath
      bottomNavigationBar: const TutorChatsBottomBar(depth: 2),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_otherSuspended)
              OtherChatSuspendedBanner(name: widget.contact.name),
            Expanded(child: _buildMessageList()),
            if (_myChat.suspended)
              ChatSuspendedPanel(state: _myChat, onExplain: _explain)
            else
              _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      color: _c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.arrow_back, color: _c.text),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 20,
            backgroundColor: _c.avatarBg,
            child: Text(
              widget.contact.initials,
              style: TextStyle(
                color: _c.avatarText,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name only: conversations show no online/offline status
          Expanded(
            child: Text(
              widget.contact.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _c.text,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Icon(Icons.more_vert,
                color: _c.textSoft, size: 22),
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
      color: _c.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 4),
              child: Icon(Icons.attach_file_outlined,
                  color: _c.hint, size: 22),
            ),
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 96),
              decoration: BoxDecoration(
                color: _c.field,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _c.divider),
              ),
              child: TextField(
                controller: _messageController,
                maxLines: null,
                style: TextStyle(fontSize: 14, color: _c.text),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle:
                      TextStyle(color: _c.hint, fontSize: 14),
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
    final c = _Palette(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textFaint),
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
    final c = _Palette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: c.hint,
                fontWeight: FontWeight.w500,
                letterSpacing: .04,
              ),
            ),
          ),
          Expanded(child: Divider(color: c.divider)),
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
    final c = _Palette(context);
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
                backgroundColor: c.avatarBg,
                child: Text(
                  initials,
                  style: TextStyle(
                    color: c.avatarText,
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
                      : c.surface,
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
                        : c.text,
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
            style: TextStyle(fontSize: 10, color: c.hint),
          ),
        ),
      ],
    );
  }
}

/// The tutor bottom bar on the chat pages, with Chats selected: the same
/// bar as every other tutor page, so conversations keep the app's layout.
/// [depth] is 1 on the Messages list and 2 in a conversation.
class TutorChatsBottomBar extends StatelessWidget {
  const TutorChatsBottomBar({required this.depth, super.key});

  final int depth;

  void _tap(BuildContext context, int index) {
    final nav = Navigator.of(context);
    if (index == 2) {
      // Chats: from a conversation, back to the list
      if (depth == 2 && nav.canPop()) nav.pop();
      return;
    }
    // Leave the chat pages, then open the tab where they were opened from
    for (var i = 0; i < depth && nav.canPop(); i++) {
      nav.pop();
    }
    openTutorTab(nav.context, index, current: -1);
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.tutorDark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? TutorDark.card : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: 2,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: dark ? TutorDark.blueText : const Color(0xFF246BFE),
        unselectedItemColor: const Color(0xFF9CA3AF),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (index) => _tap(context, index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(icon: ChatNavIcon(), label: 'Chats'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
