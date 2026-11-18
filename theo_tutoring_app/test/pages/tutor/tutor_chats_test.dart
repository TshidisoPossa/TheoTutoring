import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Tutor/Services/tutor_chat_service.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_chats.dart';
import 'package:theo_tutoring_app/config/api.dart';

const _token = 'tutor-id-token';
const _tutorId = 5;
const _studentId = 7;

Map<String, Object?> _message(int id, int senderId, String text) => {
  'messageId': '$senderId-client-$id',
  'seq': id,
  'senderId': senderId,
  'receiverId': senderId == _tutorId ? _studentId : _tutorId,
  'messageText': text,
  'sentAt': '2026-10-24T09:41:00Z',
  'isRead': 0,
  'isOutgoing': senderId == _tutorId,
};

/// A fake backend for the tutor chat routes. Every request is recorded.
class _FakeBackend {
  final requests = <http.Request>[];
  bool failConversations = false;
  bool failSend = false;
  bool failOlder = false;
  int sendStatus = 201;

  /// Messages that arrive after the conversation was opened.
  final newer = <Map<String, Object?>>[];

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    final method = request.method;
    if (method == 'GET' && path == '/tutor/conversations') {
      if (failConversations) return http.Response('boom', 500);
      return _json([
        {
          'userId': _studentId,
          'name': 'Lerato P',
          'initials': 'LP',
          'lastMessage': 'Hi tutor',
          'time': '2h ago',
          'unreadCount': 2,
          'isOnline': true,
        },
      ]);
    }
    if (method == 'GET' && path == '/tutor/me') {
      return _json({'userId': _tutorId});
    }
    if (method == 'GET' &&
        path == '/tutor/conversations/$_studentId/messages') {
      if (request.url.queryParameters['beforeSeq'] == '2') {
        if (failOlder) return http.Response('boom', 500);
        return _json([_message(1, _studentId, 'Earlier message')]);
      }
      return _json([_message(2, _studentId, 'Hi tutor'), ...newer],
          headers: {'x-next-before-seq': '2'});
    }
    if (method == 'POST' &&
        path == '/tutor/conversations/$_studentId/messages') {
      if (failSend) return http.Response('nope', 500);
      if (sendStatus == 409 || sendStatus == 503) {
        return http.Response('unavailable', sendStatus);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json(
        _message(2, _tutorId, body['messageText'] as String),
        status: sendStatus,
      );
    }
    if (method == 'PUT' && path == '/tutor/conversations/$_studentId/read') {
      return http.Response('', 204);
    }
    return http.Response('unexpected $method $path', 404);
  });

  TutorChatService service() =>
      TutorChatService(client: client, tokenProvider: () async => _token);

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).length;

  static http.Response _json(
    Object body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json', ...headers},
  );
}

Widget _app(TutorChatService service) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TutorChatListScreen(chatService: service),
            ),
          ),
          child: const Text('open chats'),
        ),
      ),
    ),
  ),
);

Future<void> _openList(WidgetTester tester, TutorChatService service) async {
  await tester.pumpWidget(_app(service));
  await tester.tap(find.text('open chats'));
  await tester.pumpAndSettle();
}

void main() {
  group('TutorChatService', () {
    test('uses apiBaseUrl and the Bearer token', () async {
      final backend = _FakeBackend();
      await backend.service().getConversations();

      final request = backend.requests.single;
      expect(request.url.toString(), '$apiBaseUrl/tutor/conversations');
      expect(request.headers['Authorization'], 'Bearer $_token');
    });

    test('looks up the tutor id once and marks outgoing messages', () async {
      final backend = _FakeBackend();
      final service = backend.service();

      final history = await service.getMessages(_studentId);
      final sent = await service.sendMessage(
        studentId: _studentId,
        messageText: 'Hello',
      );

      expect(history.single.isOutgoing, isFalse);
      expect(sent.isOutgoing, isTrue);
      expect(sent.text, 'Hello');
      expect(backend.count('GET', '/tutor/me'), 1);
    });

    test(
      'message pages send beforeSeq and parse the response cursor',
      () async {
        final backend = _FakeBackend();
        final page = await backend.service().getMessagesPage(
          _studentId,
          beforeSeq: 9,
        );

        final request = backend.requests.last;
        expect(request.url.queryParameters, {'beforeSeq': '9'});
        expect(page.messages.single.seq, 2);
        expect(page.nextBeforeSeq, 2);
      },
    );

    test('send accepts HTTP 200 and sends a clientMessageId', () async {
      final backend = _FakeBackend()..sendStatus = 200;
      await backend.service().sendMessage(
        studentId: _studentId,
        messageText: 'Hello',
      );

      final body = jsonDecode(
        backend.requests.singleWhere((r) => r.method == 'POST').body,
      ) as Map<String, dynamic>;
      expect(body['clientMessageId'], isA<String>());
      expect((body['clientMessageId'] as String), isNotEmpty);
    });

    test('send surfaces 409 and 503 responses distinctly', () async {
      for (final (status, errorType) in [
        (409, TutorChatConflictException),
        (503, TutorChatUnavailableException),
      ]) {
        final backend = _FakeBackend()..sendStatus = status;
        await expectLater(
          backend.service().sendMessage(
            studentId: _studentId,
            messageText: 'Hello',
          ),
          throwsA(
            isA<Exception>().having(
              (error) => error.runtimeType,
              'runtimeType',
              errorType,
            ),
          ),
        );
      }
    });

    test('markConversationRead sends a PUT for the student', () async {
      final backend = _FakeBackend();
      await backend.service().markConversationRead(
        _studentId,
        upToMessageId: '7-client-11',
      );

      final request = backend.requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, '/tutor/conversations/$_studentId/read');
      expect(jsonDecode(request.body), {'upToMessageId': '7-client-11'});
    });
  });

  group('Tutor chat screens', () {
    testWidgets('list shows conversations from the API', (tester) async {
      final backend = _FakeBackend();
      await _openList(tester, backend.service());

      expect(find.text('Lerato P'), findsOneWidget);
      expect(find.text('Hi tutor'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // unread badge
    });

    testWidgets('a load failure can be retried', (tester) async {
      final backend = _FakeBackend()..failConversations = true;
      await _openList(tester, backend.service());

      expect(
        find.textContaining('Could not load conversations'),
        findsOneWidget,
      );

      backend.failConversations = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Lerato P'), findsOneWidget);
    });

    testWidgets('opening a conversation loads messages and marks it read', (
      tester,
    ) async {
      final backend = _FakeBackend();
      await _openList(tester, backend.service());

      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();

      // Conversations show no online/offline status
      expect(find.text('Online'), findsNothing);
      expect(find.text('Offline'), findsNothing);
      expect(find.text('Hi tutor'), findsOneWidget);
      expect(backend.count('PUT', '/tutor/conversations/$_studentId/read'), 1);
      final read = backend.requests.singleWhere((r) => r.method == 'PUT');
      expect(jsonDecode(read.body), {'upToMessageId': '7-client-2'});

      // Back to the list, which reloads to refresh the unread badges.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(backend.count('GET', '/tutor/conversations'), 2);
    });

    testWidgets('loads and appends an older message page', (tester) async {
      final backend = _FakeBackend();
      await _openList(tester, backend.service());
      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();

      expect(find.text('Hi tutor'), findsOneWidget);
      await tester.tap(find.text('Load earlier messages'));
      await tester.pumpAndSettle();

      expect(find.text('Earlier message'), findsOneWidget);
      final older = backend.requests.singleWhere(
        (r) => r.url.queryParameters.containsKey('beforeSeq'),
      );
      expect(older.url.queryParameters['beforeSeq'], '2');
      expect(find.text('Load earlier messages'), findsNothing);
    });

    testWidgets('a failed older-page load keeps messages and can retry', (
      tester,
    ) async {
      final backend = _FakeBackend()..failOlder = true;
      await _openList(tester, backend.service());
      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Load earlier messages'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not load older messages'), findsOneWidget);
      expect(find.text('Hi tutor'), findsOneWidget);
      expect(find.text('Load earlier messages'), findsOneWidget);
    });

    testWidgets('sending posts the message and shows it', (tester) async {
      final backend = _FakeBackend();
      await _openList(tester, backend.service());
      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'See you Thursday');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final post = backend.requests.singleWhere((r) => r.method == 'POST');
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['receiverId'], _studentId);
      expect(body['messageText'], 'See you Thursday');
      expect(body['clientMessageId'], isA<String>());
      expect(find.text('See you Thursday'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('a failed send keeps the text and says so', (tester) async {
      final backend = _FakeBackend()..failSend = true;
      await _openList(tester, backend.service());
      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Lost message');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('Message not sent'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Lost message');
    });

    testWidgets('retry reuses the clientMessageId for the same message', (
      tester,
    ) async {
      final backend = _FakeBackend()..sendStatus = 503;
      await _openList(tester, backend.service());
      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Retry safely');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('Chat is temporarily unavailable. Please retry your message.'),
        findsOneWidget,
      );
      backend.sendStatus = 201;
      ScaffoldMessenger.of(
        tester.element(find.byType(TextField)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final posts = backend.requests.where((r) => r.method == 'POST').toList();
      final firstId =
          (jsonDecode(posts[0].body) as Map<String, dynamic>)['clientMessageId'];
      final retryId =
          (jsonDecode(posts[1].body) as Map<String, dynamic>)['clientMessageId'];
      expect(firstId, isA<String>());
      expect(retryId, firstId);
    });

    testWidgets('409 shows conflict guidance and retains the message', (
      tester,
    ) async {
      final backend = _FakeBackend()..sendStatus = 409;
      await _openList(tester, backend.service());
      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Conflict message');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This message conflicts with an earlier send. Check the chat before retrying.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Conflict message',
      );
    });

    testWidgets('a new message from the student appears without a refresh', (
      tester,
    ) async {
      final backend = _FakeBackend();
      await _openList(tester, backend.service());
      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();
      expect(find.text('Are you free at 3?'), findsNothing);

      backend.newer.add(_message(3, _studentId, 'Are you free at 3?'));
      await tester.pump(TutorChatScreen.pollInterval);
      await tester.pumpAndSettle();

      expect(find.text('Are you free at 3?'), findsOneWidget);
      expect(find.text('Hi tutor'), findsOneWidget); // nothing duplicated
      final reads = backend.requests.where((r) => r.method == 'PUT').toList();
      expect(jsonDecode(reads.last.body), {'upToMessageId': '7-client-3'});
    });

    testWidgets('a sent message is not shown twice once polling sees it', (
      tester,
    ) async {
      final backend = _FakeBackend();
      await _openList(tester, backend.service());
      await tester.tap(find.text('Lerato P'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'See you then');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      // The server's copy of the sent message, as the next poll returns it.
      backend.newer.add(_message(2, _tutorId, 'See you then'));
      await tester.pump(TutorChatScreen.pollInterval);
      await tester.pumpAndSettle();

      expect(find.text('See you then'), findsOneWidget);
    });
  });
}
