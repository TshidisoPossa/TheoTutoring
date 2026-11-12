import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_subjects.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

class _Ctx extends Mock implements RequestContext {}

class _Req extends Mock implements Request {}

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

/// A fake MySQL connection that records every SQL statement it is given.
/// Each query returns one row whose columns all read [count]; inserts report
/// ID 9.
_MockConnection _recordingConnection(
  List<String> statements, {
  String count = '0',
}) {
  final row = _MockRow();
  when(() => row.colByName(any())).thenReturn(count);
  final result = _MockResult();
  when(() => result.rows).thenReturn([row]);
  when(() => result.lastInsertID).thenReturn(BigInt.from(9));

  final connection = _MockConnection();
  when(() => connection.execute(any(), any())).thenAnswer((invocation) async {
    statements.add(invocation.positionalArguments.first as String);
    return result;
  });
  // delete's callback returns nothing, so Dart infers transactional<Null>.
  // ignore: prefer_void_to_null
  when(() => connection.transactional<Null>(any())).thenAnswer((
    invocation,
  ) async {
    final callback =
        invocation.positionalArguments.single
            // ignore: prefer_void_to_null
            as FutureOr<Null> Function(MySQLConnection);
    await callback(connection);
  });
  when(() => connection.connected).thenReturn(true);
  when(connection.close).thenAnswer((_) async {});
  return connection;
}

/// The shared Aiven database is case-sensitive and stores these tables in
/// lowercase, so PascalCase names (as in schema.sql) would fail there.
final _pascalCaseTable = RegExp(
  r'\b(INTO|FROM|UPDATE|JOIN)\s+`?(Subjects|TutorSubjects|BookingPurchase|Booking)\b',
);

void _expectLowercaseTables(List<String> statements) {
  expect(statements, isNotEmpty);
  for (final sql in statements) {
    expect(sql, isNot(matches(_pascalCaseTable)), reason: sql);
  }
}

class _Repo implements SubjectsAdminRepository {
  Object? error;
  String? created;
  String? renamed;
  int? deleted;

  @override
  Future<Map<String, Object?>> create(String name) async {
    if (error != null) throw error!;
    created = name;
    return {'subjectId': 9, 'subjectName': name};
  }

  @override
  Future<Map<String, Object?>> rename(int id, String name) async {
    if (error != null) throw error!;
    renamed = name;
    return {'subjectId': id, 'subjectName': name};
  }

  @override
  Future<void> delete(int id) async {
    if (error != null) throw error!;
    deleted = id;
  }
}

AdminResolver _as(String role) =>
    (_) async => AdminIdentity(id: 1, name: 'Ada', roleKey: role);

RequestContext _ctx(HttpMethod method, {Object? body}) {
  final c = _Ctx();
  final r = _Req();
  when(() => c.request).thenReturn(r);
  when(() => r.method).thenReturn(method);
  when(() => r.headers).thenReturn({'Authorization': 'Bearer t'});
  when(r.json).thenAnswer((_) async {
    if (body == null) throw const FormatException('no body');
    return body;
  });
  return c;
}

Future<Response> _call(
  HttpMethod m,
  String? id, {
  Object? body,
  String role = 'super_admin',
  AdminResolver? resolver,
  required _Repo repo,
}) => handleAdminSubjects(
  _ctx(m, body: body),
  id,
  adminResolver: resolver ?? _as(role),
  repository: repo,
);

void main() {
  test('super_admin holds admin.subjects.manage; admin does not', () {
    expect(
      adminRolePermissions['super_admin'],
      contains('admin.subjects.manage'),
    );
    expect(
      adminRolePermissions['admin'] ?? {},
      isNot(contains('admin.subjects.manage')),
    );
  });

  test('invalid token is 401', () async {
    final repo = _Repo();
    final res = await _call(
      HttpMethod.post,
      null,
      body: {'subjectName': 'Math'},
      resolver: (_) async => throw const AuthTokenException('bad'),
      repo: repo,
    );
    expect(res.statusCode, HttpStatus.unauthorized);
    expect(repo.created, isNull);
  });

  for (final role in ['admin', 'finance_admin', 'support_admin']) {
    test('$role is 403 on every method', () async {
      final repo = _Repo();
      for (final (m, id) in [
        (HttpMethod.post, null),
        (HttpMethod.patch, '1'),
        (HttpMethod.delete, '1'),
      ]) {
        final res = await _call(
          m,
          id,
          body: {'subjectName': 'Math'},
          role: role,
          repo: repo,
        );
        expect(res.statusCode, HttpStatus.forbidden);
      }
      expect(repo.created ?? repo.renamed ?? repo.deleted, isNull);
    });
  }

  test('create trims the name and returns 201', () async {
    final repo = _Repo();
    final res = await _call(
      HttpMethod.post,
      null,
      body: {'subjectName': '  Physics '},
      repo: repo,
    );
    expect(res.statusCode, HttpStatus.created);
    expect(repo.created, 'Physics');
    expect(jsonDecode(await res.body())['subjectName'], 'Physics');
  });

  test('blank, over-100 and non-string names are 400', () async {
    final repo = _Repo();
    for (final n in ['   ', 'x' * 101, 5]) {
      final res = await _call(
        HttpMethod.post,
        null,
        body: {'subjectName': n},
        repo: repo,
      );
      expect(res.statusCode, HttpStatus.badRequest);
    }
    expect(repo.created, isNull);
  });

  test('missing body is 400', () async {
    final res = await _call(HttpMethod.post, null, repo: _Repo());
    expect(res.statusCode, HttpStatus.badRequest);
  });

  test('duplicate name is 409 on create and rename', () async {
    final repo = _Repo()..error = const SubjectNameTaken();
    expect(
      (await _call(
        HttpMethod.post,
        null,
        body: {'subjectName': 'Math'},
        repo: repo,
      )).statusCode,
      HttpStatus.conflict,
    );
    expect(
      (await _call(
        HttpMethod.patch,
        '2',
        body: {'subjectName': 'Math'},
        repo: repo,
      )).statusCode,
      HttpStatus.conflict,
    );
  });

  test('rename succeeds; unknown id is 404; bad id is 400', () async {
    final repo = _Repo();
    var res = await _call(
      HttpMethod.patch,
      '2',
      body: {'subjectName': 'Maths'},
      repo: repo,
    );
    expect(res.statusCode, HttpStatus.ok);
    expect(repo.renamed, 'Maths');
    res = await _call(
      HttpMethod.patch,
      'abc',
      body: {'subjectName': 'Maths'},
      repo: repo,
    );
    expect(res.statusCode, HttpStatus.badRequest);
    repo.error = const SubjectNotFound();
    res = await _call(
      HttpMethod.patch,
      '99',
      body: {'subjectName': 'Maths'},
      repo: repo,
    );
    expect(res.statusCode, HttpStatus.notFound);
  });

  test('delete succeeds; in use is 409; unknown is 404', () async {
    final repo = _Repo();
    var res = await _call(HttpMethod.delete, '3', repo: repo);
    expect(res.statusCode, HttpStatus.ok);
    expect(repo.deleted, 3);
    repo.error = const SubjectInUse();
    res = await _call(HttpMethod.delete, '3', repo: repo);
    expect(res.statusCode, HttpStatus.conflict);
    repo.error = const SubjectNotFound();
    res = await _call(HttpMethod.delete, '3', repo: repo);
    expect(res.statusCode, HttpStatus.notFound);
  });

  test('wrong method is 405', () async {
    expect(
      (await _call(HttpMethod.get, null, repo: _Repo())).statusCode,
      HttpStatus.methodNotAllowed,
    );
    expect(
      (await _call(HttpMethod.post, '1', repo: _Repo())).statusCode,
      HttpStatus.methodNotAllowed,
    );
  });

  group('MySqlSubjectsAdminRepository uses lowercase Aiven table names', () {
    test('create inserts into subjects', () async {
      final statements = <String>[];
      final repo = MySqlSubjectsAdminRepository(
        connectionFactory: () async => _recordingConnection(statements),
      );

      final created = await repo.create('Physics');

      expect(created, {'subjectId': 9, 'subjectName': 'Physics'});
      expect(statements, [
        'INSERT INTO subjects (subjectName) VALUES (:n)',
      ]);
      _expectLowercaseTables(statements);
    });

    test('rename checks and updates subjects', () async {
      final statements = <String>[];
      final repo = MySqlSubjectsAdminRepository(
        connectionFactory: () async => _recordingConnection(statements),
      );

      await repo.rename(4, 'Maths');

      expect(statements, [
        'SELECT 1 FROM subjects WHERE subjectId = :id',
        'UPDATE subjects SET subjectName = :n WHERE subjectId = :id',
      ]);
      _expectLowercaseTables(statements);
    });

    test('delete checks tutorsubjects, bookingpurchase and booking', () async {
      final statements = <String>[];
      final repo = MySqlSubjectsAdminRepository(
        connectionFactory: () async => _recordingConnection(statements),
      );

      await repo.delete(4);

      expect(statements, hasLength(3));
      expect(
        statements[0],
        'SELECT 1 FROM subjects WHERE subjectId = :id FOR UPDATE',
      );
      expect(statements[1], contains('FROM tutorsubjects WHERE SubjectID'));
      expect(statements[1], contains('FROM bookingpurchase WHERE SubjectID'));
      expect(statements[1], contains('FROM booking WHERE SubjectID'));
      expect(statements[2], 'DELETE FROM subjects WHERE subjectId = :id');
      _expectLowercaseTables(statements);
    });

    test('a subject still in use is not deleted', () async {
      final statements = <String>[];
      final repo = MySqlSubjectsAdminRepository(
        connectionFactory: () async =>
            _recordingConnection(statements, count: '2'),
      );

      await expectLater(repo.delete(4), throwsA(isA<SubjectInUse>()));

      expect(statements.where((sql) => sql.startsWith('DELETE')), isEmpty);
      _expectLowercaseTables(statements);
    });
  });

  group('MySqlSubjectsAdminRepository connection ownership', () {
    test('defaults to an independent connection, never the shared one', () {
      // Constructing the repository opens no connection.
      final repo = MySqlSubjectsAdminRepository();

      expect(
        identical(repo.connectionFactory, createIndependentConnection),
        isTrue,
      );
      expect(identical(repo.connectionFactory, getConnection), isFalse);
    });

    test('uses the injected factory: one new connection per operation, '
        'each closed once', () async {
      final statements = <String>[];
      final opened = <_MockConnection>[];
      final repo = MySqlSubjectsAdminRepository(
        connectionFactory: () async {
          final connection = _recordingConnection(statements);
          opened.add(connection);
          return connection;
        },
      );

      await repo.create('Physics');
      expect(opened, hasLength(1));
      await repo.rename(4, 'Maths');
      expect(opened, hasLength(2));
      await repo.delete(4);
      expect(opened, hasLength(3));

      // Three distinct connections, none reused between operations.
      expect((Set<Object>.identity()..addAll(opened)).length, 3);
      for (final connection in opened) {
        verify(connection.close).called(1);
      }
    });

    test('a connection that is no longer connected is not closed', () async {
      final opened = <_MockConnection>[];
      final repo = MySqlSubjectsAdminRepository(
        connectionFactory: () async {
          final connection = _recordingConnection(<String>[]);
          when(() => connection.connected).thenReturn(false);
          opened.add(connection);
          return connection;
        },
      );

      await repo.create('Physics');
      await repo.rename(4, 'Maths');
      await repo.delete(4);

      expect(opened, hasLength(3));
      for (final connection in opened) {
        verifyNever(connection.close);
      }
    });

    test('the connection is closed when an operation fails', () async {
      final duplicate = _recordingConnection(<String>[]);
      when(
        () => duplicate.execute(any(), any()),
      ).thenThrow(const MySQLServerException('Duplicate entry', 1062));
      await expectLater(
        MySqlSubjectsAdminRepository(
          connectionFactory: () async => duplicate,
        ).create('Physics'),
        throwsA(isA<SubjectNameTaken>()),
      );
      verify(duplicate.close).called(1);

      final inUse = _recordingConnection(<String>[], count: '1');
      await expectLater(
        MySqlSubjectsAdminRepository(
          connectionFactory: () async => inUse,
        ).delete(4),
        throwsA(isA<SubjectInUse>()),
      );
      verify(inUse.close).called(1);
    });
  });
}
