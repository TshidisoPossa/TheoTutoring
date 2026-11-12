import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

class SubjectNotFound implements Exception {
  const SubjectNotFound();
}

class SubjectNameTaken implements Exception {
  const SubjectNameTaken();
}

class SubjectInUse implements Exception {
  const SubjectInUse();
}

abstract interface class SubjectsAdminRepository {
  Future<Map<String, Object?>> create(String name);
  Future<Map<String, Object?>> rename(int id, String name);
  Future<void> delete(int id);
}

bool _isDuplicate(Object e) => e is MySQLServerException && e.errorCode == 1062;

class MySqlSubjectsAdminRepository implements SubjectsAdminRepository {
  /// Each operation opens its own connection from [connectionFactory] (by
  /// default [createIndependentConnection]) and closes it afterwards, so the
  /// shared [getConnection] connection is never used or closed here.
  MySqlSubjectsAdminRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : connectionFactory = connectionFactory ?? createIndependentConnection;

  /// Where each operation gets the connection it owns and closes.
  final Future<MySQLConnection> Function() connectionFactory;

  @override
  Future<Map<String, Object?>> create(String name) async {
    final conn = await connectionFactory();
    try {
      final r = await conn.execute(
        'INSERT INTO subjects (subjectName) VALUES (:n)',
        {'n': name},
      );
      return {'subjectId': r.lastInsertID.toInt(), 'subjectName': name};
    } on Object catch (e) {
      if (_isDuplicate(e)) throw const SubjectNameTaken();
      rethrow;
    } finally {
      if (conn.connected) await conn.close();
    }
  }

  @override
  Future<Map<String, Object?>> rename(int id, String name) async {
    final conn = await connectionFactory();
    try {
      final exists = await conn.execute(
        'SELECT 1 FROM subjects WHERE subjectId = :id',
        {'id': id},
      );
      if (exists.rows.isEmpty) throw const SubjectNotFound();
      await conn.execute(
        'UPDATE subjects SET subjectName = :n WHERE subjectId = :id',
        {'n': name, 'id': id},
      );
      return {'subjectId': id, 'subjectName': name};
    } on Object catch (e) {
      if (_isDuplicate(e)) throw const SubjectNameTaken();
      rethrow;
    } finally {
      if (conn.connected) await conn.close();
    }
  }

  @override
  Future<void> delete(int id) async {
    final conn = await connectionFactory();
    try {
      await conn.transactional((tx) async {
        final found = await tx.execute(
          'SELECT 1 FROM subjects WHERE subjectId = :id FOR UPDATE',
          {'id': id},
        );
        if (found.rows.isEmpty) throw const SubjectNotFound();
        final used = await tx.execute(
          'SELECT '
          '(SELECT COUNT(*) FROM tutorsubjects WHERE SubjectID = :id) + '
          '(SELECT COUNT(*) FROM bookingpurchase WHERE SubjectID = :id) + '
          '(SELECT COUNT(*) FROM booking WHERE SubjectID = :id) AS n',
          {'id': id},
        );
        final n = int.tryParse(used.rows.first.str('n') ?? '') ?? 1;
        if (n > 0) throw const SubjectInUse();
        await tx.execute('DELETE FROM subjects WHERE subjectId = :id', {
          'id': id,
        });
      });
    } finally {
      if (conn.connected) await conn.close();
    }
  }
}

/// Handles POST /admin/subjects ([idParam] null) and PATCH/DELETE
/// /admin/subjects/{id}. Super Admin only (admin.subjects.manage).
Future<Response> handleAdminSubjects(
  RequestContext context,
  String? idParam, {
  AdminResolver? adminResolver,
  SubjectsAdminRepository? repository,
}) async {
  final method = context.request.method;
  final allowed = idParam == null
      ? {HttpMethod.post}
      : {HttpMethod.patch, HttpMethod.delete};
  if (!allowed.contains(method)) {
    return _json(HttpStatus.methodNotAllowed, 'Method not allowed.');
  }
  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.subjects.manage');

    final repo = repository ?? MySqlSubjectsAdminRepository();
    int? id;
    if (idParam != null) {
      id = int.tryParse(idParam);
      if (id == null || id < 1) return _json(400, 'Invalid subject id.');
      if (method == HttpMethod.delete) {
        await repo.delete(id);
        return Response.json(body: {'deleted': true, 'subjectId': id});
      }
    }
    final Object? body;
    try {
      body = await context.request.json();
    } on Object {
      return _json(400, 'A JSON body is required.');
    }
    final raw = body is Map ? body['subjectName'] : null;
    final name = raw is String ? raw.trim() : '';
    if (name.isEmpty || name.length > 100) {
      return _json(400, 'subjectName must be 1-100 characters.');
    }
    if (id == null) {
      return Response.json(
        statusCode: HttpStatus.created,
        body: await repo.create(name),
      );
    }
    return Response.json(body: await repo.rename(id, name));
  } on AuthTokenException catch (e) {
    return _json(HttpStatus.unauthorized, e.message);
  } on AdminAccessDenied catch (e) {
    return _json(HttpStatus.forbidden, e.message);
  } on SubjectNotFound {
    return _json(HttpStatus.notFound, 'Subject not found.');
  } on SubjectNameTaken {
    return _json(HttpStatus.conflict, 'A subject with that name exists.');
  } on SubjectInUse {
    return _json(
      HttpStatus.conflict,
      'Subject is in use by tutors or bookings and cannot be deleted.',
    );
  } catch (error) {
    stderr.writeln('Subject admin failed (${error.runtimeType}).');
    return _json(HttpStatus.internalServerError, 'The request failed.');
  }
}

Response _json(int status, String message) =>
    Response.json(statusCode: status, body: {'error': message});
