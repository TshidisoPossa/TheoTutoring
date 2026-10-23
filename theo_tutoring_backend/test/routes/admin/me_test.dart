import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/me.dart' as admin_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

void main() {
  late RequestContext context;
  late Request request;

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.get);
    when(() => request.headers).thenReturn({'Authorization': 'Bearer test'});
  });

  test('returns the verified active administrator identity', () async {
    final response = await admin_route.handleAdminIdentity(
      context,
      adminResolver: (authorization) async {
        expect(authorization, 'Bearer test');
        return const AdminIdentity(id: 8, name: 'Admin Tester');
      },
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = jsonDecode(await response.body()) as Map<String, dynamic>;
    expect(body['adminId'], 8);
    expect(body['adminName'], 'Admin Tester');
    expect(body['adminRole'], 'admin');
    expect(body['permissions'], contains('admin.applications.review'));
    expect(body['permissions'], isNot(contains('admin.roles.manage')));
  });

  test('rejects unauthenticated and non-admin accounts', () async {
    final unauthenticated = await admin_route.handleAdminIdentity(
      context,
      adminResolver: (_) => throw const AuthTokenException('Sign in required.'),
    );
    final nonAdmin = await admin_route.handleAdminIdentity(
      context,
      adminResolver: (_) => throw const AdminAccessDenied(
        'Administrator access is required.',
      ),
    );

    expect(unauthenticated.statusCode, HttpStatus.unauthorized);
    expect(nonAdmin.statusCode, HttpStatus.forbidden);
  });

  test('rejects methods other than GET before resolving identity', () async {
    when(() => request.method).thenReturn(HttpMethod.post);
    var resolved = false;

    final response = await admin_route.handleAdminIdentity(
      context,
      adminResolver: (_) async {
        resolved = true;
        return const AdminIdentity(id: 8, name: 'Admin Tester');
      },
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
    expect(resolved, isFalse);
  });
}
