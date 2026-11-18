import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_chat_moderation_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_chat_moderation.dart';
import 'package:theo_tutoring_app/Pages/Student/student_bottom_nav.dart';
import 'package:theo_tutoring_app/Pages/Student/student_chats.dart';
import 'package:theo_tutoring_app/Pages/Tutor/Services/tutor_chat_models.dart';
import 'package:theo_tutoring_app/Pages/Tutor/Services/tutor_chat_service.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_chats.dart';
import 'package:theo_tutoring_app/services/chat_unread.dart';
import 'package:theo_tutoring_app/services/student_chat_models.dart';
import 'package:theo_tutoring_app/services/student_chat_service.dart';

// Chat: the unread badge, the shared layout, and moderation (a blocked
// message suspends the sender's chat; the other side is told; the sender
// explains; the admin decides). Every server is a fake.

Map<String, dynamic> _status({
  bool suspended = false,
  String status = 'clear',
  bool canAppeal = false,
  bool otherSuspended = false,
}) => {
  'me': {
    'suspended': suspended,
    'status': status,
    'reason': suspended ? 'a phone number' : null,
    'canAppeal': canAppeal,
  },
  'otherSuspended': otherSuspended,
};

/// A chat backend: messages are empty, chat-status is [status], sending
/// is refused as a blocked message.
class _ChatServer {
  _ChatServer(this.status);

  Map<String, dynamic> status;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/chat-status')) {
      return http.Response(jsonEncode(status), 200);
    }
    if (path.endsWith('/chat-appeal')) {
      status = _status(suspended: true, status: 'appealed');
      return http.Response(jsonEncode({'chatStatus': status['me']}), 200);
    }
    if (request.method == 'POST' && path.endsWith('/messages')) {
      status = _status(suspended: true, status: 'suspended', canAppeal: true);
      return http.Response(
        jsonEncode({
          'error': 'Message not sent: it contains a phone number.',
          'code': 'message_blocked',
          'chatStatus': status['me'],
        }),
        422,
      );
    }
    if (path.endsWith('/messages')) return http.Response('[]', 200);
    if (path == '/tutor/me') return http.Response('{"userId": 5}', 200);
    if (path.endsWith('/read')) return http.Response('{}', 200);
    if (path.endsWith('/conversations')) return http.Response('[]', 200);
    return http.Response('not found', 404);
  });
}

final _tutorContact = StudentChatContact.fromJson({
  'userId': 3,
  'name': 'Thabo Nkosi',
  'lastMessage': '',
  'time': '',
  'unreadCount': 0,
});

const _studentContact = TutorChatContact(
  userId: 7,
  name: 'Lerato Dube',
  initials: 'LD',
  lastMessage: '',
  time: '',
  unreadCount: 0,
  isOnline: true,
);

Future<void> _pump(WidgetTester tester, Widget home) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

/// Removes the screen so its 3-second refresh timer stops.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  group('unread badge', () {
    tearDown(ChatUnread.instance.stop);

    testWidgets('shows the unread count and follows it', (tester) async {
      var unread = 3;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: StudentBottomNav(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      ChatUnread.instance.start(() async => unread);
      await tester.pump();
      expect(find.text('3'), findsOneWidget);

      unread = 0; // the conversation was read
      await ChatUnread.instance.refresh();
      await tester.pump();
      expect(find.text('3'), findsNothing);

      unread = 120;
      await ChatUnread.instance.refresh();
      await tester.pump();
      expect(find.text('99+'), findsOneWidget);

      ChatUnread.instance.stop(); // signing out clears it
      await tester.pump();
      expect(find.text('99+'), findsNothing);
    });
  });

  group('student conversation', () {
    testWidgets('keeps the student bottom bar, with Chat selected', (
      tester,
    ) async {
      final server = _ChatServer(_status());
      await _pump(
        tester,
        ChatScreen(
          contact: _tutorContact,
          service: StudentChatService(
            client: server.client,
            tokenProvider: () async => 't',
          ),
        ),
      );
      final nav = tester.widget<StudentBottomNav>(
        find.byType(StudentBottomNav),
      );
      expect(nav.currentIndex, StudentBottomNav.chatTab);
      expect(find.text('Online'), findsNothing);
      expect(find.text('Offline'), findsNothing);
      await _close(tester);
    });

    testWidgets('a blocked message suspends the chat; the student explains',
        (tester) async {
      final server = _ChatServer(_status());
      await _pump(
        tester,
        ChatScreen(
          contact: _tutorContact,
          service: StudentChatService(
            client: server.client,
            tokenProvider: () async => 't',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'call 082 555 1234');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Not delivered, and no message box any more
      expect(find.text('call 082 555 1234'), findsNothing);
      expect(find.text('Your chat is suspended'), findsOneWidget);
      expect(find.textContaining('contained a phone number'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Let the "Message not sent" snackbar go before tapping under it
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('explain-to-admin')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'It was the school office number, sorry.',
      );
      await tester.pump(); // the button enables once there is enough text
      await tester.tap(find.text('Send explanation'));
      await tester.pumpAndSettle();

      final appeal = server.requests.lastWhere(
        (r) => r.url.path == '/student/chat-appeal',
      );
      expect(jsonDecode(appeal.body), {
        'explanation': 'It was the school office number, sorry.',
      });
      expect(find.textContaining('explanation has been sent'), findsOneWidget);
      expect(find.byKey(const ValueKey('explain-to-admin')), findsNothing);
      await _close(tester);
    });

    testWidgets("the tutor's suspended chat is shown to the student", (
      tester,
    ) async {
      final server = _ChatServer(_status(otherSuspended: true));
      await _pump(
        tester,
        ChatScreen(
          contact: _tutorContact,
          service: StudentChatService(
            client: server.client,
            tokenProvider: () async => 't',
          ),
        ),
      );
      expect(
        find.textContaining("Thabo Nkosi's chat is suspended"),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget); // student can still send
      await _close(tester);
    });
  });

  group('tutor conversation', () {
    testWidgets('has the tutor bottom bar and no online status', (
      tester,
    ) async {
      final server = _ChatServer(_status());
      await _pump(
        tester,
        TutorChatScreen(
          contact: _studentContact,
          chatService: TutorChatService(
            client: server.client,
            tokenProvider: () async => 't',
          ),
        ),
      );
      expect(find.byType(TutorChatsBottomBar), findsOneWidget);
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
      expect(find.text('Offline'), findsNothing);
      await _close(tester);
    });

    testWidgets("a suspended tutor sees why; the student's banner too", (
      tester,
    ) async {
      final server = _ChatServer(
        _status(
          suspended: true,
          status: 'suspended',
          canAppeal: true,
          otherSuspended: true,
        ),
      );
      await _pump(
        tester,
        TutorChatScreen(
          contact: _studentContact,
          chatService: TutorChatService(
            client: server.client,
            tokenProvider: () async => 't',
          ),
        ),
      );
      expect(find.text('Your chat is suspended'), findsOneWidget);
      expect(find.text('Explain to the admin'), findsOneWidget);
      expect(
        find.textContaining("Lerato Dube's chat is suspended"),
        findsOneWidget,
      );
      await _close(tester);
    });
  });

  group('admin Chat Moderation', () {
    Map<String, dynamic> caseJson(int id, String status, {String? appeal}) => {
      'userId': id,
      'role': 'student',
      'name': 'Student $id',
      'status': status,
      'reason': 'a phone number',
      'flaggedText': 'call me on 082 555 123$id',
      'otherName': 'Thabo Nkosi',
      'flaggedAt': '2026-11-18T08:00:00Z',
      'flagCount': 1,
      'appeal': appeal,
    };

    late List<http.Request> requests;
    AdminChatModerationService service(List<Map<String, dynamic>> cases) {
      requests = [];
      return AdminChatModerationService(
        tokenProvider: () async => 't',
        client: MockClient((r) async {
          requests.add(r);
          if (r.method == 'GET') {
            return http.Response(jsonEncode({'cases': cases}), 200);
          }
          final id = int.parse(r.url.pathSegments[2]);
          final lift = (jsonDecode(r.body) as Map)['decision'] == 'lift';
          return http.Response(
            jsonEncode({'case': caseJson(id, lift ? 'lifted' : 'upheld')}),
            200,
          );
        }),
      );
    }

    testWidgets('shows the blocked message and explanation; restore works',
        (tester) async {
      await _pump(
        tester,
        AdminChatModerationScreen(
          service: service([
            caseJson(7, 'appealed', appeal: 'It was my school number.'),
            caseJson(8, 'lifted'),
          ]),
        ),
      );
      expect(find.text('Student 7'), findsOneWidget);
      expect(find.text('call me on 082 555 1237'), findsOneWidget);
      expect(find.text('It was my school number.'), findsOneWidget);
      expect(find.text('Student 8'), findsNothing); // decided: hidden
      expect(find.text('1 open'), findsOneWidget);

      await tester.tap(find.text('Restore chat'));
      await tester.pumpAndSettle();
      final decision = requests.firstWhere((r) => r.method == 'POST');
      expect(decision.url.path, '/admin/chat-moderation/7/decision');
      expect(jsonDecode(decision.body), {'decision': 'lift'});
    });

    testWidgets('keeping a suspension asks for the reason', (tester) async {
      await _pump(
        tester,
        AdminChatModerationScreen(service: service([caseJson(7, 'suspended')])),
      );
      await tester.tap(find.text('Keep suspended'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Sharing numbers is not allowed.',
      );
      await tester.pump(); // the button enables once there is a reason
      await tester.tap(find.widgetWithText(FilledButton, 'Keep suspended'));
      await tester.pumpAndSettle();
      final decision = requests.firstWhere((r) => r.method == 'POST');
      expect(jsonDecode(decision.body), {
        'decision': 'keep',
        'note': 'Sharing numbers is not allowed.',
      });
    });
  });
}
