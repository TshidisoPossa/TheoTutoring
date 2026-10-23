import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_roles.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/roles/[adminId].dart' as route;

class _MockContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _FakeRoleRepository implements AdminRoleRepository {
  int calls = 0;
  int? targetId;
  String? newRole;
  AdminIdentity? actor;

  @override
  Future<Map<String, Object?>> changeRole({
    required int targetAdminId,
    required String newRole,
    required String reason,
    required AdminIdentity actor,
  }) async {
    calls++;
    targetId = targetAdminId;
    this.newRole = newRole;
    this.actor = actor;
    return {
      'adminId': targetAdminId,
      'previousRole': 'admin',
      'role': newRole,
    };
  }
}

void main() {
  late RequestContext context;
  late Request request;
  late _FakeRoleRepository repository;
  late Map<String, dynamic> body;

  setUp(() {
    context = _MockContext();
    request = _MockRequest();
    repository = _FakeRoleRepository();
    body = {'role': 'application_reviewer', 'reason': 'Assigned for review'};
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.put);
    when(() => request.uri).thenReturn(Uri.parse('/admin/roles/5'));
    when(() => request.headers).thenReturn({'Authorization': 'Bearer token'});
    when(() => request.json()).thenAnswer((_) async => body);
  });

  test('Super Admin role change records the verified actor', () async {
    final response = await route.handleAdminRoleChange(
      context,
      targetAdminId: 5,
      adminResolver: (_) async => const AdminIdentity(
        id: 1,
        name: 'Root',
        roleKey: 'super_admin',
      ),
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(await response.body()), {
      'adminId': 5,
      'previousRole': 'admin',
      'role': 'application_reviewer',
    });
    expect(repository.calls, 1);
    expect(repository.targetId, 5);
    expect(repository.newRole, 'application_reviewer');
    expect(repository.actor?.id, 1);
  });

  test('standard Admin cannot change roles or call the repository', () async {
    final response = await route.handleAdminRoleChange(
      context,
      targetAdminId: 5,
      adminResolver: (_) async => const AdminIdentity(id: 1, name: 'Admin'),
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.forbidden);
    expect(repository.calls, 0);
  });

  test('rejects unknown role keys before persistence', () async {
    body['role'] = 'root_everything';
    final response = await route.handleAdminRoleChange(
      context,
      targetAdminId: 5,
      adminResolver: (_) async => const AdminIdentity(
        id: 1,
        name: 'Root',
        roleKey: 'super_admin',
      ),
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.badRequest);
    expect(repository.calls, 0);
  });

  test('rejects missing audit reason before persistence', () async {
    body.remove('reason');
    final response = await route.handleAdminRoleChange(
      context,
      targetAdminId: 5,
      adminResolver: (_) async => const AdminIdentity(
        id: 1,
        name: 'Root',
        roleKey: 'super_admin',
      ),
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.badRequest);
    expect(repository.calls, 0);
  });

  test('invalid authentication and non-admin identity are rejected', () async {
    final invalid = await route.handleAdminRoleChange(
      context,
      targetAdminId: 5,
      adminResolver: (_) => throw const AuthTokenException('Invalid token.'),
      repositoryFactory: () => repository,
    );
    final denied = await route.handleAdminRoleChange(
      context,
      targetAdminId: 5,
      adminResolver: (_) => throw const AdminAccessDenied('Admin required.'),
      repositoryFactory: () => repository,
    );
    expect(invalid.statusCode, HttpStatus.unauthorized);
    expect(denied.statusCode, HttpStatus.forbidden);
    expect(repository.calls, 0);
  });
}
