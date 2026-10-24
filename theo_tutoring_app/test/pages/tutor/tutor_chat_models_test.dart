import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Tutor/Services/tutor_chat_models.dart';

void main() {
  group('TutorChatContact.fromJson', () {
    test('reads every field', () {
      final contact = TutorChatContact.fromJson({
        'userId': 7,
        'name': 'Lerato P',
        'initials': 'LP',
        'lastMessage': 'See you Thursday',
        'time': '9:41 AM',
        'unreadCount': 2,
        'isOnline': true,
      });

      expect(contact.userId, 7);
      expect(contact.name, 'Lerato P');
      expect(contact.initials, 'LP');
      expect(contact.lastMessage, 'See you Thursday');
      expect(contact.time, '9:41 AM');
      expect(contact.unreadCount, 2);
      expect(contact.isOnline, isTrue);
    });

    test('falls back when optional fields are missing', () {
      final contact = TutorChatContact.fromJson({'userId': 7});

      expect(contact.name, '');
      expect(contact.initials, '?');
      expect(contact.unreadCount, 0);
      expect(contact.isOnline, isFalse);
    });
  });

  group('TutorChatMessage.fromJson', () {
    Map<String, dynamic> message({
      required int senderId,
      required bool isOutgoing,
      Object? isRead,
    }) => {
      'messageId': '5-client-1',
      'seq': 14,
      'senderId': senderId,
      'receiverId': 99,
      'messageText': 'Hello',
      'sentAt': '2026-10-24T09:41:00Z',
      'isOutgoing': isOutgoing,
      'isRead': isRead,
      'bookingId': 12,
    };

    test('marks messages from the current user as outgoing', () {
      final msg = TutorChatMessage.fromJson(
        message(senderId: 5, isOutgoing: true),
        5,
      );

      expect(msg.isOutgoing, isTrue);
      expect(msg.messageId, '5-client-1');
      expect(msg.seq, 14);
      expect(msg.text, 'Hello');
      expect(msg.bookingId, 12);
    });

    test('marks messages from the other user as incoming', () {
      final msg = TutorChatMessage.fromJson(
        message(senderId: 99, isOutgoing: false),
        5,
      );

      expect(msg.isOutgoing, isFalse);
    });

    test('uses the server direction when it differs from sender ids', () {
      final msg = TutorChatMessage.fromJson(
        message(senderId: 99, isOutgoing: true),
        5,
      );

      expect(msg.isOutgoing, isTrue);
    });

    test('accepts MySQL tinyint and bool read flags', () {
      expect(
        TutorChatMessage.fromJson(
          message(senderId: 5, isOutgoing: true, isRead: 1),
          5,
        ).isRead,
        isTrue,
      );
      expect(
        TutorChatMessage.fromJson(
          message(senderId: 5, isOutgoing: true, isRead: true),
          5,
        ).isRead,
        isTrue,
      );
      expect(
        TutorChatMessage.fromJson(
          message(senderId: 5, isOutgoing: true, isRead: 0),
          5,
        ).isRead,
        isFalse,
      );
    });
  });

  test('TutorSendMessageRequest includes its idempotency key', () {
    expect(
      const TutorSendMessageRequest(
        receiverId: 3,
        messageText: 'Hi',
        clientMessageId: 'client-123',
      ).toJson(),
      {'receiverId': 3, 'messageText': 'Hi', 'clientMessageId': 'client-123'},
    );
    expect(
      const TutorSendMessageRequest(
        receiverId: 3,
        messageText: 'Hi',
        clientMessageId: 'client-123',
        bookingId: 4,
      ).toJson(),
      {
        'receiverId': 3,
        'messageText': 'Hi',
        'clientMessageId': 'client-123',
        'bookingId': 4,
      },
    );
  });

  test('TutorMarkReadRequest sends the message boundary', () {
    expect(const TutorMarkReadRequest(upToMessageId: '5-client-123').toJson(), {
      'upToMessageId': '5-client-123',
    });
  });
}
