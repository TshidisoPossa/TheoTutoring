import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Student/student_chatlist.dart';
import 'package:theo_tutoring_app/Pages/Student/student_chats.dart';
import 'package:theo_tutoring_app/services/student_chat_models.dart';
import 'package:theo_tutoring_app/services/student_chat_service.dart';

const _tutorId = 3;

final _contact = StudentChatContact.fromJson({
  'userId': _tutorId,
  'name': 'Thabo Mokoena',
  'lastMessage': 'See you Thursday',
  'time': '2h ago',
  'profilePhotoUrl': null,
  'unreadCount': 1,
});

Map<String, Object?> _message(int seq, String text, {bool mine = false}) => {
  'messageId': '${mine ? 10 : _tutorId}-client-$seq-xxxxxxxxxx',
  'seq': seq,
  'senderId': mine ? 10 : _tutorId,
  'receiverId': mine ? _tutorId : 10,
  'messageText': text,
  'sentAt': '2026-10-24T09:4$seq:00Z',
  'isRead': false,
  'isOutgoing': mine,
  'bookingId': null,
};

/// A scripted student chat API. Every request is recorded.
class _FakeApi {
  final requests = <http.Request>[];

  /// Answers for POST .../messages, in order (status codes); 201 after.
  final sendStatuses = <int>[];
  List<Map<String, Object?>> latest = [
    _message(1, 'Hi Lerato'),
    _message(2, 'See you Thursday'),
  ];
  String? nextBeforeSeq;
  List<Map<String, Object?>> older = [];
  bool failHistory = false;
  List<Map<String, Object?>> conversations = [];
  bool failConversations = false;

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'GET' && path == '/student/conversations') {
      if (failConversations) return http.Response('down', 500);
      return http.Response(jsonEncode(conversations), 200);
    }
    if (request.method == 'GET' && path.endsWith('/messages')) {
      if (failHistory) return http.Response('down', 500);
      final before = request.url.queryParameters['beforeSeq'];
      return http.Response(
        jsonEncode(before == null ? latest : older),
        200,
        headers: {
          if (before == null && nextBeforeSeq != null)
            'x-next-before-seq': nextBeforeSeq!,
        },
      );
    }
    if (request.method == 'POST' && path.endsWith('/messages')) {
      final status = sendStatuses.isEmpty ? 201 : sendStatuses.removeAt(0);
      if (status != 201) return http.Response('{"error":"x"}', status);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          ..._message(9, body['messageText'] as String, mine: true),
          'messageId': '10-${body['clientMessageId']}',
        }),
        201,
      );
    }
    if (request.method == 'PUT' && path.endsWith('/read')) {
      return http.Response('{"markedRead":1,"unreadCount":0}', 200);
    }
    return http.Response('not found', 404);
  });

  StudentChatService service() =>
      StudentChatService(client: client, tokenProvider: () async => 'tok');

  List<Map<String, dynamic>> bodies(String method) => [
    for (final r in requests)
      if (r.method == method) jsonDecode(r.body) as Map<String, dynamic>,
  ];
}

Future<void> _openChat(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatTile(chat: _contact, service: api.service()),
      ),
    ),
  );
  await tester.tap(find.text('Thabo Mokoena'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();
}

final _clientId = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

void main() {
  group('StudentChatService', () {
    test('history: URL, token, beforeSeq and the next-page header', () async {
      final api = _FakeApi()..nextBeforeSeq = '1';
      final page = await api.service().getMessagesPage(_tutorId);
      final older = await api.service().getMessagesPage(_tutorId, beforeSeq: 1);

      expect(api.requests.first.url.path, '/student/conversations/3/messages');
      expect(api.requests.first.headers['Authorization'], 'Bearer tok');
      expect(api.requests.last.url.queryParameters, {'beforeSeq': '1'});
      expect(page.messages.map((m) => m.seq), [1, 2]);
      expect(page.messages.first.messageId, '3-client-1-xxxxxxxxxx');
      expect(page.nextBeforeSeq, 1);
      expect(older.nextBeforeSeq, isNull);
    });

    test('send body carries the idempotency key', () async {
      final api = _FakeApi();
      final sent = await api.service().sendMessage(
        tutorId: _tutorId,
        messageText: 'Hello',
        clientMessageId: 'abcdefghijklmnop',
      );
      expect(api.bodies('POST').single, {
        'clientMessageId': 'abcdefghijklmnop',
        'messageText': 'Hello',
        'receiverId': _tutorId,
      });
      expect(sent.isOutgoing, isTrue);
    });

    test('409 and 503 become typed errors', () async {
      final api = _FakeApi()..sendStatuses.addAll([409, 503, 500]);
      Future<void> send() => api.service().sendMessage(
        tutorId: _tutorId,
        messageText: 'x',
        clientMessageId: 'abcdefghijklmnop',
      );
      await expectLater(send(), throwsA(isA<StudentChatConflictException>()));
      await expectLater(
        send(),
        throwsA(isA<StudentChatUnavailableException>()),
      );
      await expectLater(send(), throwsA(isA<Exception>()));
    });

    test('mark-read sends the boundary message', () async {
      final api = _FakeApi();
      await api.service().markRead(_tutorId, '3-client-2-xxxxxxxxxx');
      expect(api.requests.single.method, 'PUT');
      expect(api.requests.single.url.path, '/student/conversations/3/read');
      expect(api.bodies('PUT').single, {
        'tutorId': _tutorId,
        'upToMessageId': '3-client-2-xxxxxxxxxx',
      });
    });

    test('new client message ids are valid and distinct', () {
      final a = StudentChatService.newClientMessageId();
      final b = StudentChatService.newClientMessageId();
      expect(a, matches(_clientId));
      expect(a, isNot(b));
    });
  });

  group('ChatsScreen', () {
    Map<String, Object?> conversation(
      int userId,
      String name,
      String lastMessage,
      int unreadCount,
    ) => {
      'userId': userId,
      'name': name,
      'lastMessage': lastMessage,
      'time': '2h ago',
      'profilePhotoUrl': null,
      'unreadCount': unreadCount,
    };

    _FakeApi listApi() => _FakeApi()
      ..conversations = [
        conversation(_tutorId, 'Thabo Mokoena', 'See you Thursday', 3),
        conversation(5, 'Naledi Dube', 'Thanks for the notes', 0),
      ];

    Future<void> pumpList(WidgetTester tester, _FakeApi api) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatsScreen(service: api.service())),
      );
      await tester.pumpAndSettle();
    }

    int listRequests(_FakeApi api) => api.requests
        .where((r) => r.url.path == '/student/conversations')
        .length;

    testWidgets('renders conversations from the injected service', (
      tester,
    ) async {
      final api = listApi();
      await pumpList(tester, api);

      expect(api.requests.single.url.path, '/student/conversations');
      expect(api.requests.single.headers['Authorization'], 'Bearer tok');
      expect(find.byType(ChatTile), findsNWidgets(2));
      expect(find.text('Thabo Mokoena'), findsOneWidget);
      expect(find.text('See you Thursday'), findsOneWidget);
      expect(find.text('Naledi Dube'), findsOneWidget);
      expect(find.text('Thanks for the notes'), findsOneWidget);
      expect(find.text('TM'), findsOneWidget);
    });

    testWidgets('shows unread counts only for conversations that have them', (
      tester,
    ) async {
      await pumpList(tester, listApi());

      expect(
        find.descendant(
          of: find.widgetWithText(ChatTile, 'Thabo Mokoena'),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.text('0'), findsNothing);
    });

    testWidgets('tapping a conversation opens that chat and refreshes the '
        'list on return', (tester) async {
      final api = listApi();
      await pumpList(tester, api);

      await tester.tap(find.text('Naledi Dube'));
      await tester.pumpAndSettle();

      final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
      expect(chat.contact.userId, 5);
      expect(chat.contact.name, 'Naledi Dube');
      expect(
        api.requests.any(
          (r) =>
              r.method == 'GET' &&
              r.url.path == '/student/conversations/5/messages',
        ),
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(listRequests(api), 2);
    });

    testWidgets('a loading error offers a retry', (tester) async {
      final api = listApi()..failConversations = true;
      await pumpList(tester, api);

      expect(
        find.text('Could not load conversations. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(ChatTile), findsNothing);

      api.failConversations = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(listRequests(api), 2);
      expect(find.byType(ChatTile), findsNWidgets(2));
      expect(
        find.text('Could not load conversations. Please try again.'),
        findsNothing,
      );
    });

    testWidgets('an empty list says there are no conversations', (
      tester,
    ) async {
      await pumpList(tester, _FakeApi());
      expect(find.text('No conversations yet'), findsOneWidget);
    });

    testWidgets('has no bottom navigation of its own', (tester) async {
      // The dashboard supplies the bottom navigation for its Chat tab
      await pumpList(tester, listApi());

      expect(find.text('Chats'), findsOneWidget);
      for (final label in ['Home', 'Lessons', 'Chat', 'Profile']) {
        expect(find.text(label), findsNothing);
      }
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull);
    });
  });

  group('ChatScreen', () {
    testWidgets('a chat tile opens that conversation with its history and '
        'marks it read', (tester) async {
      final api = _FakeApi();
      await _openChat(tester, api);

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Thabo Mokoena'),
        ),
        findsOneWidget,
      );
      expect(find.text('Hi Lerato'), findsOneWidget);
      expect(find.text('See you Thursday'), findsOneWidget);
      expect(
        api.bodies('PUT').single['upToMessageId'],
        '3-client-2-xxxxxxxxxx',
      );
    });

    testWidgets('the back arrow returns to the chat list', (tester) async {
      await _openChat(tester, _FakeApi());
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(ChatTile), findsOneWidget);
    });

    testWidgets('sending posts the text with a fresh clientMessageId', (
      tester,
    ) async {
      final api = _FakeApi();
      await _openChat(tester, api);
      await _type(tester, '  Bring the textbook  ');

      final body = api.bodies('POST').single;
      expect(body['messageText'], 'Bring the textbook');
      expect(body['receiverId'], _tutorId);
      expect(body['clientMessageId'] as String, matches(_clientId));
      expect(find.text('Bring the textbook'), findsOneWidget);
      expect(find.text('Sending...'), findsNothing);
    });

    testWidgets('a failed send is retried with the same clientMessageId', (
      tester,
    ) async {
      final api = _FakeApi()..sendStatuses.add(503);
      await _openChat(tester, api);
      await _type(tester, 'Are you free?');

      expect(
        find.text(
          'Chat is unavailable right now. Please try again in a '
          'moment.',
        ),
        findsOneWidget,
      );
      expect(find.text('Not sent - tap to retry'), findsOneWidget);

      await tester.tap(find.text('Are you free?'));
      await tester.pumpAndSettle();

      final ids = [for (final b in api.bodies('POST')) b['clientMessageId']];
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(1), reason: 'retry reuses the id');
      expect(find.text('Not sent - tap to retry'), findsNothing);
      expect(find.text('Are you free?'), findsOneWidget);
    });

    testWidgets('after a 409 the retry uses a new clientMessageId', (
      tester,
    ) async {
      final api = _FakeApi()..sendStatuses.add(409);
      await _openChat(tester, api);
      await _type(tester, 'Hello again');

      expect(
        find.text('That message could not be sent. Tap it to try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Hello again'));
      await tester.pumpAndSettle();

      final ids = [for (final b in api.bodies('POST')) b['clientMessageId']];
      expect(ids.toSet(), hasLength(2));
      expect(find.text('Not sent - tap to retry'), findsNothing);
    });

    testWidgets('older messages load above the current page', (tester) async {
      final api = _FakeApi()
        ..latest = [_message(5, 'Five'), _message(6, 'Six')]
        ..nextBeforeSeq = '5'
        ..older = [_message(3, 'Three'), _message(4, 'Four')];
      await _openChat(tester, api);

      await tester.tap(find.text('Load earlier messages'));
      await tester.pumpAndSettle();

      expect(
        api.requests
            .where((r) => r.method == 'GET')
            .last
            .url
            .queryParameters['beforeSeq'],
        '5',
      );
      final three = tester.getTopLeft(find.text('Three')).dy;
      final five = tester.getTopLeft(find.text('Five')).dy;
      expect(three, lessThan(five));
      expect(find.text('Load earlier messages'), findsNothing);
    });

    testWidgets('a history failure offers a retry', (tester) async {
      final api = _FakeApi()..failHistory = true;
      await _openChat(tester, api);
      expect(find.text('Could not load messages.'), findsOneWidget);

      api.failHistory = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Hi Lerato'), findsOneWidget);
    });

    testWidgets('a new message from the tutor appears without a refresh', (
      tester,
    ) async {
      final api = _FakeApi();
      await _openChat(tester, api);
      expect(find.text('Are you ready?'), findsNothing);

      api.latest = [...api.latest, _message(3, 'Are you ready?')];
      await tester.pump(ChatScreen.pollInterval);
      await tester.pumpAndSettle();

      expect(find.text('Are you ready?'), findsOneWidget);
      expect(find.text('Hi Lerato'), findsOneWidget); // nothing duplicated
      expect(api.bodies('PUT').last['upToMessageId'], '3-client-3-xxxxxxxxxx');
    });

    testWidgets('a sent message is not shown twice once polling sees it', (
      tester,
    ) async {
      final api = _FakeApi();
      await _openChat(tester, api);
      await _type(tester, 'On my way');
      final stored = api.bodies('POST').single;

      api.latest = [
        ...api.latest,
        {
          ..._message(9, 'On my way', mine: true),
          'messageId': '10-${stored['clientMessageId']}',
        },
      ];
      await tester.pump(ChatScreen.pollInterval);
      await tester.pumpAndSettle();

      expect(find.text('On my way'), findsOneWidget);
    });
  });
}
