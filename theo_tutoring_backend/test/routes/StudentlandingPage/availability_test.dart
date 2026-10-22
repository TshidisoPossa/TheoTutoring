import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_availability.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/StudentlandingPage/availability.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _FakeRepository implements BookingAvailabilityRepository {
  _FakeRepository(this.snapshot);

  final AvailabilitySnapshot? snapshot;
  AvailabilityRequest? receivedRequest;

  @override
  Future<AvailabilitySnapshot?> load(AvailabilityRequest request) async {
    receivedRequest = request;
    return snapshot;
  }
}

class _ErrorRepository implements BookingAvailabilityRepository {
  @override
  Future<AvailabilitySnapshot?> load(AvailabilityRequest request) =>
      Future.error(Exception('database detail'));
}

class _UnavailableRepository implements BookingAvailabilityRepository {
  @override
  Future<AvailabilitySnapshot?> load(AvailabilityRequest request) =>
      Future.error(const BookingAvailabilityUnavailable());
}

class _ScheduledRecord {
  const _ScheduledRecord({
    required this.interval,
    required this.tutorId,
    required this.studentId,
    this.status = 'Confirmed',
    this.expiresAtUtc,
  });

  final LessonInterval interval;
  final int tutorId;
  final int studentId;
  final String status;
  final DateTime? expiresAtUtc;
}

class _SchedulingFakeRepository implements BookingAvailabilityRepository {
  _SchedulingFakeRepository(this.records);

  final List<_ScheduledRecord> records;

  @override
  Future<AvailabilitySnapshot?> load(AvailabilityRequest request) async {
    final busy = records
        .where((record) {
          if (record.interval.date.daysUntil(request.from) > 0 ||
              record.interval.date.daysUntil(request.through) < 0) {
            return false;
          }
          if (record.status == 'Confirmed') {
            return record.tutorId == request.tutorId ||
                record.studentId == request.studentId;
          }
          return record.status == 'Active' &&
              record.expiresAtUtc != null &&
              record.expiresAtUtc!.isAfter(request.nowUtc) &&
              (record.tutorId == request.tutorId ||
                  record.studentId == request.studentId);
        })
        .map((record) => record.interval)
        .toList();

    return AvailabilitySnapshot(
      weeklyAvailability: const [
        WeeklyAvailability(
          weekday: DateTime.monday,
          startMinutes: 4 * 60,
          endMinutes: 10 * 60,
        ),
      ],
      busyIntervals: busy,
      platformRate: '250.00',
    );
  }
}

void main() {
  const now = '2026-10-19T00:52:00Z';
  final nowUtc = DateTime.parse(now);
  late RequestContext context;
  late Request request;

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.get);
    when(
      () => request.uri,
    ).thenReturn(
      Uri.parse(
        '/StudentlandingPage/availability?tutorId=6&subjectId=12&from=2026-10-19&through=2026-10-20',
      ),
    );
    when(() => request.headers).thenReturn({'Authorization': 'Bearer token'});
  });

  group('GET /StudentlandingPage/availability', () {
    test('returns slots, timezone, and the configured rate', () async {
      final repository = _FakeRepository(
        AvailabilitySnapshot(
          weeklyAvailability: const [
            WeeklyAvailability(
              weekday: DateTime.monday,
              startMinutes: 4 * 60,
              endMinutes: 8 * 60,
            ),
          ],
          busyIntervals: [
            LessonInterval(
              date: BookingDate(2026, 10, 19),
              startMinutes: 6 * 60,
              endMinutes: 7 * 60,
            ),
          ],
          platformRate: '250.00',
        ),
      );

      final response = await route.handleAvailability(
        context,
        repositoryFactory: () async => repository,
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(repository.receivedRequest?.studentId, 19);
      expect(repository.receivedRequest?.tutorId, 6);
      expect(repository.receivedRequest?.subjectId, 12);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['timezone'], 'Africa/Johannesburg');
      expect(body['hourlyRate'], '250.00');
      expect(body['slots'], [
        {'date': '2026-10-19', 'startTime': '05:00', 'endTime': '06:00'},
        {'date': '2026-10-19', 'startTime': '07:00', 'endTime': '08:00'},
      ]);
    });

    for (final query in [
      'tutorId=0&from=2026-10-19&through=2026-10-20',
      'tutorId=abc&subjectId=12&from=2026-10-19&through=2026-10-20',
      'tutorId=6&subjectId=0&from=2026-10-19&through=2026-10-20',
      'tutorId=6&subjectId=abc&from=2026-10-19&through=2026-10-20',
      'tutorId=6&from=2026-10-19&through=2026-10-20',
      'tutorId=6&subjectId=12&from=2026-02-30&through=2026-10-20',
      'tutorId=6&subjectId=12&from=2026-10-20&through=2026-10-19',
      'tutorId=6&subjectId=12&from=2026-10-19&through=2027-01-19',
      'tutorId=6&subjectId=12&tutorId=7&from=2026-10-19&through=2026-10-20',
      'tutorId=6&subjectId=12&from=2026-10-19&through=2026-10-20&studentId=19',
      'tutorId=6&subjectId=12&from=2026-10-19&through=2026-10-20&extra=x',
    ]) {
      test('rejects malformed query: $query', () async {
        when(() => request.uri).thenReturn(
          Uri.parse('/StudentlandingPage/availability?$query'),
        );
        var identityResolved = false;

        final response = await route.handleAvailability(
          context,
          studentIdResolver: (_) async {
            identityResolved = true;
            return 19;
          },
          clock: () => nowUtc,
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect(identityResolved, isFalse);
      });
    }

    test('returns 404 for a tutor who is not eligible for search', () async {
      final response = await route.handleAvailability(
        context,
        repositoryFactory: () async => _FakeRepository(null),
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('returns 404 when the subject is not linked to the tutor', () async {
      final response = await route.handleAvailability(
        context,
        repositoryFactory: () async => _FakeRepository(null),
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('rejects invalid authenticated student identities', () async {
      final response = await route.handleAvailability(
        context,
        studentIdResolver: (_) => throw const route.StudentAccountException(
          HttpStatus.forbidden,
          'An active student account is required.',
        ),
        clock: () => nowUtc,
      );

      expect(response.statusCode, HttpStatus.forbidden);
    });

    test('rejects invalid Firebase tokens', () async {
      final response = await route.handleAvailability(
        context,
        studentIdResolver: (_) =>
            throw const AuthTokenException('Invalid sign-in token.'),
        clock: () => nowUtc,
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test(
      'blocks cross-tutor student bookings and active holds, but ignores '
      'expired holds',
      () async {
        final day = BookingDate(2026, 10, 19);
        final response = await route.handleAvailability(
          context,
          repositoryFactory: () async => _SchedulingFakeRepository([
            _ScheduledRecord(
              interval: LessonInterval(
                date: day,
                startMinutes: 6 * 60,
                endMinutes: 7 * 60,
              ),
              tutorId: 99,
              studentId: 19,
            ),
            _ScheduledRecord(
              interval: LessonInterval(
                date: day,
                startMinutes: 7 * 60,
                endMinutes: 8 * 60,
              ),
              tutorId: 6,
              studentId: 88,
              status: 'Active',
              expiresAtUtc: nowUtc.add(const Duration(minutes: 5)),
            ),
            _ScheduledRecord(
              interval: LessonInterval(
                date: day,
                startMinutes: 8 * 60,
                endMinutes: 9 * 60,
              ),
              tutorId: 6,
              studentId: 88,
              status: 'Active',
              expiresAtUtc: nowUtc.subtract(const Duration(seconds: 1)),
            ),
            _ScheduledRecord(
              interval: LessonInterval(
                date: day,
                startMinutes: 9 * 60,
                endMinutes: 10 * 60,
              ),
              tutorId: 99,
              studentId: 19,
              status: 'Active',
              expiresAtUtc: nowUtc.add(const Duration(minutes: 5)),
            ),
          ]),
          studentIdResolver: (_) async => 19,
          clock: () => nowUtc,
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        final slots = body['slots'] as List<dynamic>;
        expect(
          slots.map((slot) => (slot as Map<String, dynamic>)['startTime']),
          ['05:00', '08:00'],
        );
      },
    );

    test(
      'returns 503 when availability configuration is unavailable',
      () async {
        final response = await route.handleAvailability(
          context,
          repositoryFactory: () async => _UnavailableRepository(),
          studentIdResolver: (_) async => 19,
          clock: () => nowUtc,
        );

        expect(response.statusCode, HttpStatus.serviceUnavailable);
      },
    );

    test('does not leak repository errors', () async {
      final response = await route.handleAvailability(
        context,
        repositoryFactory: () async => _ErrorRepository(),
        studentIdResolver: (_) async => 19,
        clock: () => nowUtc,
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect((await response.body()).contains('database detail'), isFalse);
    });

    test('rejects non-GET methods', () async {
      when(() => request.method).thenReturn(HttpMethod.post);

      final response = await route.handleAvailability(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
