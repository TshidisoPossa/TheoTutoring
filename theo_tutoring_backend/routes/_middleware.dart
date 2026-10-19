import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/database.dart';

Handler middleware(Handler handler) {
  return (context) async {
    final conn = await getConnection();
    return handler.use(provider<MySQLConnection>((_) => conn)).call(context);
  };
}
