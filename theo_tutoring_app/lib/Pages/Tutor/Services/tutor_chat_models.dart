// lib/Pages/Tutor/Services/tutor_chat_models.dart

class TutorChatContact {
  final int userId;
  final String name;
  final String initials;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final bool isOnline;

  const TutorChatContact({
    required this.userId,
    required this.name,
    required this.initials,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
    required this.isOnline,
  });

  factory TutorChatContact.fromJson(Map<String, dynamic> json) {
    return TutorChatContact(
      userId: json['userId'] as int,
      name: json['name'] as String? ?? '',
      initials: json['initials'] as String? ?? '?',
      lastMessage: json['lastMessage'] as String? ?? '',
      time: json['time'] as String? ?? '',
      unreadCount: json['unreadCount'] as int? ?? 0,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }
}

class TutorChatMessage {
  final int messageId;
  final int senderId;
  final int receiverId;
  final String text;
  final String sentAt;
  final bool isRead;
  final bool isOutgoing;
  final int? bookingId;

  const TutorChatMessage({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.sentAt,
    required this.isRead,
    required this.isOutgoing,
    this.bookingId,
  });

  factory TutorChatMessage.fromJson(
      Map<String, dynamic> json, int currentUserId) {
    final senderId = json['senderId'] as int;
    return TutorChatMessage(
      messageId: json['messageId'] as int,
      senderId: senderId,
      receiverId: json['receiverId'] as int,
      text: json['messageText'] as String? ?? '',
      sentAt: json['sentAt'] as String? ?? '',
      isRead: json['isRead'] == 1 || json['isRead'] == true,
      isOutgoing: senderId == currentUserId,
      bookingId: json['bookingId'] as int?,
    );
  }
}

class TutorSendMessageRequest {
  final int receiverId;
  final String messageText;
  final int? bookingId;

  const TutorSendMessageRequest({
    required this.receiverId,
    required this.messageText,
    this.bookingId,
  });

  Map<String, dynamic> toJson() => {
        'receiverId': receiverId,
        'messageText': messageText,
        if (bookingId != null) 'bookingId': bookingId,
      };
}

class TutorMarkReadRequest {
  final int studentId;

  const TutorMarkReadRequest({required this.studentId});

  Map<String, dynamic> toJson() => {'studentId': studentId};
}