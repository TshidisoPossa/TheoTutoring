import 'package:mysql_client/mysql_client.dart';


MySQLConnection? _connection;

Future<MySQLConnection> getConnection() async {
  if (_connection != null && _connection!.connected) {
    return _connection!;
  }

  _connection = await MySQLConnection.createConnection(
    host: '127.0.0.1',
    port: 3306,
    userName: 'root',
    password: '',
    databaseName: 'theotutoring',
    secure: true, // Use SSL/TLS for secure connection
  );

  await _connection!.connect();
  print('✅ Connected to MySQL');
  return _connection!;
}