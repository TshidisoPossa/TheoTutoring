import 'package:flutter/material.dart';


class AppColors {
  static const ink = Color(0xFF1B2433);         
  static const muted = Color(0xFF6B7585);      
  static const hint = Color(0xFF9AA3B2);       
  static const border = Color(0xFFDDE3EC);     
  static const brand = Color(0xFF2A66B0);      
  static const tagBg = Color(0xFFE8F0FB);      
  static const online = Color(0xFF16B97A);     
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
        fontFamily: 'Inter', // add google_fonts / asset if desired; falls back to system font
      ),
      home: const ChatsScreen(),
    );
  }
}


class ChatPreview {
  final String name;
  final String subject;
  final String message;
  final String time;
  final String avatarUrl;
  final bool online;
  final int unread;

  const ChatPreview({
    required this.name,
    required this.subject,
    required this.message,
    required this.time,
    required this.avatarUrl,
    this.online = false,
    this.unread = 0,
  });
}

const _chats = <ChatPreview>[
  ChatPreview(
    name: 'Theophilus Nkhabu',
    subject: 'Mathematics',
    message: 'Absolutely, those are key topics. I will...',
    time: '10:10 AM',
    avatarUrl: 'https://i.pravatar.cc/200?img=12',
    online: true,
    unread: 2,
  ),
  ChatPreview(
    name: 'Dr. Sarah Smith',
    subject: 'Statistics',
    message: 'See you on Monday for our session, remember...',
    time: 'Yesterday',
    avatarUrl: 'https://i.pravatar.cc/200?img=47',
  ),

];


class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  int _tabIndex = 2; 

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatPreview> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _chats;
    return _chats
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.subject.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final chats = _filtered;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                    icon: const Icon(Icons.search,
                        size: 28, color: AppColors.ink),
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
                  hintText: 'Search tutors or subjects...',
                  hintStyle:
                      const TextStyle(color: AppColors.hint, fontSize: 16),
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.inactive, size: 24),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.brand, width: 1.5),
                  ),
                ),
              ),
            ),

            
            Expanded(
              child: chats.isEmpty
                  ? const Center(
                      child: Text(
                        'No tutors match your search',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: chats.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => ChatTile(chat: chats[i]),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(
        index: _tabIndex,
        onChanged: (i) => setState(() => _tabIndex = i),
      ),
    );
  }
}


class ChatTile extends StatelessWidget {
  final ChatPreview chat;
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
              _Avatar(url: chat.avatarUrl, online: chat.online),
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
                              fontSize: 14, color: AppColors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _SubjectChip(label: chat.subject),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, color: AppColors.muted),
                          ),
                        ),
                        if (chat.unread > 0) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: chat.unread),
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
  final String url;
  final bool online;
  const _Avatar({required this.url, required this.online});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: Image.network(
              url,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.tagBg,
                child: const Icon(Icons.person, color: AppColors.brand),
              ),
            ),
          ),
          if (online)
            Positioned(
              left: 38 - 12 + 2,
              bottom: 2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  final String label;
  const _SubjectChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tagBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.brand,
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