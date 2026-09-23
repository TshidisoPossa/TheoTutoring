import 'package:mysql_client/mysql_client.dart';

class DatabaseConnection {
  static MySQLConnectionPool? _pool;

  static MySQLConnectionPool get pool {
    _pool ??= MySQLConnectionPool(
      host: '127.0.0.1',
      port: 3310,
      userName: 'root',
      password: '',
      databaseName: 'theo_tutoring_db',
      maxConnections: 10,
      secure: false,
    );
    return _pool!;
  }
}
