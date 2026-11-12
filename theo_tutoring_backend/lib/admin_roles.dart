import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';

// ignore_for_file: public_member_api_docs

class AdminRoleValidation implements Exception {
  const AdminRoleValidation(this.message);
  final String message;
}

class AdminRoleNotFound implements Exception {}

class AdminRoleConflict implements Exception {
  const AdminRoleConflict(this.message);
  final String message;
}

typedef AdminRoleRepositoryFactory = AdminRoleRepository Function();

// ignore: one_member_abstracts
abstract interface class AdminRoleRepository {
  Future<Map<String, Object?>> changeRole({
    required int targetAdminId,
    required String newRole,
    required String reason,
    required AdminIdentity actor,
  });
}

class MySqlAdminRoleRepository implements AdminRoleRepository {
  MySqlAdminRoleRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final Future<MySQLConnection> Function() _connectionFactory;

  @override
  Future<Map<String, Object?>> changeRole({
    required int targetAdminId,
    required String newRole,
    required String reason,
    required AdminIdentity actor,
  }) async {
    final connection = await _connectionFactory();
    try {
      return await connection.transactional((transaction) async {
        // Serializes role mutations so concurrent requests cannot both remove
        // the final Super Admin.
        await transaction.execute(
          'SELECT AdminID FROM admin ORDER BY AdminID FOR UPDATE',
        );
        final target = await transaction.execute(
          'SELECT RoleKey FROM admin WHERE AdminID = :id LIMIT 1',
          {'id': targetAdminId},
        );
        if (target.rows.isEmpty) throw AdminRoleNotFound();
        final previousRole = target.rows.first.str('RoleKey') ?? '';
        if (!isKnownAdminRole(previousRole)) {
          throw const AdminRoleConflict(
            'The target account has an unknown role.',
          );
        }
        if (previousRole == newRole) {
          throw const AdminRoleConflict(
            'The administrator already has this role.',
          );
        }
        if (previousRole == 'super_admin' && newRole != 'super_admin') {
          final count = await transaction.execute(
            "SELECT COUNT(*) AS total FROM admin WHERE RoleKey = 'super_admin'",
          );
          final total = int.tryParse(count.rows.first.str('total') ?? '') ?? 0;
          if (total <= 1) {
            throw const AdminRoleConflict(
              'The last Super Admin cannot be demoted.',
            );
          }
        }

        await transaction.execute(
          'UPDATE admin SET RoleKey = :role WHERE AdminID = :id',
          {'role': newRole, 'id': targetAdminId},
        );
        await transaction.execute(
          '''
          INSERT INTO adminrolechangeaudit
            (ActorAdminID, TargetAdminID, PreviousRoleKey, NewRoleKey,
             Reason, ChangedAtUtc)
          VALUES (:actorId, :targetId, :previousRole, :newRole, :reason,
                  UTC_TIMESTAMP(6))
          ''',
          {
            'actorId': actor.id,
            'targetId': targetAdminId,
            'previousRole': previousRole,
            'newRole': newRole,
            'reason': reason,
          },
        );
        return {
          'adminId': targetAdminId,
          'previousRole': previousRole,
          'role': newRole,
        };
      });
    } finally {
      if (connection.connected) await connection.close();
    }
  }
}
