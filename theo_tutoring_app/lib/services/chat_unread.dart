import 'dart:async';

import 'package:flutter/material.dart';

/// The number of unread chat messages for the signed-in student or tutor,
/// for the badge on the Chat/Chats navigation icon.
///
/// Checked every [pollInterval] while signed in, and again whenever a
/// conversation is read ([refresh]), so the badge follows the messages.
class ChatUnread {
  ChatUnread._();

  static final instance = ChatUnread._();

  static const pollInterval = Duration(seconds: 15);

  /// Unread messages across the user's conversations (0 when signed out).
  final count = ValueNotifier<int>(0);

  Future<int> Function()? _fetch;
  Timer? _timer;
  bool _checking = false;

  bool get isRunning => _timer != null;

  /// Starts following the unread count; [fetch] is GET
  /// .../conversations/unread-count.
  void start(Future<int> Function() fetch) {
    stop();
    _fetch = fetch;
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    refresh();
  }

  /// Stops (signing out) and clears the badge.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _fetch = null;
    count.value = 0;
  }

  /// Checks the count now (after reading a conversation).
  Future<void> refresh() async {
    final fetch = _fetch;
    if (fetch == null || _checking) return;
    _checking = true;
    try {
      final value = await fetch();
      if (_fetch == fetch) count.value = value < 0 ? 0 : value;
    } catch (_) {
      // Quiet: the badge keeps its last number until the next check.
    } finally {
      _checking = false;
    }
  }
}

/// The Chat/Chats navigation icon with a red badge for unread messages.
class ChatNavIcon extends StatelessWidget {
  const ChatNavIcon({
    this.icon = Icons.chat_bubble_outline_rounded,
    this.color,
    this.size,
    super.key,
  });

  final IconData icon;
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: ChatUnread.instance.count,
    builder: (context, unread, _) => Badge(
      key: const ValueKey('chat-unread-badge'),
      isLabelVisible: unread > 0,
      backgroundColor: const Color(0xFFE05252),
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: Icon(icon, color: color, size: size),
    ),
  );
}
