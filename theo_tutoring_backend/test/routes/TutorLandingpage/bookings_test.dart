import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/tutor_bookings.dart';
import 'package:theo_tutoring_backend/tutorlanding_session.dart';

import '../../../routes/TutorLandingpage/bookings.dart' as route;

class _MockContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _FakeRepository implements TutorBookingsRepository {
  _FakeRepository(this.byTutor);

  final Map<int, List<TutorBookingSummary>> byTutor;
  int? askedTutorId;
  String? askedStatus;
  int? askedLimit;

  @override
  Future<List<TutorBookingSummary>> listForTutor(
    int tutorId, {
    String? status,
    int limit = defaultTutorBookingsLimit,
  }) async {
    askedTutorId = tutorId;
    askedStatus = status;
    askedLimit = limit;
    return [
      for (final b in byTutor[tutorId] ?? const <TutorBookingSummary>[])
        if (status == null || b.status == status) b,
    ];
  }
}

TutorBookingSummary _booking(int id, String status) => TutorBookingSummary(
  bookingId: id,
  status: status,
  date: '2026-11-01',
  startTime: '10:00:00',
  endTime: '11:00:00',
  subjectId: 7,
  subject: 'Maths',
  studentName: 'Student $id',
  createdAt: '2026-10-20 09:00:00',
  purchaseId: 100 + id,
  lessonNumber: 1,
);

Future<(int, Map<String, dynamic>?)> _call({
  required TutorSession session,
  required TutorBookingsRepository repository,
  HttpMethod method = HttpMethod.get,
  String query = '',
  bool failRepository = false,
}) async {
  final context = _MockContext();
  final request = _MockRequest();
  when(() => context.request).thenReturn(request);
  when(() => request.method).thenReturn(method);
  when(() => request.uri).thenReturn(Uri.parse('/bookings$query'));
  when(() => context.read<TutorSession>()).thenReturn(session);
  final response = await route.handleTutorBookings(
    context,
    repositoryFactory: () async {
      if (failRepository) throw StateError('db down password=secret');
      return repository;
    },
  );
  final text = await response.body();
  return (
    response.statusCode,
    text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>,
  );
}

const _activeA = TutorSession('uid-a', 1, accountStatus: 'Active');
const _activeB = TutorSession('uid-b', 2, accountStatus: 'Active');

void main() {
  group('GET /TutorLandingpage/bookings', () {
    test("returns only the signed-in tutor's bookings", () async {
      final repo = _FakeRepository({
        1: [_booking(1, 'Confirmed')],
        2: [_booking(2, 'Confirmed'), _booking(3, 'Completed')],
      });

      final a = await _call(session: _activeA, repository: repo);
      expect(a.$1, 200);
      expect((a.$2!['bookings'] as List).map((b) => b['bookingId']), [1]);
      expect(repo.askedTutorId, 1);

      final b = await _call(session: _activeB, repository: repo);
      expect((b.$2!['bookings'] as List).map((x) => x['bookingId']), [2, 3]);
      expect(repo.askedTutorId, 2);
    });

    test('a tutor with no bookings gets an empty list', () async {
      final result = await _call(
        session: _activeA,
        repository: _FakeRepository({}),
      );
      expect(result.$1, 200);
      expect(result.$2, {'bookings': <Object?>[]});
    });

    test('exposes status and expected fields but no student contact', () async {
      final result = await _call(
        session: _activeA,
        repository: _FakeRepository({
          1: [_booking(1, 'Confirmed')],
        }),
      );
      final booking = (result.$2!['bookings'] as List).single as Map;
      expect(booking['status'], 'Confirmed');
      expect(booking['subject'], 'Maths');
      expect(booking['studentName'], 'Student 1');
      for (final key in ['email', 'phone', 'studentId']) {
        expect(booking.containsKey(key), isFalse, reason: key);
      }
    });

    test('filters by every valid status', () async {
      for (final status in tutorBookingStatuses) {
        final repo = _FakeRepository({
          1: [_booking(1, status), _booking(2, 'Confirmed')],
        });
        final result = await _call(
          session: _activeA,
          repository: repo,
          query: '?status=$status',
        );
        expect(result.$1, 200);
        expect(repo.askedStatus, status);
        expect(
          (result.$2!['bookings'] as List).every((b) => b['status'] == status),
          isTrue,
        );
      }
    });

    test('rejects unknown or mixed-case status and bad limits', () async {
      final repo = _FakeRepository({});
      for (final query in [
        '?status=paid',
        '?status=confirmed',
        '?status=Confirmed%27%20OR%201=1',
        '?limit=0',
        '?limit=101',
        '?limit=abc',
      ]) {
        final result = await _call(
          session: _activeA,
          repository: repo,
          query: query,
        );
        expect(result.$1, 400, reason: query);
      }
      expect(repo.askedTutorId, isNull);
    });

    test('applies the default and an explicit limit', () async {
      final repo = _FakeRepository({});
      await _call(session: _activeA, repository: repo);
      expect(repo.askedLimit, defaultTutorBookingsLimit);
      await _call(session: _activeA, repository: repo, query: '?limit=5');
      expect(repo.askedLimit, 5);
    });

    test(
      'non-Active sessions are refused without touching the repository',
      () async {
        for (final status in ['Pending', 'Incomplete', 'Rejected', '']) {
          final repo = _FakeRepository({
            1: [_booking(1, 'Confirmed')],
          });
          final result = await _call(
            session: TutorSession('uid-a', 1, accountStatus: status),
            repository: repo,
          );
          expect(result.$1, 403, reason: '$status');
          expect(repo.askedTutorId, isNull);
        }
      },
    );

    test('Active status is matched case-insensitively', () async {
      final result = await _call(
        session: const TutorSession('uid-a', 1, accountStatus: ' ACTIVE '),
        repository: _FakeRepository({}),
      );
      expect(result.$1, 200);
    });

    test('rejects non-GET methods', () async {
      for (final method in [
        HttpMethod.post,
        HttpMethod.put,
        HttpMethod.patch,
        HttpMethod.delete,
      ]) {
        final result = await _call(
          session: _activeA,
          repository: _FakeRepository({}),
          method: method,
        );
        expect(result.$1, 405);
      }
    });

    test('database failures return a generic 503 without details', () async {
      final result = await _call(
        session: _activeA,
        repository: _FakeRepository({}),
        failRepository: true,
      );
      expect(result.$1, 503);
      expect(jsonEncode(result.$2), isNot(contains('secret')));
    });
  });
}
