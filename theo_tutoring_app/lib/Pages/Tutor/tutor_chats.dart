import 'package:flutter/material.dart';

// ─── Data models ───────────────────────────────────────────────────────────

class ChatContact {
  final String name;
  final String initials;
  final String subject;
  final String lastMessage;
  final String time;
  final int unread;

  const ChatContact({
    required this.name,
    required this.initials,
    required this.subject,
    required this.lastMessage,
    required this.time,
    this.unread = 0,
  });
}

class ChatMessage {
  final String text;
  final bool isOutgoing;
  final String time;
  final bool isSessionCard;
  final String? sessionTitle;
  final String? sessionDate;

  const ChatMessage({
    required this.text,
    required this.isOutgoing,
    required this.time,
    this.isSessionCard = false,
    this.sessionTitle,
    this.sessionDate,
  });
}

// ─── Chat list screen ───────────────────────────────────────────────────────

class TutorChatListScreen extends StatefulWidget {
  const TutorChatListScreen({super.key});

  @override
  State<TutorChatListScreen> createState() => _TutorChatListScreenState();
}

class _TutorChatListScreenState extends State<TutorChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<ChatContact> _contacts = const [
    ChatContact(
      name: 'Emma Roberts',
      initials: 'ER',
      subject: 'Mathematics',
      lastMessage: 'Looking for help with derivatives and chain rule…',
      time: '2h ago',
      unread: 2,
    ),
    ChatContact(
      name: 'Lerato P',
      initials: 'LP',
      subject: 'Physics',
      lastMessage: 'That works perfectly for me 👍',
      time: 'Yesterday',
    ),
    ChatContact(
      name: 'Sipho K',
      initials: 'SK',
      subject: 'Chemistry',
      lastMessage: 'Can we reschedule to Thursday?',
      time: 'Mon',
      unread: 1,
    ),
    ChatContact(
      name: 'Aisha M',
      initials: 'AM',
      subject: 'English',
      lastMessage: 'Thank you so much for the session!',
      time: 'Sun',
    ),
    ChatContact(
      name: 'Thabo N',
      initials: 'TN',
      subject: 'Biology',
      lastMessage: 'See you at 3pm tomorrow!',
      time: 'Fri',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatContact> get _filtered {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts
        .where((c) =>
            c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            c.subject.toLowerCase().contains(_searchQuery.toLowerCase()))
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

            // Contact list
            Expanded(
              child: ListView.separated(
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 76,
                  color: Colors.grey[100],
                ),
                itemBuilder: (context, index) {
                  final contact = _filtered[index];
                  return _ContactTile(
                    contact: contact,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TutorChatScreen(contact: contact),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _ContactTile extends StatelessWidget {
  final ChatContact contact;
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
            // Avatar
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
                      color: contact.unread > 0
                          ? Colors.black87
                          : Colors.black45,
                      fontWeight: contact.unread > 0
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
                if (contact.unread > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1457D9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${contact.unread}',
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
  final ChatContact contact;

  const TutorChatScreen({super.key, required this.contact});

  @override
  State<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends State<TutorChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [
    const ChatMessage(
      text: 'Hi TheoTutor! Are you available for a Maths session this week?',
      isOutgoing: false,
      time: '9:41 AM',
    ),
    const ChatMessage(
      text: 'Lerato Yes, I have some slots open. How about Thursday at 3:00 PM?',
      isOutgoing: true,
      time: '9:44 AM',
    ),
    const ChatMessage(
      text: 'That works perfectly for me. Can we cover integration and derivatives?',
      isOutgoing: false,
      time: '9:46 AM',
    ),
    const ChatMessage(
      text: "Absolutely! I'll bring some practice problems and materials. Make sure to bring your textbook.",
      isOutgoing: true,
      time: '9:48 AM',
    ),
    const ChatMessage(
      text: '',
      isOutgoing: false,
      time: '9:50 AM',
      isSessionCard: true,
      sessionTitle: 'Mathematics — Calculus',
      sessionDate: 'Thursday, 17 Oct · 3:00 – 4:30 PM',
    ),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isOutgoing: true,
        time: TimeOfDay.now().format(context),
      ));
    });
    _messageController.clear();
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
                  '${widget.contact.subject} · Online',
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
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + 1, // +1 for date divider
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _DateDivider(label: 'Today');
        }
        final msg = _messages[index - 1];
        if (msg.isSessionCard) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _SessionCard(
              title: msg.sessionTitle!,
              date: msg.sessionDate!,
              time: msg.time,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _MessageBubble(
            message: msg,
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
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

}

// ─── Reusable widgets ───────────────────────────────────────────────────────

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
  final ChatMessage message;
  final String initials;

  const _MessageBubble({required this.message, required this.initials});

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
                      color: Colors.black.withOpacity(0.05),
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
            message.time,
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatefulWidget {
  final String title;
  final String date;
  final String time;

  const _SessionCard({
    required this.title,
    required this.date,
    required this.time,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _confirmed = false;
  bool _declined = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: Color(0xFF1457D9)),
                const SizedBox(width: 6),
                const Text(
                  'SESSION REQUEST',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1457D9),
                    letterSpacing: .6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.date,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              '📍 Online (TheoTutor)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            if (_confirmed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 14, color: Color(0xFF16A34A)),
                    SizedBox(width: 6),
                    Text(
                      'Session Confirmed',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              )
            else if (_declined)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Declined',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black45),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _declined = true),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Decline',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _confirmed = true),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1457D9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Confirm',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
