import 'package:flutter/material.dart';

import '../../services/student_chat_models.dart';
import '../../services/student_chat_service.dart';
import '../Tutor/tutor_theme.dart';

/// The conversation's colours: light, or dark while dark mode is on.
class AppColors {
  const AppColors._(this._dk);

  factory AppColors.of(BuildContext context) => AppColors._(context.tutorDark);

  final bool _dk;

  static const primary = Color(0xFF2B6CB8); // my bubbles, send button

  Color get chatBackground =>
      _dk ? TutorDark.background : const Color(0xFFF1F4FA);
  Color get receivedBubble =>
      _dk ? TutorDark.cardAlt : const Color(0xFFE3E8F1);
  Color get textDark => _dk ? TutorDark.text : const Color(0xFF1B2433);
  Color get textGrey => _dk ? TutorDark.textMuted : const Color(0xFF8A94A6);
  Color get inputBackground =>
      _dk ? TutorDark.cardAlt : const Color(0xFFE9EDF5);
  Color get surface => _dk ? TutorDark.card : Colors.white;
  Color get line => _dk ? TutorDark.border : const Color(0xFFE5E8EF);
  Color get accent => _dk ? TutorDark.blueText : primary; // blue text
}

class Message {
  final String text;
  final String time;
  final bool isMe;

  /// Still being sent (no server copy yet).
  final bool sending;

  /// Sending failed; tapping the bubble retries it.
  final bool failed;

  const Message(
    this.text,
    this.time, {
    required this.isMe,
    this.sending = false,
    this.failed = false,
  });
}

/// A message typed by the student that the server has not stored yet. Its
/// clientMessageId is reused on every retry, so it is stored at most once.
class _Pending {
  _Pending(this.text, this.clientMessageId);

  final String text;
  String clientMessageId;
  bool failed = false;
}

/// "9:41 AM" in local time.
String _timeLabel(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// One conversation between the signed-in student and [contact].
class ChatScreen extends StatefulWidget {
  final StudentChatContact contact;

  /// Tests pass their own service; the app uses the real API.
  final StudentChatService? service;

  const ChatScreen({super.key, required this.contact, this.service});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  late final StudentChatService _service =
      widget.service ?? StudentChatService();

  /// Stored messages, oldest first.
  final List<StudentChatMessage> _history = [];
  final List<_Pending> _pending = [];
  int? _nextBeforeSeq;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _loadFailed = false;

  int _navIndex = 2;

  int get _tutorId => widget.contact.userId;

  List<Message> get _messages => [
    for (final m in _history)
      Message(m.text, _timeLabel(m.sentAt), isMe: m.isOutgoing),
    for (final p in _pending)
      Message(
        p.text,
        p.failed ? 'Not sent - tap to retry' : 'Sending...',
        isMe: true,
        sending: !p.failed,
        failed: p.failed,
      ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final page = await _service.getMessagesPage(_tutorId);
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(page.messages);
        _nextBeforeSeq = page.nextBeforeSeq;
        _loading = false;
      });
      _scrollToBottom();
      await _markRead();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadOlder() async {
    final before = _nextBeforeSeq;
    if (before == null || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await _service.getMessagesPage(_tutorId, beforeSeq: before);
      if (!mounted) return;
      setState(() {
        _history.insertAll(0, page.messages);
        _nextBeforeSeq = page.nextBeforeSeq;
      });
    } catch (_) {
      _notify('Could not load earlier messages. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// Marks everything shown as read (best effort: the badge just stays).
  Future<void> _markRead() async {
    if (_history.isEmpty) return;
    try {
      await _service.markRead(_tutorId, _history.last.messageId);
    } catch (e) {
      debugPrint('Marking messages read failed: $e');
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final pending = _Pending(text, StudentChatService.newClientMessageId());
    setState(() {
      _pending.add(pending);
      _controller.clear();
    });
    _scrollToBottom();
    _attempt(pending);
  }

  /// Sends [pending], reusing its clientMessageId when retrying.
  Future<void> _attempt(_Pending pending) async {
    setState(() => pending.failed = false);
    try {
      final stored = await _service.sendMessage(
        tutorId: _tutorId,
        messageText: pending.text,
        clientMessageId: pending.clientMessageId,
      );
      if (!mounted) return;
      setState(() {
        _pending.remove(pending);
        if (!_history.any((m) => m.messageId == stored.messageId)) {
          _history.add(stored);
        }
      });
    } on StudentChatConflictException {
      // That id belongs to a different message: the next try needs a new one.
      pending.clientMessageId = StudentChatService.newClientMessageId();
      _failed(pending, 'That message could not be sent. Tap it to try again.');
    } on StudentChatUnavailableException {
      _failed(
        pending,
        'Chat is unavailable right now. Please try again in a moment.',
      );
    } catch (_) {
      _failed(pending, 'Message not sent. Tap it to try again.');
    }
  }

  void _failed(_Pending pending, String message) {
    if (!mounted) return;
    setState(() => pending.failed = true);
    _notify(message);
  }

  void _retry(int index) {
    final pendingIndex = index - _history.length;
    if (pendingIndex < 0 || pendingIndex >= _pending.length) return;
    final pending = _pending[pendingIndex];
    if (pending.failed) _attempt(pending);
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Light or dark colours (dark mode is switched on the Profile tab)
  AppColors get _colors => AppColors.of(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colors.surface,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: _colors.chatBackground,
              child: _buildMessages(),
            ),
          ),
          _buildInputBar(),
        ],
      ),
      // As the Scaffold's bar it stays behind the phone keyboard, so the
      // message box sits right above the keyboard instead of the nav bar
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildMessages() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load messages.',
              style: TextStyle(color: _colors.textGrey),
            ),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final messages = _messages;
    final hasOlder = _nextBeforeSeq != null;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      itemCount: messages.length + (hasOlder ? 1 : 0),
      itemBuilder: (_, i) {
        if (hasOlder && i == 0) {
          return Center(
            child: TextButton(
              onPressed: _loadingOlder ? null : _loadOlder,
              child: Text(
                _loadingOlder ? 'Loading...' : 'Load earlier messages',
              ),
            ),
          );
        }
        final index = hasOlder ? i - 1 : i;
        return MessageBubble(
          message: messages[index],
          onRetry: () => _retry(index),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final photoUrl = widget.contact.profilePhotoUrl;
    return AppBar(
      backgroundColor: _colors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: _colors.textDark),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFD9B8A0),
            foregroundImage: photoUrl == null || photoUrl.isEmpty
                ? null
                : NetworkImage(photoUrl),
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.contact.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _colors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: _colors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 14, right: 6),
              decoration: BoxDecoration(
                color: _colors.inputBackground,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          color: _colors.textGrey,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Transform.rotate(
                      angle: 0.8,
                      child: Icon(
                        Icons.attach_file,
                        color: _colors.textGrey,
                        size: 20,
                      ),
                    ),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    const items = [
      (Icons.home_outlined, 'Home'),
      (Icons.calendar_today_outlined, 'Lessons'),
      (Icons.chat_bubble_outline, 'Chat'),
      (Icons.person_outline, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _colors.surface,
        border: Border(top: BorderSide(color: _colors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final selected = i == _navIndex;
              final color = selected ? _colors.accent : _colors.textGrey;
              return InkWell(
                onTap: () => setState(() => _navIndex = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(items[i].$1, color: color, size: 26),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$2,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Message message;

  /// Called when a failed message is tapped.
  final VoidCallback? onRetry;

  const MessageBubble({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final colors = AppColors.of(context);
    final maxWidth = MediaQuery.of(context).size.width * 0.72;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: message.failed ? onRetry : null,
        child: Opacity(
          opacity: message.sending ? 0.7 : 1,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : colors.receivedBubble,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.35,
                    color: isMe ? Colors.white : colors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    message.time,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isMe ? Colors.white70 : colors.textGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
