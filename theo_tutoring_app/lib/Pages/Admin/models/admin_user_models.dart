// Backend contract (Dart Frog), both require `admin.users.manage`:
// GET  /admin/users -> { "adminName", "roles": ["super_admin", ...],
//                        "admins": [ { "adminId", "name", "email", "role",
//                                      "accountStatus", "createdAt" } ] }
// POST /admin/users   { "name", "email", "password", "role" } -> 201 admin

class AdminAccount {
  final int adminId;
  final String name;
  final String email;
  final String role;
  final String accountStatus;

  const AdminAccount({
    required this.adminId,
    required this.name,
    required this.email,
    required this.role,
    required this.accountStatus,
  });

  factory AdminAccount.fromJson(Map<String, dynamic> j) => AdminAccount(
    adminId: (j['adminId'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    role: (j['role'] ?? '').toString(),
    accountStatus: (j['accountStatus'] ?? '').toString(),
  );
}

class AdminUsersResult {
  final String adminName;

  /// Role keys from the backend's role/permission model, in its order.
  final List<String> roles;

  /// Each role's permission keys, exactly as the backend enforces them.
  final Map<String, List<String>> rolePermissions;
  final List<AdminAccount> admins;

  const AdminUsersResult({
    required this.adminName,
    required this.roles,
    required this.admins,
    this.rolePermissions = const {},
  });

  factory AdminUsersResult.fromJson(Map<String, dynamic> j) => AdminUsersResult(
    adminName: (j['adminName'] ?? '').toString(),
    roles: ((j['roles'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    rolePermissions: {
      for (final MapEntry(:key, :value)
          in ((j['rolePermissions'] as Map<String, dynamic>?) ?? const {})
              .entries)
        key: (value as List<dynamic>).map((e) => e.toString()).toList(),
    },
    admins: ((j['admins'] as List<dynamic>?) ?? const [])
        .map((e) => AdminAccount.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Plain-language names for the backend's permission keys, in display order.
const _permissionLabels = {
  'admin.dashboard.read': 'view the dashboard',
  'admin.applications.read': 'view tutor applications',
  'admin.applications.review': 'approve or reject applications',
  'admin.refunds.read': 'view refunds',
  'admin.refunds.decide': 'decide refunds',
  'admin.reports.read': 'view user reports',
  'admin.reports.resolve': 'resolve user reports',
  'admin.reviews.read': 'view reviews',
  'admin.finance.read': 'view finances',
  'admin.payouts.manage': 'manage payouts',
  'admin.settings.rate.read': 'view the session rate',
  'admin.settings.rate.write': 'change the session rate',
  'admin.monitor.read': 'monitor the platform',
  'admin.users.manage': 'manage administrator accounts',
  'admin.roles.manage': 'change administrator roles',
};

/// A short note on what [role] can do, built from its permission keys.
/// Returns null when the backend did not send that role's permissions.
String? adminRoleAccessNote(
  String role,
  Map<String, List<String>> rolePermissions,
) {
  final permissions = rolePermissions[role];
  if (permissions == null) return null;
  if (permissions.isEmpty) return 'This role has no Admin access.';

  final allPermissions = {for (final p in rolePermissions.values) ...p};
  if (permissions.toSet().containsAll(allPermissions)) {
    return 'Full access to every Admin area, including managing '
        'administrator accounts and roles.';
  }

  final labels = [
    for (final MapEntry(:key, :value) in _permissionLabels.entries)
      if (permissions.contains(key)) value,
    for (final key in permissions)
      if (!_permissionLabels.containsKey(key)) key,
  ];
  return 'Can ${labels.join(', ')}.';
}

/// "finance_admin" -> "Finance Admin".
String adminRoleLabel(String roleKey) => roleKey
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => part[0].toUpperCase() + part.substring(1))
    .join(' ');
