import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';

// Admin account management: list Admin accounts and create new ones.
// The initial password is passed straight to Firebase Authentication and is
// never stored, logged or returned by this backend.
// ignore_for_file: public_member_api_docs

class AdminUserValidation implements Exception {
  const AdminUserValidation(this.message);
  final String message;
}

class AdminUserConflict implements Exception {
  const AdminUserConflict(this.message);
  final String message;
}

/// Firebase account creation is not configured (no service account).
class AdminAccountSetupUnavailable implements Exception {
  const AdminAccountSetupUnavailable();
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// A validated "create administrator" request.
class NewAdminAccount {
  const NewAdminAccount({
    required this.name,
    required this.email,
    required this.password,
    required this.roleKey,
  });

  factory NewAdminAccount.fromJson(Map<String, dynamic> body) {
    final name = body['name'];
    if (name is! String || name.trim().length < 2 || name.trim().length > 100) {
      throw const AdminUserValidation('Name must be 2 to 100 characters.');
    }
    final email = body['email'];
    if (email is! String ||
        email.trim().length > 150 ||
        !_emailPattern.hasMatch(email.trim())) {
      throw const AdminUserValidation('A valid email address is required.');
    }
    final password = body['password'];
    if (password is! String || password.length < 8 || password.length > 128) {
      throw const AdminUserValidation(
        'The initial password must be 8 to 128 characters.',
      );
    }
    final role = body['role'];
    if (role is! String || !isKnownAdminRole(role.trim())) {
      throw const AdminUserValidation('A recognized role is required.');
    }
    return NewAdminAccount(
      name: name.trim(),
      email: email.trim().toLowerCase(),
      password: password,
      roleKey: role.trim(),
    );
  }

  final String name;
  final String email;
  final String password;
  final String roleKey;
}

typedef AdminUsersRepositoryFactory = AdminUsersRepository Function();
typedef AdminAccountProvisionerFactory = AdminAccountProvisioner Function();

abstract interface class AdminUsersRepository {
  Future<List<Map<String, Object?>>> listAdmins();
  Future<bool> emailInUse(String email);

  /// Inserts the User and Admin rows together; returns the new AdminID.
  Future<int> insertAdmin({
    required String firebaseUid,
    required String name,
    required String email,
    required String roleKey,
  });
}

/// Creates and removes Firebase Authentication accounts.
abstract interface class AdminAccountProvisioner {
  /// Returns the new account's Firebase UID.
  Future<String> createAccount({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> deleteAccount(String uid);
}

/// Creates the Firebase account first, then the MySQL rows. If the database
/// step fails, the Firebase account is deleted again so no half-created login
/// is left behind.
Future<Map<String, Object?>> createAdminAccount(
  NewAdminAccount account, {
  required AdminUsersRepository repository,
  required AdminAccountProvisioner provisioner,
}) async {
  if (await repository.emailInUse(account.email)) {
    throw const AdminUserConflict('An account with this email already exists.');
  }

  final uid = await provisioner.createAccount(
    email: account.email,
    password: account.password,
    displayName: account.name,
  );

  final int adminId;
  try {
    adminId = await repository.insertAdmin(
      firebaseUid: uid,
      name: account.name,
      email: account.email,
      roleKey: account.roleKey,
    );
  } catch (error) {
    try {
      await provisioner.deleteAccount(uid);
    } catch (_) {
      stderr.writeln(
        'Admin account rollback failed; remove Firebase user $uid manually.',
      );
    }
    if (error is MySQLServerException && error.errorCode == 1062) {
      throw const AdminUserConflict(
        'An account with this email already exists.',
      );
    }
    rethrow;
  }

  return {
    'adminId': adminId,
    'name': account.name,
    'email': account.email,
    'role': account.roleKey,
    'accountStatus': 'Active',
  };
}

class MySqlAdminUsersRepository implements AdminUsersRepository {
  MySqlAdminUsersRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final Future<MySQLConnection> Function() _connectionFactory;

  @override
  Future<List<Map<String, Object?>>> listAdmins() async {
    final connection = await _connectionFactory();
    try {
      final result = await connection.execute('''
        SELECT a.AdminID, a.RoleKey, u.Name, u.Email, u.AccountStatus,
               u.Created_at
        FROM Admin a
        INNER JOIN `User` u ON u.UserId = a.UserId
        ORDER BY u.Name, a.AdminID
      ''');
      return [
        for (final row in result.rows)
          {
            'adminId': int.parse(row.reqStr('AdminID')),
            'name': row.str('Name'),
            'email': row.str('Email'),
            'role': row.str('RoleKey'),
            'accountStatus': row.str('AccountStatus'),
            'createdAt': row.str('Created_at'),
          },
      ];
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  @override
  Future<bool> emailInUse(String email) async {
    final connection = await _connectionFactory();
    try {
      final result = await connection.execute(
        'SELECT 1 FROM `User` WHERE Email = :email LIMIT 1',
        {'email': email},
      );
      return result.rows.isNotEmpty;
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  @override
  Future<int> insertAdmin({
    required String firebaseUid,
    required String name,
    required String email,
    required String roleKey,
  }) async {
    final connection = await _connectionFactory();
    try {
      return await connection.transactional((transaction) async {
        final user = await transaction.execute(
          '''
          INSERT INTO `User`
            (FirebaseUid, Name, PhoneNum, Email, Role, AccountStatus)
          VALUES (:uid, :name, '', :email, 'admin', 'Active')
          ''',
          {'uid': firebaseUid, 'name': name, 'email': email},
        );
        final admin = await transaction.execute(
          'INSERT INTO Admin (UserId, RoleKey) VALUES (:userId, :role)',
          {'userId': user.lastInsertID.toInt(), 'role': roleKey},
        );
        return admin.lastInsertID.toInt();
      });
    } finally {
      if (connection.connected) await connection.close();
    }
  }
}

/// Firebase Authentication accounts via the Identity Toolkit REST API, signed
/// in with the backend's Firebase service account.
class FirebaseAccountProvisioner implements AdminAccountProvisioner {
  FirebaseAccountProvisioner({
    FirebaseAdmin Function()? firebaseAdmin,
    http.Client? client,
  }) : _firebaseAdmin = firebaseAdmin ?? (() => FirebaseAdmin.instance),
       _client = client ?? http.Client();

  final FirebaseAdmin Function() _firebaseAdmin;
  final http.Client _client;

  static const _base = 'https://identitytoolkit.googleapis.com/v1/projects';

  Future<(FirebaseAdmin, String)> _signIn() async {
    try {
      final admin = _firebaseAdmin();
      return (admin, await admin.accessToken());
    } on FirebaseAdminException {
      throw const AdminAccountSetupUnavailable();
    }
  }

  @override
  Future<String> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final (admin, token) = await _signIn();
    final response = await _client.post(
      Uri.parse('$_base/${admin.projectId}/accounts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'displayName': displayName,
      }),
    );
    final body = _decode(response.body);
    if (response.statusCode == 200 && body['localId'] is String) {
      return body['localId'] as String;
    }
    final code = (body['error'] as Map?)?['message']?.toString() ?? '';
    if (code.startsWith('EMAIL_EXISTS')) {
      throw const AdminUserConflict(
        'An account with this email already exists.',
      );
    }
    if (code.startsWith('INVALID_EMAIL')) {
      throw const AdminUserValidation('A valid email address is required.');
    }
    if (code.startsWith('WEAK_PASSWORD')) {
      throw const AdminUserValidation('The initial password is too weak.');
    }
    throw StateError(
      'Firebase account creation failed (${response.statusCode}).',
    );
  }

  @override
  Future<void> deleteAccount(String uid) async {
    final (admin, token) = await _signIn();
    final response = await _client.post(
      Uri.parse('$_base/${admin.projectId}/accounts:delete'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'localId': uid}),
    );
    if (response.statusCode != 200) {
      throw StateError('Firebase account deletion failed.');
    }
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}
