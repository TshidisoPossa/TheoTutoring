import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/env.dart';

//Database connection
MySQLConnection? _connection;

/// Opens an isolated connection for work that owns a transaction.
Future<MySQLConnection> createIndependentConnection() async {
  final connection = await MySQLConnection.createConnection(
    host: env['DB_HOST'] ?? '127.0.0.1',
    port: int.parse(env['DB_PORT'] ?? '3306'),
    userName: env['DB_USER'] ?? 'root',
    password: env['DB_PASSWORD'] ?? '',
    databaseName: env['DB_NAME'] ?? 'theotutoring',
    secure: true,
  );
  await connection.connect();
  return connection;
}

Future<MySQLConnection> getConnection() async {
  if (_connection != null && _connection!.connected) {
    return _connection!;
  }

  // Each developer sets DB_USER, DB_PASSWORD etc. in their own .env file.
  // Never commit passwords.
  _connection = await MySQLConnection.createConnection(
    host: env['DB_HOST'] ?? '127.0.0.1',
    port: int.parse(env['DB_PORT'] ?? '3306'),
    userName: env['DB_USER'] ?? 'root',
    password: env['DB_PASSWORD'] ?? '',
    databaseName: env['DB_NAME'] ?? 'theotutoring',
    secure: true, // Use SSL/TLS for secure connection
  );

  await _connection!.connect();
  print('✅ Connected to MySQL');
  return _connection!;
}
