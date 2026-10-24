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

/// One message in a student's conversation, as the API returns it.
class StudentChatMessage {
  final String messageId;
  final int seq;
  final int senderId;
  final int receiverId;
  final String text;
  final DateTime sentAt;
  final bool isRead;
  final bool isOutgoing;
  final int? bookingId;

  const StudentChatMessage({
    required this.messageId,
    required this.seq,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.sentAt,
    required this.isRead,
    required this.isOutgoing,
    this.bookingId,
  });

  factory StudentChatMessage.fromJson(Map<String, dynamic> json) =>
      StudentChatMessage(
        messageId: json['messageId'] as String,
        seq: json['seq'] as int,
        senderId: json['senderId'] as int,
        receiverId: json['receiverId'] as int,
        text: json['messageText'] as String? ?? '',
        sentAt: DateTime.parse(json['sentAt'] as String),
        isRead: json['isRead'] == true || json['isRead'] == 1,
        isOutgoing: json['isOutgoing'] == true,
        bookingId: json['bookingId'] as int?,
      );
}

/// A page of messages, oldest first, with the cursor for older ones.
class StudentChatMessagePage {
  final List<StudentChatMessage> messages;

  /// Pass as `beforeSeq` to load older messages; null when there are none.
  final int? nextBeforeSeq;

  const StudentChatMessagePage({required this.messages, this.nextBeforeSeq});
}
