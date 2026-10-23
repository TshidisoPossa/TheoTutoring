import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_users.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/users/index.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _FakeRepository implements AdminUsersRepository {
  bool emailTaken = false;
  Exception? insertError;
  final inserted = <Map<String, String>>[];

  @override
  Future<List<Map<String, Object?>>> listAdmins() async => [
    {
      'adminId': 1,
      'name': 'Admin Tester',
      'email': 'admin@example.com',
      'role': 'super_admin',
      'accountStatus': 'Active',
      'createdAt': '2026-10-20 10:00:00',
    },
  ];

  @override
  Future<bool> emailInUse(String email) async => emailTaken;

  @override
  Future<int> insertAdmin({
    required String firebaseUid,
    required String name,
    required String email,
    required String roleKey,
  }) async {
    if (insertError != null) throw insertError!;
    inserted.add({
      'uid': firebaseUid,
      'name': name,
      'email': email,
      'role': roleKey,
    });
    return 9;
  }
}

class _FakeProvisioner implements AdminAccountProvisioner {
  final created = <Map<String, String>>[];
  final deleted = <String>[];

  @override
  Future<String> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    created.add({'email': email, 'password': password, 'name': displayName});
    return 'firebase-uid-123';
  }

  @override
  Future<void> deleteAccount(String uid) async => deleted.add(uid);
}

const _superAdmin = AdminIdentity(
  id: 1,
  name: 'Admin Tester',
  roleKey: 'super_admin',
);

const _validBody = {
  'name': '  New Admin ',
  'email': ' New.Admin@Example.com ',
  'password': 'initial-pass-123',
  'role': 'finance_admin',
};

void main() {
  late RequestContext context;
  late Request request;
  late _FakeRepository repository;
  late _FakeProvisioner provisioner;

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    repository = _FakeRepository();
    provisioner = _FakeProvisioner();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.get);
    when(() => request.headers).thenReturn({'Authorization': 'Bearer test'});
  });

  Future<Response> send({
    HttpMethod method = HttpMethod.get,
    Object? body,
    AdminResolver? resolver,
  }) {
    when(() => request.method).thenReturn(method);
    when(() => request.json()).thenAnswer((_) async => body);
    return route.handleAdminUsers(
      context,
      adminResolver: resolver ?? (_) async => _superAdmin,
      repositoryFactory: () => repository,
      provisionerFactory: () => provisioner,
    );
  }

  Future<Map<String, dynamic>> json(Response response) async =>
      jsonDecode(await response.body()) as Map<String, dynamic>;

  group('authorization', () {
    test('returns 401 without a valid Firebase token', () async {
      final response = await send(
        resolver: (_) => throw const AuthTokenException('Invalid token.'),
      );
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('a standard admin role cannot list or create admins', () async {
      for (final method in [HttpMethod.get, HttpMethod.post]) {
        final response = await send(
          method: method,
          body: _validBody,
          // The default role is the standard 'admin' role.
          resolver: (_) async => const AdminIdentity(id: 2, name: 'Standard'),
        );
        expect(response.statusCode, HttpStatus.forbidden);
      }
      expect(provisioner.created, isEmpty);
      expect(repository.inserted, isEmpty);
    });

    test('rejects unsupported methods', () async {
      final response = await send(method: HttpMethod.delete);
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  test('GET lists admins and the existing role keys', () async {
    final response = await send();
    expect(response.statusCode, HttpStatus.ok);
    final body = await json(response);
    expect(body['adminName'], 'Admin Tester');
    expect(body['roles'], adminRolePermissions.keys.toList());
    expect(body['rolePermissions'], {
      for (final entry in adminRolePermissions.entries)
        entry.key: entry.value.toList()..sort(),
    });
    final admins = (body['admins'] as List).cast<Map<String, dynamic>>();
    expect(admins.single['email'], 'admin@example.com');
  });

  group('POST creates an admin', () {
    test('creates the Firebase login, then the User/Admin rows', () async {
      final response = await send(method: HttpMethod.post, body: _validBody);

      expect(response.statusCode, HttpStatus.created);
      expect(provisioner.created.single, {
        'email': 'new.admin@example.com',
        'password': 'initial-pass-123',
        'name': 'New Admin',
      });
      expect(repository.inserted.single, {
        'uid': 'firebase-uid-123',
        'name': 'New Admin',
        'email': 'new.admin@example.com',
        'role': 'finance_admin',
      });
      final raw = await response.body();
      expect(raw, isNot(contains('initial-pass-123')));
      expect(jsonDecode(raw), {
        'adminId': 9,
        'name': 'New Admin',
        'email': 'new.admin@example.com',
        'role': 'finance_admin',
        'accountStatus': 'Active',
      });
    });

    test('validates every field before creating anything', () async {
      for (final invalid in [
        {..._validBody, 'name': 'A'},
        {..._validBody, 'email': 'not-an-email'},
        {..._validBody, 'password': 'short'},
        {..._validBody, 'role': 'owner'},
        {..._validBody}..remove('role'),
      ]) {
        final response = await send(method: HttpMethod.post, body: invalid);
        expect(response.statusCode, HttpStatus.badRequest, reason: '$invalid');
      }
      final response = await send(method: HttpMethod.post, body: 'text');
      expect(response.statusCode, HttpStatus.badRequest);
      expect(provisioner.created, isEmpty);
    });

    test('rejects a registered email without touching Firebase', () async {
      repository.emailTaken = true;
      final response = await send(method: HttpMethod.post, body: _validBody);
      expect(response.statusCode, HttpStatus.conflict);
      expect(provisioner.created, isEmpty);
    });

    test('deletes the Firebase login when the DB insert fails', () async {
      repository.insertError = const MySQLServerException('Deadlock', 1213);
      final response = await send(method: HttpMethod.post, body: _validBody);

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(provisioner.deleted, ['firebase-uid-123']);
      expect(await response.body(), isNot(contains('initial-pass-123')));
    });

    test('a duplicate-email race is a rolled-back conflict', () async {
      repository.insertError = const MySQLServerException('Duplicate', 1062);
      final response = await send(method: HttpMethod.post, body: _validBody);

      expect(response.statusCode, HttpStatus.conflict);
      expect(provisioner.deleted, ['firebase-uid-123']);
    });

    test('returns 503 when no Firebase service account is set', () async {
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.json()).thenAnswer((_) async => _validBody);
      final response = await route.handleAdminUsers(
        context,
        adminResolver: (_) async => _superAdmin,
        repositoryFactory: () => repository,
        provisionerFactory: () => FirebaseAccountProvisioner(
          firebaseAdmin: () => throw const FirebaseAdminException('not set'),
        ),
      );
      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(repository.inserted, isEmpty);
    });
  });
}
