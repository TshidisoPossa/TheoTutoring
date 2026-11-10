import 'package:flutter/material.dart';

import '../../services/student_chat_models.dart';
import '../../services/student_chat_service.dart';
import '../Tutor/tutor_theme.dart';
import 'student_chats.dart' show ChatScreen;

/// The chat list's colours: light, or dark while dark mode is on.
class AppColors {
  const AppColors._(this._dk);

  factory AppColors.of(BuildContext context) => AppColors._(context.tutorDark);

  final bool _dk;

  static const brand = Color(0xFF2A66B0); // fills: badges, focus

  Color get ink => _dk ? TutorDark.text : const Color(0xFF1B2433);
  Color get muted => _dk ? TutorDark.textMuted : const Color(0xFF6B7585);
  Color get hint => _dk ? TutorDark.textFaint : const Color(0xFF9AA3B2);
  Color get border => _dk ? TutorDark.border : const Color(0xFFDDE3EC);
  Color get tagBg => _dk ? TutorDark.blueTint : const Color(0xFFE8F0FB);
  Color get inactive => _dk ? TutorDark.textMuted : const Color(0xFF5B6B84);
  Color get surface => _dk ? TutorDark.card : Colors.white;
  Color get accent => _dk ? TutorDark.blueText : brand; // blue text
}

class TutorApp extends StatelessWidget {
  const TutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tutor Chats',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorSchemeSeed: AppColors.brand,
      ),
      home: const ChatsScreen(),
    );
  }
}

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, this.service});

  /// Used for the list and passed on to each conversation (tests use a fake).
  final StudentChatService? service;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _searchController = TextEditingController();
  late final StudentChatService _chatService =
      widget.service ?? StudentChatService();
  List<StudentChatContact> _chats = [];
  String _query = '';
  bool _isLoading = true;
  bool _hasLoadError = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
      _hasLoadError = false;
      _loadError = null;
    });

    try {
      final chats = await _chatService.getConversations();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasLoadError = true;
        _loadError = error;
      });
    }
  }

  List<StudentChatContact> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _chats;
    return _chats
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.lastMessage.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chats',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(
                      Icons.search,
                      size: 28,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.border),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                // Results filter as you type; Search just closes the keyboard
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 16, color: colors.ink),
                decoration: InputDecoration(
                  hintText: 'Search conversations...',
                  hintStyle: TextStyle(
                    color: colors.hint,
                    fontSize: 16,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: colors.inactive,
                    size: 24,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.brand,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),

            Expanded(child: _buildChatList()),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    final colors = AppColors.of(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasLoadError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load conversations. Please try again.',
              style: TextStyle(color: colors.muted),
            ),
            if (_loadError != null)
              Text(
                '$_loadError',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            TextButton(onPressed: _loadChats, child: const Text('Try again')),
          ],
        ),
      );
    }

    final chats = _filtered;
    if (chats.isEmpty) {
      return Center(
        child: Text(
          _chats.isEmpty
              ? 'No conversations yet'
              : 'No conversations match your search',
          style: TextStyle(color: colors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: chats.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) =>
          ChatTile(chat: chats[i], service: _chatService, onClosed: _loadChats),
    );
  }
}

class ChatTile extends StatelessWidget {
  final StudentChatContact chat;

  /// Passed on to the conversation (tests use a fake).
  final StudentChatService? service;

  /// Called after the conversation closes (to refresh unread counts).
  final VoidCallback? onClosed;

  const ChatTile({super.key, required this.chat, this.service, this.onClosed});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(contact: chat, service: service),
            ),
          );
          onClosed?.call();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(url: chat.profilePhotoUrl, initials: chat.initials),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chat.time,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              color: colors.muted,
                            ),
                          ),
                        ),
                        if (chat.unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: chat.unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String initials;
  const _Avatar({required this.url, required this.initials});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipOval(
        child: url == null || url!.isEmpty
            ? _fallbackAvatar(colors)
            : Image.network(
                url!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallbackAvatar(colors),
              ),
      ),
    );
  }

  Widget _fallbackAvatar(AppColors colors) {
    return Container(
      color: colors.tagBg,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: colors.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.brand,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
