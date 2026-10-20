import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

// ─── Models ────────────────────────────────────────────────────────────────

enum NotificationType { newMessage, upcomingLesson, other }

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime sentAt;
  bool isRead;
  final String? actionLabel;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.sentAt,
    required this.isRead,
    this.actionLabel,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    NotificationType type;
    switch (json['type']) {
      case 'new_message':
        type = NotificationType.newMessage;
        break;
      case 'upcoming_lesson':
        type = NotificationType.upcomingLesson;
        break;
      default:
        type = NotificationType.other;
    }
    return AppNotification(
      id: json['id'].toString(),
      type: type,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      sentAt: DateTime.parse(json['sent_at']),
      isRead: json['is_read'] == true || json['is_read'] == 1,
      actionLabel: json['action_label'],
    );
  }
}

// ─── Service ───────────────────────────────────────────────────────────────

class TutorNotificationService {
  static const String _base = 'http://10.0.2.2:8080';

  static Future<String?> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    return user == null ? null : await user.getIdToken();
  }

  static Future<List<AppNotification>> fetchNotifications() async {
    final token = await _token();
    if (token == null) return [];
    final res = await http.get(
      Uri.parse('$_base/tutor/notifications'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return [];
    final List data = jsonDecode(res.body)['notifications'] ?? [];
    return data.map((e) => AppNotification.fromJson(e)).toList();
  }

  static Future<void> markAllRead() async {
    final token = await _token();
    if (token == null) return;
    await http.put(
      Uri.parse('$_base/tutor/notifications/mark-all-read'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  static Future<void> markOneRead(String id) async {
    final token = await _token();
    if (token == null) return;
    await http.put(
      Uri.parse('$_base/tutor/notifications/$id/read'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────

class TutorNotificationsPage extends StatefulWidget {
  const TutorNotificationsPage({super.key});

  @override
  State<TutorNotificationsPage> createState() =>
      _TutorNotificationsPageState();
}

class _TutorNotificationsPageState extends State<TutorNotificationsPage> {
  List<AppNotification> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await TutorNotificationService.fetchNotifications();
      setState(() {
        _notifications = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load notifications.';
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    await TutorNotificationService.markAllRead();
    setState(() {
      for (final n in _notifications) {
        n.isRead = true;
      }
    });
  }

  Future<void> _markOneRead(AppNotification n) async {
    if (n.isRead) return;
    await TutorNotificationService.markOneRead(n.id);
    setState(() => n.isRead = true);
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  Map<String, List<AppNotification>> get _grouped {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final Map<String, List<AppNotification>> groups = {};
    for (final n in _notifications) {
      final d = DateTime(n.sentAt.year, n.sentAt.month, n.sentAt.day);
      String label;
      if (d == today) {
        label = 'Today';
      } else if (d == yesterday) {
        label = 'Yesterday';
      } else {
        label =
            '${n.sentAt.day} ${_monthName(n.sentAt.month)} ${n.sentAt.year}';
      }
      groups.putIfAbsent(label, () => []).add(n);
    }
    return groups;
  }

  String _monthName(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final time =
        '${dt.hour % 12 == 0 ? 12 : dt.hour % 12}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    return 'Yesterday · $time';
  }

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.newMessage:
        return Icons.chat_bubble_outline_rounded;
      case NotificationType.upcomingLesson:
        return Icons.calendar_today_outlined;
      case NotificationType.other:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Tutor',
              style: TextStyle(
                color: Color(0xFF1565C0),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _notifications.isEmpty
                  ? const Center(
                      child: Text('No notifications yet.',
                          style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        children: [
                          // Header row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Today  $_unreadCount unread',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              GestureDetector(
                                onTap: _markAllRead,
                                child: const Text(
                                  'Mark all as read',
                                  style: TextStyle(
                                    color: Color(0xFF1565C0),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Grouped notifications
                          for (final entry in _grouped.entries) ...[
                            if (entry.key != 'Today') ...[
                              const SizedBox(height: 16),
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            for (final n in entry.value)
                              _NotificationCard(
                                notification: n,
                                timeAgo: _timeAgo(n.sentAt),
                                icon: _iconFor(n.type),
                                onTap: () => _markOneRead(n),
                              ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

// ─── Notification Card ─────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final String timeAgo;
  final IconData icon;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.timeAgo,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      color: const Color(0xFF1565C0), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF1565C0),
                          fontWeight: isUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1565C0),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            if (notification.actionLabel != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    notification.actionLabel!,
                    style: const TextStyle(
                      color: Color(0xFF1565C0),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: Color(0xFF1565C0), size: 18),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
