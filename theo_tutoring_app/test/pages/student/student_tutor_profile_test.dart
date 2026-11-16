import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Student/student_bottom_nav.dart';
import 'package:theo_tutoring_app/Pages/Student/student_chats.dart';
import 'package:theo_tutoring_app/Pages/Student/student_tutor_profile.dart';
import 'package:theo_tutoring_app/models/tutor.dart';
import 'package:theo_tutoring_app/services/student_chat_service.dart';
import 'package:theo_tutoring_app/services/tutor_search_api.dart';

Tutor _tutor({List<TutorSubject>? subjects, double? rating = 4.5}) => Tutor(
  tutorId: 7,
  // Differs from tutorId so the chat test proves which ID is used.
  userId: 42,
  name: 'Theophilus Nkhabu',
  profilePhoto: null,
  bio: 'Engineering tutor.',
  experience: '3-5',
  subjects:
      subjects ??
      const [TutorSubject(subjectId: 3, subjectName: 'Mathematics')],
  hourlyRate: 100,
  averageRating: rating,
  reviewCount: 24,
  qualification: 'BSc Engineering',
);

Map<String, dynamic> _json(
  Tutor tutor, {
  bool availableNow = true,
  int reviews = 3,
}) => {
  'tutorId': tutor.tutorId,
  'userId': tutor.userId,
  'name': tutor.name,
  'profilePhoto': null,
  'bio': tutor.bio,
  'experience': tutor.experience,
  'qualification': tutor.qualification,
  'hourlyRate': tutor.hourlyRate,
  'averageRating': tutor.averageRating,
  'reviewCount': tutor.reviewCount,
  'subjects': [
    for (final subject in tutor.subjects)
      {'subjectId': subject.subjectId, 'subjectName': subject.subjectName},
  ],
  'availableNow': availableNow,
  'qualifications': [
    {'degree': 'BSc Engineering', 'institution': 'University of Pretoria'},
    {'degree': 'MSc Mathematics', 'institution': 'University of Cape Town'},
  ],
  'availability': [
    {'day': 'Monday', 'startTime': '08:00', 'endTime': '15:00'},
    {'day': 'Wednesday', 'startTime': '10:00', 'endTime': '12:00'},
  ],
  'reviews': [
    for (var i = 0; i < reviews; i++)
      {
        'reviewId': i + 1,
        'studentName': ['Lerato M.', 'Sipho K.', 'Ayanda N.'][i % 3],
        'rating': 5,
        'comment': 'Great session $i.',
        'createdAt': '2026-10-01T10:00:00',
      },
  ],
};

Future<void> _pump(
  WidgetTester tester,
  Tutor tutor, {
  http.Response? response,
  StudentChatService? chatService,
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = TutorSearchApi(
    client: MockClient(
      (_) async => response ?? http.Response(jsonEncode(_json(tutor)), 200),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: StudentTutorProfilePage(
        tutor: tutor,
        api: api,
        chatService: chatService,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the tutor profile from GET /tutors/{id}', (tester) async {
    await _pump(tester, _tutor());

    expect(find.text('Tutor Profile'), findsOneWidget);
    expect(find.text('Theophilus Nkhabu'), findsOneWidget);
    expect(find.text('(24 reviews)'), findsOneWidget);
    expect(find.text('Available Now'), findsOneWidget);
    expect(find.text('Engineering tutor.'), findsOneWidget);
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Experience: 3–5 years'), findsOneWidget);
    expect(find.text('R100.00 per session'), findsOneWidget);
    expect(find.text('University of Pretoria'), findsOneWidget);
    expect(find.text('MSc Mathematics'), findsOneWidget);
    expect(find.text('Tap a day to see time slots'), findsOneWidget);
    expect(find.text('Lerato M.'), findsOneWidget);
    expect(find.text('Sipho K.'), findsOneWidget);
    expect(find.text('Ayanda N.'), findsNothing); // only two until See all
    expect(find.text('See all 3 reviews'), findsOneWidget);
    expect(find.text('Book a Session'), findsOneWidget);
    expect(find.text('Message Tutor'), findsOneWidget);
    expect(find.byType(StudentBottomNav), findsOneWidget);
  });

  testWidgets('See all shows every review', (tester) async {
    await _pump(tester, _tutor());
    await tester.tap(find.text('See all 3 reviews'));
    await tester.pump();
    expect(find.text('Ayanda N.'), findsOneWidget);
    expect(find.text('Show fewer reviews'), findsOneWidget);
  });

  testWidgets('tapping a day shows its time slots', (tester) async {
    await _pump(tester, _tutor());
    await tester.tap(find.text('Mon'));
    await tester.pump();
    expect(find.text('Monday 08:00 – 15:00'), findsOneWidget);

    await tester.tap(find.text('Tue'));
    await tester.pump();
    expect(find.text('Not available on Tuesday.'), findsOneWidget);
  });

  testWidgets('tutor who is not using the app shows Offline', (tester) async {
    final tutor = _tutor();
    await _pump(
      tester,
      tutor,
      response: http.Response(
        jsonEncode(_json(tutor, availableNow: false, reviews: 0)),
        200,
      ),
    );
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Available Now'), findsNothing);
    expect(
      find.text('No reviews yet. Reviews appear after completed sessions.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed load keeps the basics and offers Retry', (
    tester,
  ) async {
    await _pump(tester, _tutor(), response: http.Response('{}', 500));
    expect(find.text('Theophilus Nkhabu'), findsOneWidget);
    expect(find.text('Engineering tutor.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'Message Tutor opens the chat with this tutor, and back returns',
    (tester) async {
      final chatRequests = <http.Request>[];
      final chatService = StudentChatService(
        client: MockClient((request) async {
          chatRequests.add(request);
          // A new conversation: no messages yet.
          return http.Response('[]', 200);
        }),
        tokenProvider: () async => 'tok',
      );
      await _pump(tester, _tutor(), chatService: chatService);

      await tester.tap(find.text('Message Tutor'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
      expect(chat.contact.userId, 42); // the tutor's User ID, not TutorID 7
      expect(chat.contact.name, 'Theophilus Nkhabu');
      expect(chat.contact.initials, 'TN');
      expect(chat.contact.lastMessage, '');
      expect(chat.contact.unreadCount, 0);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Theophilus Nkhabu'),
        ),
        findsOneWidget,
      );
      expect(chatRequests.single.method, 'GET');
      expect(
        chatRequests.single.url.path,
        endsWith('/student/conversations/42/messages'),
      );
      expect(chatRequests.single.headers['Authorization'], 'Bearer tok');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text('Tutor Profile'), findsOneWidget);
      expect(find.text('Message Tutor'), findsOneWidget);
    },
  );

  testWidgets('the first message from the profile goes to the tutor User ID', (
    tester,
  ) async {
    final chatRequests = <http.Request>[];
    final chatService = StudentChatService(
      client: MockClient((request) async {
        chatRequests.add(request);
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // The stored message, shaped like StudentChatMessage.fromJson reads.
          return http.Response(
            jsonEncode({
              'messageId': '10-${body['clientMessageId']}',
              'seq': 1,
              'senderId': 10,
              'receiverId': 42,
              'messageText': body['messageText'],
              'sentAt': '2026-11-13T09:00:00Z',
              'isRead': false,
              'isOutgoing': true,
              'bookingId': null,
            }),
            201,
          );
        }
        // A new conversation: no messages yet.
        return http.Response('[]', 200);
      }),
      tokenProvider: () async => 'tok',
    );
    await _pump(tester, _tutor(), chatService: chatService);

    await tester.tap(find.text('Message Tutor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello, are you free?');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    final post = chatRequests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, endsWith('/student/conversations/42/messages'));
    expect(
      chatRequests.where((r) => r.url.path.contains('/conversations/7/')),
      isEmpty,
    );
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['messageText'], 'Hello, are you free?');
    expect(body['receiverId'], 42);
    expect(body['clientMessageId'], isA<String>());
    expect(body['clientMessageId'] as String, isNotEmpty);

    expect(find.text('Hello, are you free?'), findsOneWidget);
    expect(find.text('Sending...'), findsNothing);
    expect(find.textContaining('Not sent'), findsNothing);
  });

  testWidgets('Message Tutor does not guess when the User ID is missing', (
    tester,
  ) async {
    final tutor = Tutor(
      tutorId: 7,
      name: 'Theophilus Nkhabu',
      profilePhoto: null,
      bio: 'Engineering tutor.',
      experience: '3-5',
      subjects: const [TutorSubject(subjectId: 3, subjectName: 'Mathematics')],
      hourlyRate: 100,
      averageRating: 4.5,
      reviewCount: 24,
    );
    await _pump(tester, tutor);
    await tester.tap(find.text('Message Tutor'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(
      find.text('Messaging is not available for this tutor right now.'),
      findsOneWidget,
    );
  });

  testWidgets('the menu reports the tutor with a reason', (tester) async {
    await _pump(tester, _tutor());
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report tutor'));
    await tester.pumpAndSettle();
    expect(find.text('Report Theophilus Nkhabu?'), findsOneWidget);
    expect(find.text('What went wrong?'), findsOneWidget);
  });

  testWidgets('single-subject tutor books directly with selected state', (
    tester,
  ) async {
    await _pump(tester, _tutor());
    await tester.tap(find.text('Book a Session'));
    await tester.pumpAndSettle();

    expect(find.text('Lesson'), findsOneWidget);
    expect(find.text('Theophilus Nkhabu'), findsOneWidget);
    expect(find.textContaining('Mathematics'), findsOneWidget);
    expect(find.textContaining('R100.00'), findsOneWidget);
  });

  testWidgets('multi-subject tutor asks for the subject first', (tester) async {
    await _pump(
      tester,
      _tutor(
        subjects: const [
          TutorSubject(subjectId: 3, subjectName: 'Mathematics'),
          TutorSubject(subjectId: 4, subjectName: 'Physics'),
        ],
      ),
    );
    await tester.tap(find.text('Book a Session'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a subject'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Physics'));
    await tester.pumpAndSettle();
    expect(find.text('Lesson'), findsOneWidget);
    expect(find.textContaining('Physics'), findsOneWidget);
  });

  testWidgets('no subjects disables booking; no rating is explained', (
    tester,
  ) async {
    await _pump(tester, _tutor(subjects: const [], rating: null));

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Book a Session'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('No subjects listed.'), findsOneWidget);
  });

  for (final (label, tab) in [
    ('Home', 0),
    ('Lessons', 1),
    ('Chat', 2),
    ('Profile', 3),
  ]) {
    testWidgets('$label in the bottom nav returns to the dashboard tab', (
      tester,
    ) async {
      addTearDown(() => studentTabRequest.value = null);
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = TutorSearchApi(
        client: MockClient(
          (_) async => http.Response(jsonEncode(_json(_tutor())), 200),
        ),
      );
      // The tutor profile opened on top of a stand-in dashboard
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        StudentTutorProfilePage(tutor: _tutor(), api: api),
                  ),
                ),
                child: const Text('root'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('root'));
      await tester.pumpAndSettle();
      expect(find.byType(StudentTutorProfilePage), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(StudentBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StudentTutorProfilePage), findsNothing);
      expect(find.text('root'), findsOneWidget);
      expect(studentTabRequest.value, tab);
      expect(find.textContaining('will be connected soon'), findsNothing);
    });
  }

  test('timeAgo words review dates', () {
    final now = DateTime(2026, 10, 23, 12);
    expect(timeAgo(DateTime(2026, 10, 9, 12), now: now), '2 weeks ago');
    expect(timeAgo(DateTime(2026, 9, 20, 12), now: now), '1 month ago');
    expect(timeAgo(DateTime(2026, 10, 22, 12), now: now), '1 day ago');
    expect(timeAgo(null, now: now), '');
  });

  test('experienceLabel matches tutor registration', () {
    expect(experienceLabel('0-1'), 'Less than 1 year');
    expect(experienceLabel('5+'), '5+ years');
  });
}
