import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_chat_moderation.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/chat_moderation.dart';

// Chat moderation: the word filter, suspending a sender, their explanation
// and the admin's decision. The store is in memory.

class _MemoryStore implements ChatModerationStore {
  final records = <int, ChatModerationRecord>{};

  @override
  Future<ChatModerationRecord?> get(int userId) async => records[userId];

  @override
  Future<Map<int, ChatModerationRecord>> getMany(Iterable<int> ids) async => {
    for (final id in ids)
      if (records[id] case final r?) id: r,
  };

  @override
  Future<void> save(ChatModerationRecord record) async =>
      records[record.userId] = record;

  @override
  Future<List<ChatModerationRecord>> all() async => records.values.toList();
}

class _MockContext extends Mock implements RequestContext {}

RequestContext _request(String method, [Object? body]) {
  final context = _MockContext();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/admin/chat-moderation'),
      headers: {'Authorization': 'Bearer test'},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  return context;
}

Future<AdminIdentity> _admin(String? _) async =>
    const AdminIdentity(id: 1, name: 'Admin Thandi');

Future<AdminIdentity> _financeAdmin(String? _) async =>
    const AdminIdentity(id: 2, name: 'Finance', roleKey: 'finance_admin');

final _now = DateTime.utc(2026, 11, 18, 10);

Future<ChatModerationRecord> _flag(_MemoryStore store, [int userId = 7]) =>
    flagChatMessage(
      store,
      userId: userId,
      role: 'student',
      name: 'Lerato',
      otherUserId: 9,
      otherName: 'Thabo',
      text: 'call me on 082 555 1234',
      verdict: screenChatMessage('call me on 082 555 1234')!,
      now: _now,
    );

void main() {
  group('screenChatMessage blocks', () {
    for (final (text, category) in [
      ('email me: lerato.dube@gmail.com', 'email'),
      ('lerato @ gmail . com', 'email'),
      ('lerato at gmail dot com', 'email'),
      ('my cell 082 555 1234', 'phone'),
      ('+27 (82) 555-1234', 'phone'),
      ('0825551234', 'phone'),
      ('zero eight two five five five one two three four', 'phone'),
      ('add me on WhatsApp', 'contact_app'),
      ('find me on Instagram!', 'contact_app'),
      ("Let's just do it outside the app", 'off_platform'),
      ('you can pay me directly next time', 'off_platform'),
      ('you are an idiot', 'abusive'),
    ]) {
      test('"$text" ($category)', () {
        expect(screenChatMessage(text)?.category, category);
      });
    }
  });

  group('screenChatMessage allows', () {
    for (final text in [
      'See you on Thursday at 14:00',
      'Chapter 3, questions 1 to 12 please',
      'The lesson costs R185.00',
      'Booking #1665 on 2026-11-20',
      'I scored 85% on the test!',
      'What is 3.14159 times 2?',
      'Please bring your textbook',
      'Is the assignment due on the 20th?',
    ]) {
      test('"$text"', () => expect(screenChatMessage(text), isNull));
    }
  });

  group('suspension', () {
    test('a blocked message suspends the sender and is kept for admins',
        () async {
      final store = _MemoryStore();
      final record = await _flag(store);
      expect(record.isSuspended, isTrue);
      expect(record.status, ChatModerationStatus.suspended);
      expect(record.category, 'phone');
      expect(record.flaggedText, 'call me on 082 555 1234');
      expect(record.canAppeal, isTrue);
      expect(store.records[7], isNotNull);
    });

    test('each blocked message is counted', () async {
      final store = _MemoryStore();
      await _flag(store);
      final second = await _flag(store);
      expect(second.flagCount, 2);
    });

    test('the user can explain once; then it waits for an admin', () async {
      final store = _MemoryStore();
      await _flag(store);
      final appealed = await appealChatSuspension(
        store,
        userId: 7,
        explanation: 'It was my school office number, sorry.',
        now: _now,
      );
      expect(appealed.status, ChatModerationStatus.appealed);
      expect(appealed.isSuspended, isTrue); // still cannot send
      expect(appealed.appeal, 'It was my school office number, sorry.');
      await expectLater(
        appealChatSuspension(
          store,
          userId: 7,
          explanation: 'Another explanation here',
          now: _now,
        ),
        throwsA(isA<ChatModerationException>()),
      );
    });

    test('a too-short explanation is refused', () async {
      final store = _MemoryStore();
      await _flag(store);
      await expectLater(
        appealChatSuspension(store, userId: 7, explanation: 'sorry', now: _now),
        throwsA(
          isA<ChatModerationException>().having(
            (e) => e.statusCode,
            'status',
            400,
          ),
        ),
      );
    });

    test('a user who was never flagged cannot appeal', () async {
      await expectLater(
        appealChatSuspension(
          _MemoryStore(),
          userId: 7,
          explanation: 'Nothing happened here',
          now: _now,
        ),
        throwsA(isA<ChatModerationException>()),
      );
    });
  });

  group('admin decision', () {
    test('lift restores chat; keep leaves it suspended', () async {
      final store = _MemoryStore();
      await _flag(store, 7);
      await _flag(store, 8);
      final lifted = await decideChatSuspension(
        store,
        userId: 7,
        lift: true,
        adminName: 'Admin',
        now: _now,
      );
      expect(lifted.isSuspended, isFalse);
      final kept = await decideChatSuspension(
        store,
        userId: 8,
        lift: false,
        adminName: 'Admin',
        note: 'Sharing numbers is not allowed.',
        now: _now,
      );
      expect(kept.isSuspended, isTrue);
      expect(kept.status, ChatModerationStatus.upheld);
      expect(kept.canAppeal, isTrue); // they may explain again
    });

    test('the list route puts explained cases first', () async {
      final store = _MemoryStore();
      await _flag(store, 7);
      await _flag(store, 8);
      await appealChatSuspension(
        store,
        userId: 8,
        explanation: 'It was a mistake, sorry about that.',
        now: _now,
      );
      final response = await handleAdminChatModerationList(
        _request('GET'),
        adminResolver: _admin,
        storeFactory: () async => store,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['open'], 2);
      final cases = body['cases'] as List;
      expect((cases.first as Map)['userId'], 8);
      expect((cases.first as Map)['appeal'], contains('mistake'));
      expect((cases.first as Map)['flaggedText'], 'call me on 082 555 1234');
    });

    test('the decision route lifts and tells the user', () async {
      final store = _MemoryStore();
      await _flag(store, 7);
      final told = <ChatModerationRecord>[];
      final response = await handleAdminChatModerationDecision(
        _request('POST', {'decision': 'lift'}),
        '7',
        adminResolver: _admin,
        storeFactory: () async => store,
        notifyUser: (r) async => told.add(r),
        clock: () => _now,
      );
      expect(response.statusCode, 200);
      expect(store.records[7]!.status, ChatModerationStatus.lifted);
      expect(store.records[7]!.decidedBy, 'Admin Thandi');
      expect(told.single.status, ChatModerationStatus.lifted);
    });

    test('keeping a suspension needs a reason', () async {
      final store = _MemoryStore();
      await _flag(store, 7);
      final response = await handleAdminChatModerationDecision(
        _request('POST', {'decision': 'keep'}),
        '7',
        adminResolver: _admin,
        storeFactory: () async => store,
        notifyUser: (_) async {},
      );
      expect(response.statusCode, 400);
      expect(store.records[7]!.status, ChatModerationStatus.suspended);
    });

    test('an admin without report permissions cannot decide', () async {
      final store = _MemoryStore();
      await _flag(store, 7);
      final response = await handleAdminChatModerationDecision(
        _request('POST', {'decision': 'lift'}),
        '7',
        adminResolver: _financeAdmin,
        storeFactory: () async => store,
        notifyUser: (_) async {},
      );
      expect(response.statusCode, 403);
      expect(store.records[7]!.isSuspended, isTrue);
    });
  });
}
