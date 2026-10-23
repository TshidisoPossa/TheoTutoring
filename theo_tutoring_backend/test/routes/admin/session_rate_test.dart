import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_session_rate.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/session-rate.dart' as route;

class _MockContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _FakeRepository implements AdminSessionRateRepository {
  String? updatedAmount;
  AdminIdentity? updatedBy;
  bool notConfigured = false;

  @override
  Future<Map<String, Object?>> fetch(String adminName) async => {
    'adminName': adminName,
    'current': {'id': 1, 'amount': '350.00', 'setBy': 'Admin'},
    'history': <Object?>[],
  };

  @override
  Future<Map<String, Object?>> update(
    String amount,
    AdminIdentity admin,
  ) async {
    if (notConfigured) throw AdminSessionRateNotConfigured();
    updatedAmount = amount;
    updatedBy = admin;
    return {
      'adminName': admin.name,
      'current': {'id': 1, 'amount': amount, 'setBy': admin.name},
      'history': <Object?>[],
    };
  }
}

void main() {
  late RequestContext context;
  late Request request;
  late _FakeRepository repository;
  var method = HttpMethod.get;
  var body = '';

  setUp(() {
    context = _MockContext();
    request = _MockRequest();
    repository = _FakeRepository();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenAnswer((_) => method);
    when(() => request.headers).thenReturn({'Authorization': 'Bearer token'});
    when(() => request.body()).thenAnswer((_) async => body);
    method = HttpMethod.get;
    body = '';
  });

  Future<AdminIdentity> allowed(String? authorization) async {
    expect(authorization, 'Bearer token');
    return const AdminIdentity(id: 9, name: 'Verified Admin');
  }

  test('GET returns current settings and truthful empty history', () async {
    final response = await route.handleAdminSessionRate(
      context,
      adminResolver: allowed,
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(await response.body()), {
      'adminName': 'Verified Admin',
      'current': {'id': 1, 'amount': '350.00', 'setBy': 'Admin'},
      'history': <Object?>[],
    });
  });

  test(
    'PUT validates and attributes a rate update to verified admin',
    () async {
      method = HttpMethod.put;
      body = jsonEncode({'amount': '375.50'});
      final response = await route.handleAdminSessionRate(
        context,
        adminResolver: allowed,
        repositoryFactory: () => repository,
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(repository.updatedAmount, '375.50');
      expect(
        repository.updatedBy,
        const AdminIdentity(id: 9, name: 'Verified Admin'),
      );
    },
  );

  test('rejects invalid amount and does not update repository', () async {
    method = HttpMethod.put;
    body = jsonEncode({'amount': '0'});
    final response = await route.handleAdminSessionRate(
      context,
      adminResolver: allowed,
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.badRequest);
    expect(repository.updatedAmount, isNull);
  });

  test(
    'does not create missing settings with an invented commission',
    () async {
      method = HttpMethod.put;
      body = jsonEncode({'amount': '375.50'});
      repository.notConfigured = true;
      final response = await route.handleAdminSessionRate(
        context,
        adminResolver: allowed,
        repositoryFactory: () => repository,
      );
      expect(response.statusCode, HttpStatus.conflict);
      expect(repository.updatedAmount, isNull);
    },
  );

  test('distinguishes invalid identity and authenticated non-admin', () async {
    final invalid = await route.handleAdminSessionRate(
      context,
      adminResolver: (_) => throw const AuthTokenException('Invalid token.'),
      repositoryFactory: () => repository,
    );
    final denied = await route.handleAdminSessionRate(
      context,
      adminResolver: (_) => throw const AdminAccessDenied('Admin required.'),
      repositoryFactory: () => repository,
    );
    expect(invalid.statusCode, HttpStatus.unauthorized);
    expect(denied.statusCode, HttpStatus.forbidden);
  });
}
