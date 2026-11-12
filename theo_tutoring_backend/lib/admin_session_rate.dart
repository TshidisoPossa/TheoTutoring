import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';

// ignore_for_file: public_member_api_docs

class AdminSessionRateValidation implements Exception {
  const AdminSessionRateValidation(this.message);
  final String message;
}

class AdminSessionRateNotConfigured implements Exception {}

typedef AdminSessionRateRepositoryFactory =
    AdminSessionRateRepository Function();

abstract interface class AdminSessionRateRepository {
  Future<Map<String, Object?>> fetch(String adminName);
  Future<Map<String, Object?>> update(String amount, AdminIdentity admin);
}

class MySqlAdminSessionRateRepository implements AdminSessionRateRepository {
  MySqlAdminSessionRateRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final Future<MySQLConnection> Function() _connectionFactory;

  @override
  Future<Map<String, Object?>> fetch(String adminName) async {
    final connection = await _connectionFactory();
    try {
      final result = await connection.execute(_select);
      return _response(
        result.rows.isEmpty ? null : result.rows.first,
        adminName,
      );
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  @override
  Future<Map<String, Object?>> update(
    String amount,
    AdminIdentity admin,
  ) async {
    final connection = await _connectionFactory();
    try {
      final result = await connection.execute(
        'SELECT SettingsID FROM platformsettings WHERE SettingsID = 1 LIMIT 1',
      );
      if (result.rows.isEmpty) throw AdminSessionRateNotConfigured();
      await connection.execute(
        '''
        UPDATE platformsettings
           SET TutoringRate = :amount, UpdatedByAdminID = :adminId,
               UpdatedAt = CURRENT_TIMESTAMP
           WHERE SettingsID = 1''',
        {'amount': amount, 'adminId': admin.id},
      );
      final updated = await connection.execute(_select);
      return _response(
        updated.rows.isEmpty ? null : updated.rows.first,
        admin.name,
      );
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  static const _select = '''
    SELECT settings.SettingsID, settings.TutoringRate,
           settings.UpdatedAt, actor.Name AS SetBy
    FROM platformsettings settings
    LEFT JOIN admin admin ON admin.AdminID = settings.UpdatedByAdminID
    LEFT JOIN `user` actor ON actor.UserId = admin.UserId
    WHERE settings.SettingsID = 1
    LIMIT 1
  ''';

  Map<String, Object?> _response(ResultSetRow? row, String adminName) => {
    'adminName': adminName,
    'current': row == null
        ? null
        : {
            'id': row.str('SettingsID'),
            'amount': row.str('TutoringRate'),
            'effectiveFrom': row.str('UpdatedAt'),
            'setBy': row.str('SetBy'),
          },
    // The existing schema stores only the current rate, not rate history.
    'history': <Object?>[],
  };
}
