import 'package:flutter/material.dart';

import 'Services/student_chat_models.dart';
import 'Services/student_chat_service.dart';

class AppColors {
  static const ink = Color(0xFF1B2433);
  static const muted = Color(0xFF6B7585);
  static const hint = Color(0xFF9AA3B2);
  static const border = Color(0xFFDDE3EC);
  static const brand = Color(0xFF2A66B0);
  static const tagBg = Color(0xFFE8F0FB);
  static const inactive = Color(0xFF5B6B84);
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
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _searchController = TextEditingController();
  final _chatService = StudentChatService();
  List<StudentChatContact> _chats = [];
  String _query = '';
  int _tabIndex = 2;
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chats',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.search,
                      size: 28,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.border),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 16, color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'Search conversations...',
                  hintStyle: const TextStyle(
                    color: AppColors.hint,
                    fontSize: 16,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.inactive,
                    size: 24,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
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
      bottomNavigationBar: _BottomNav(
        index: _tabIndex,
        onChanged: (i) => setState(() => _tabIndex = i),
      ),
    );
  }

  Widget _buildChatList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasLoadError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Could not load conversations. Please try again.',
              style: TextStyle(color: AppColors.muted),
            ),
            if (_loadError != null)
              Text(
                '$_loadError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
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
          style: const TextStyle(color: AppColors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => ChatTile(chat: chats[i]),
    );
  }
}

class ChatTile extends StatelessWidget {
  final StudentChatContact chat;
  const ChatTile({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {},
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chat.time,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
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
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.muted,
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
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipOval(
        child: url == null || url!.isEmpty
            ? _fallbackAvatar()
            : Image.network(
                url!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackAvatar(),
              ),
      ),
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      color: AppColors.tagBg,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.brand,
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

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _BottomNav({required this.index, required this.onChanged});

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.calendar_today_outlined, Icons.calendar_today, 'Lessons'),
    (Icons.chat_bubble_outline, Icons.chat_bubble_outline, 'Chat'),
    (Icons.person_outline, Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == index ? _items[i].$2 : _items[i].$1,
                          size: 30,
                          color: i == index
                              ? AppColors.brand
                              : AppColors.inactive,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _items[i].$3,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: i == index
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: i == index
                                ? AppColors.brand
                                : AppColors.inactive,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
