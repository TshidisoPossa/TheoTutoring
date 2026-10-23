import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';

void main() {
  test('fixed roles allow only their declared permissions', () {
    const reviewer = AdminIdentity(
      id: 2,
      name: 'Reviewer',
      roleKey: 'application_reviewer',
    );
    expect(
      () => requireAdminPermission(reviewer, 'admin.applications.review'),
      returnsNormally,
    );
    expect(
      () => requireAdminPermission(reviewer, 'admin.refunds.decide'),
      throwsA(isA<AdminPermissionDenied>()),
    );
  });

  test('unknown roles fail closed and receive no permissions', () {
    const unknown = AdminIdentity(
      id: 3,
      name: 'Unknown',
      roleKey: 'future_unreviewed_role',
    );
    expect(isKnownAdminRole(unknown.roleKey), isFalse);
    expect(unknown.permissions, isEmpty);
    expect(
      () => requireAdminPermission(unknown, 'admin.applications.read'),
      throwsA(isA<AdminPermissionDenied>()),
    );
  });

  test('Super Admin alone can manage roles', () {
    const standard = AdminIdentity(id: 1, name: 'Admin');
    const superAdmin = AdminIdentity(
      id: 4,
      name: 'Root',
      roleKey: 'super_admin',
    );
    expect(
      () => requireAdminPermission(standard, 'admin.roles.manage'),
      throwsA(isA<AdminPermissionDenied>()),
    );
    expect(
      () => requireAdminPermission(superAdmin, 'admin.roles.manage'),
      returnsNormally,
    );
  });
}
