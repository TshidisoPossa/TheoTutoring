import 'dart:io';

import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/env.dart';
import 'package:theo_tutoring_backend/local_test_database.dart';

MySQLConnection? _connection;

/// A new, unopened connection using the settings from .env.
///
/// TLS is always on and the server certificate and hostname are verified.
/// When DB_SSL_CA is set (for example Aiven's ca.pem), only that CA is
/// trusted; otherwise the system's trusted roots are used.
///
/// With THEO_LOCAL_TEST_DB=1 (see local_test_database.dart) every
/// connection goes to the local `theotutoring_test` database instead and
/// DB_* is ignored; invalid local settings throw before connecting.
Future<MySQLConnection> _newConnection() {
  final local = LocalTestDatabase.resolve();
  if (local != null) return local.newConnection();
  final caPath = env['DB_SSL_CA']?.trim() ?? '';
  return MySQLConnection.createConnection(
    host: env['DB_HOST'] ?? '127.0.0.1',
    port: int.parse(env['DB_PORT'] ?? '3306'),
    userName: env['DB_USER'] ?? 'root',
    password: env['DB_PASSWORD'] ?? '',
    databaseName: env['DB_NAME'] ?? 'theotutoring',
    secure: true,
    securityContext: caPath.isEmpty
        ? null
        : (SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificates(caPath)),
  );
}

/// Opens an isolated connection for work that owns a transaction.
Future<MySQLConnection> createIndependentConnection() async {
  final connection = await _newConnection();
  await connection.connect();
  return connection;
}

Future<MySQLConnection> getConnection() async {
  if (_connection != null && _connection!.connected) {
    return _connection!;
  }

  // Each developer sets DB_USER, DB_PASSWORD etc. in their own .env file.
  // Never commit passwords.
  _connection = await _newConnection();

  await _connection!.connect();
  final local = LocalTestDatabase.resolve();
  print(
    local == null
        ? '✅ Connected to MySQL'
        : '✅ Connected to local test MySQL ${local.description}',
  );
  return _connection!;
}
