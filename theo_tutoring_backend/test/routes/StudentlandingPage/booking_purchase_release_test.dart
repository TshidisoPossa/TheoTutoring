import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_purchase.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/StudentlandingPage/booking-purchases/[purchaseId]/release.dart'
    as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

/// One purchase per id, owned by a student, in a status; release follows
/// the documented rules so the route's responses can be checked.
class _FakeReleaseRepository implements BookingPurchaseReleaseRepository {
  _FakeReleaseRepository(this.purchases);

  final Map<int, ({int studentId, String status})> purchases;
  final List<(int, int)> calls = [];
  Exception? error;

  @override
  Future<String> release(int studentId, int purchaseId) async {
    calls.add((studentId, purchaseId));
    if (error != null) throw error!;
    final purchase = purchases[purchaseId];
    if (purchase == null || purchase.studentId != studentId) {
      throw const BookingPurchaseNotFound();
    }
    switch (purchase.status) {
      case 'Cancelled' || 'Expired':
        return purchase.status;
      case 'Held':
        purchases[purchaseId] = (studentId: studentId, status: 'Cancelled');
        return 'Cancelled';
      default:
        throw const BookingPurchaseConflict(
          'purchase_not_releasable',
          'This reservation has been paid or is being paid.',
        );
    }
  }
}

void main() {
  late _MockRequestContext context;
  late _MockRequest request;

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.post);
    when(() => request.headers).thenReturn({'Authorization': 'Bearer token'});
  });

  Future<({int status, Map<String, dynamic> body})> send(
    _FakeReleaseRepository repository, {
    String id = '27',
    int studentId = 5,
  }) async {
    final response = await route.handleReleasePurchase(
      context,
      routePurchaseId: id,
      repositoryFactory: () async => repository,
      studentIdResolver: (_) async => studentId,
    );
    return (
      status: response.statusCode,
      body: jsonDecode(await response.body()) as Map<String, dynamic>,
    );
  }

  test("releases the student's own held purchase", () async {
    final repository = _FakeReleaseRepository({
      27: (studentId: 5, status: 'Held'),
    });
    final reply = await send(repository);
    expect(reply.status, HttpStatus.ok);
    expect(reply.body, {'purchaseId': 27, 'purchaseStatus': 'Cancelled'});
    expect(repository.calls, [(5, 27)]);
  });

  test('a retry, or an already expired purchase, is a success', () async {
    final repository = _FakeReleaseRepository({
      27: (studentId: 5, status: 'Held'),
      28: (studentId: 5, status: 'Expired'),
    });
    expect((await send(repository)).body['purchaseStatus'], 'Cancelled');
    final retry = await send(repository);
    expect(retry.status, HttpStatus.ok);
    expect(retry.body['purchaseStatus'], 'Cancelled');
    final expired = await send(repository, id: '28');
    expect(expired.status, HttpStatus.ok);
    expect(expired.body['purchaseStatus'], 'Expired');
  });

  test('a paid purchase cannot be released', () async {
    for (final status in ['Paid', 'PaymentPending', 'Refunded']) {
      final reply = await send(
        _FakeReleaseRepository({27: (studentId: 5, status: status)}),
      );
      expect(reply.status, HttpStatus.conflict, reason: status);
      expect(reply.body['code'], 'purchase_not_releasable');
    }
  });

  test("another student's purchase is not found", () async {
    final repository = _FakeReleaseRepository({
      27: (studentId: 6, status: 'Held'),
    });
    final reply = await send(repository);
    expect(reply.status, HttpStatus.notFound);
    expect(repository.purchases[27]?.status, 'Held'); // untouched
  });

  test('rejects other methods, bad ids and bad tokens', () async {
    final repository = _FakeReleaseRepository({});
    when(() => request.method).thenReturn(HttpMethod.get);
    expect((await send(repository)).status, HttpStatus.methodNotAllowed);
    when(() => request.method).thenReturn(HttpMethod.post);
    for (final id in ['0', '-1', 'abc', '99999999999']) {
      expect((await send(repository, id: id)).status, HttpStatus.badRequest);
    }
    expect(repository.calls, isEmpty);

    final response = await route.handleReleasePurchase(
      context,
      routePurchaseId: '27',
      repositoryFactory: () async => repository,
      studentIdResolver: (_) async =>
          throw const AuthTokenException('Invalid token.'),
    );
    expect(response.statusCode, HttpStatus.unauthorized);
    expect(repository.calls, isEmpty);
  });

  test('a database outage is reported as temporarily unavailable', () async {
    final repository = _FakeReleaseRepository({
      27: (studentId: 5, status: 'Held'),
    })..error = const BookingPurchaseServiceUnavailable();
    expect((await send(repository)).status, HttpStatus.serviceUnavailable);
  });
}
