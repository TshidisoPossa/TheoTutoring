import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/database/database_connection.dart';

Future<Response> onRequest(RequestContext context) async {
  final pool = DatabaseConnection.pool;

  final result = await pool.execute(
    'SELECT * FROM users',
  ); // change table/columns here

  final students = result.rows.map((row) => row.assoc()).toList();

  return Response(
    body: jsonEncode(students),
    headers: {'Content-Type': 'application/json'},
  );
}
