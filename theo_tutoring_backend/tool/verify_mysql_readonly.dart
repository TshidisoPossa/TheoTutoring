import 'dart:io';

import 'package:mysql_client/exception.dart';
import 'package:theo_tutoring_backend/database.dart';

Future<void> main() async {
  var stage = 'connection';
  try {
    final connection = await getConnection();
    stage = 'SELECT DATABASE()';
    final database = await connection.execute('SELECT DATABASE() AS db');
    stdout.writeln('Database: ${database.rows.first.assoc()['db']}');

    stage = 'SHOW COLUMNS FROM User';
    final columns = await connection.execute('SHOW COLUMNS FROM `User`');
    final userColumns = columns.rows.map((row) => row.assoc()).toList();
    final firebaseUid = userColumns.where(
      (column) => column['Field'] == 'FirebaseUid',
    );
    final password = userColumns.where(
      (column) => column['Field'] == 'Password',
    );

    stdout.writeln('FirebaseUid exists: ${firebaseUid.isNotEmpty}');
    stdout.writeln(
      'Password nullable: ${password.isNotEmpty && password.first['Null'] == 'YES'}',
    );
  } catch (error) {
    final code = error is MySQLServerException
        ? ', code ${error.errorCode}'
        : '';
    stderr.writeln('MySQL $stage failed (${error.runtimeType}$code).');
    exitCode = 1;
  }
}
