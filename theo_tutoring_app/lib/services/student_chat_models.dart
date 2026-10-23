class StudentChatContact {
  final int userId;
  final String name;
  final String initials;
  final String lastMessage;
  final String time;
  final String? profilePhotoUrl;
  final int unreadCount;

  const StudentChatContact({
    required this.userId,
    required this.name,
    required this.initials,
    required this.lastMessage,
    required this.time,
    required this.profilePhotoUrl,
    required this.unreadCount,
  });

  factory StudentChatContact.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final nameParts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials = nameParts.isEmpty
        ? '?'
        : nameParts.length > 1
            ? '${nameParts.first[0]}${nameParts.last[0]}'.toUpperCase()
            : nameParts.first[0].toUpperCase();

    return StudentChatContact(
      userId: json['userId'] as int,
      name: name,
      initials: initials,
      lastMessage: json['lastMessage'] as String? ?? '',
      time: json['time'] as String? ?? '',
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}
