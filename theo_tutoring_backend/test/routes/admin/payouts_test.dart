import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_payouts.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/payouts/[payoutId]/approve.dart' as action_route;
import '../../../routes/admin/payouts/index.dart' as list_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

class _FakeRepository implements AdminPayoutsRepository {
  AdminPayoutQuery? query;
  String? action;
  int? payoutId;
  Exception? error;

  @override
  Future<Map<String, Object?>> list(AdminPayoutQuery query) async {
    this.query = query;
    if (error != null) throw error!;
    return {
      'total': 1,
      'page': query.page,
      'pageSize': query.pageSize,
      'summary': {'pendingCount': 1},
      'payouts': [
        {'payoutId': 5, 'status': 'pending', 'netAmount': 270.0},
      ],
    };
  }

  @override
  Future<void> approve(int payoutId, AdminIdentity admin) async {
    action = 'approve';
    this.payoutId = payoutId;
    if (error != null) throw error!;
  }

  @override
  Future<void> markPaid(int payoutId, AdminIdentity admin) async {
    action = 'mark-paid';
    this.payoutId = payoutId;
    if (error != null) throw error!;
  }
}

IResultSet _result(List<Map<String, String?>> rows, {BigInt? affectedRows}) {
  final resultRows = [
    for (final values in rows)
      () {
        final row = _MockRow();
        when(() => row.colByName(any())).thenAnswer(
          (invocation) =>
              values[invocation.positionalArguments.single as String],
        );
        return row;
      }(),
  ];
  final result = _MockResult();
  when(() => result.rows).thenReturn(resultRows);
  when(() => result.affectedRows).thenReturn(affectedRows ?? BigInt.zero);
  return result;
}

/// A connection whose transactional() runs the callback on itself and whose
/// execute() is answered by [answer]; every statement is recorded.
_MockConnection _connection(
  List<(String, Map<String, dynamic>?)> statements,
  IResultSet Function(String sql) answer,
) {
  final connection = _MockConnection();
  when(() => connection.connected).thenReturn(false);
  when(() => connection.execute(any(), any())).thenAnswer((invocation) async {
    final sql = invocation.positionalArguments.first as String;
    statements.add((
      sql,
      invocation.positionalArguments[1] as Map<String, dynamic>?,
    ));
    return answer(sql);
  });
  when(() => connection.transactional<void>(any())).thenAnswer((
    invocation,
  ) async {
    final callback =
        invocation.positionalArguments.single
            as FutureOr<void> Function(MySQLConnection);
    await callback(connection);
  });
  return connection;
}

const _admin = AdminIdentity(id: 7, name: 'Admin Tester');

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue((MySQLConnection _) async {});
  });

  late RequestContext context;
  late Request request;
  late _FakeRepository repository;

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    repository = _FakeRepository();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.get);
    when(() => request.uri).thenReturn(Uri.parse('/admin/payouts'));
    when(() => request.headers).thenReturn({'Authorization': 'Bearer test'});
  });

  Future<AdminIdentity> adminResolver(String? authorization) async {
    expect(authorization, 'Bearer test');
    return _admin;
  }

  Future<Map<String, dynamic>> json(Response response) async =>
      jsonDecode(await response.body()) as Map<String, dynamic>;

  group('GET /admin/payouts', () {
    Future<Response> list({AdminResolver? resolver}) =>
        list_route.handleAdminPayouts(
          context,
          adminResolver: resolver ?? adminResolver,
          repositoryFactory: () => repository,
        );

    test('lists payouts for a verified administrator', () async {
      final response = await list();
      expect(response.statusCode, HttpStatus.ok);
      final body = await json(response);
      expect(body['adminName'], 'Admin Tester');
      expect(body['payouts'], hasLength(1));
      expect(repository.query?.status, isNull);
      expect(repository.query?.page, 1);
      expect(repository.query?.pageSize, 20);
    });

    test('passes the status filter and page through', () async {
      when(() => request.uri).thenReturn(
        Uri.parse('/admin/payouts?status=approved&page=2&pageSize=10'),
      );
      final response = await list();
      expect(response.statusCode, HttpStatus.ok);
      expect(repository.query?.status, 'Approved');
      expect(repository.query?.page, 2);
      expect(repository.query?.pageSize, 10);
    });

    test('rejects unknown filters before looking anything up', () async {
      when(
        () => request.uri,
      ).thenReturn(Uri.parse('/admin/payouts?status=rejected'));
      expect((await list()).statusCode, HttpStatus.badRequest);
      when(() => request.uri).thenReturn(Uri.parse('/admin/payouts?page=0'));
      expect((await list()).statusCode, HttpStatus.badRequest);
      expect(repository.query, isNull);
    });

    test('returns 401 when the Firebase token is invalid', () async {
      final response = await list(
        resolver: (_) => throw const AuthTokenException('Invalid token.'),
      );
      expect(response.statusCode, HttpStatus.unauthorized);
      expect(repository.query, isNull);
    });

    test('returns 403 for a non-admin and for a role without finance '
        'access', () async {
      final notAdmin = await list(
        resolver: (_) =>
            throw const AdminAccessDenied('Administrator access is required.'),
      );
      final monitor = await list(
        resolver: (_) async => const AdminIdentity(
          id: 9,
          name: 'Monitor',
          roleKey: 'monitor_admin',
        ),
      );
      expect(notAdmin.statusCode, HttpStatus.forbidden);
      expect(monitor.statusCode, HttpStatus.forbidden);
      expect(repository.query, isNull);
    });

    test('returns 503 without SQL details when the payout table is '
        'missing', () async {
      repository.error = const MySQLServerException(
        "Table 'theotutoring.payout' doesn't exist",
        1146,
      );
      final response = await list();
      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect((await json(response))['error'], isNot(contains('theotutoring')));
    });

    test('returns a generic 500 for other database failures', () async {
      repository.error = const MySQLServerException('Deadlock found', 1213);
      final response = await list();
      expect(response.statusCode, HttpStatus.internalServerError);
      expect(
        (await json(response))['error'],
        'Payouts are temporarily unavailable.',
      );
    });
  });

  group('POST /admin/payouts/:id/(approve|mark-paid)', () {
    Future<Response> send(
      String action, {
      String id = '5',
      AdminResolver? resolver,
    }) {
      when(() => request.method).thenReturn(HttpMethod.post);
      return action_route.handlePayoutAction(
        context,
        action: action,
        payoutId: id,
        adminResolver: resolver ?? adminResolver,
        repositoryFactory: () => repository,
      );
    }

    test('approves the parsed payout', () async {
      final response = await send('approve');
      expect(response.statusCode, HttpStatus.ok);
      expect(repository.action, 'approve');
      expect(repository.payoutId, 5);
    });

    test('marks the parsed payout as paid', () async {
      final response = await send('mark-paid');
      expect(response.statusCode, HttpStatus.ok);
      expect(repository.action, 'mark-paid');
      expect(repository.payoutId, 5);
    });

    test('rejects invalid payout IDs before authenticating', () async {
      var resolved = false;
      for (final id in ['0', '-3', 'abc', '']) {
        final response = await send(
          'approve',
          id: id,
          resolver: (_) async {
            resolved = true;
            return _admin;
          },
        );
        expect(response.statusCode, HttpStatus.badRequest, reason: id);
      }
      expect(resolved, isFalse);
      expect(repository.action, isNull);
    });

    test('only accepts POST', () async {
      when(() => request.method).thenReturn(HttpMethod.get);
      final response = await action_route.handlePayoutAction(
        context,
        action: 'approve',
        payoutId: '5',
        adminResolver: adminResolver,
        repositoryFactory: () => repository,
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });

    test('returns 401 and 403 for authentication and permission '
        'failures', () async {
      final unauthenticated = await send(
        'approve',
        resolver: (_) => throw const AuthTokenException('Sign in required.'),
      );
      final support = await send(
        'mark-paid',
        resolver: (_) async => const AdminIdentity(
          id: 9,
          name: 'Support',
          roleKey: 'support_admin',
        ),
      );
      expect(unauthenticated.statusCode, HttpStatus.unauthorized);
      expect(support.statusCode, HttpStatus.forbidden);
      expect(repository.action, isNull);
    });

    test('returns 404 when the payout does not exist', () async {
      repository.error = const AdminPayoutNotFound();
      final response = await send('approve');
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('returns 409 with the reason for an invalid transition', () async {
      repository.error = const AdminPayoutConflict(
        'Approve this payout before marking it as paid.',
      );
      final response = await send('mark-paid');
      expect(response.statusCode, HttpStatus.conflict);
      expect(
        (await json(response))['error'],
        'Approve this payout before marking it as paid.',
      );
    });

    test('returns a generic 500 for database failures', () async {
      repository.error = const MySQLServerException(
        "Unknown column 'PaidAt' in 'field list'",
        1054,
      );
      final response = await send('mark-paid');
      expect(response.statusCode, HttpStatus.internalServerError);
      final error = (await json(response))['error'] as String;
      expect(error, 'The payout could not be updated.');
      expect(error, isNot(contains('PaidAt')));
    });
  });

  group('MySqlAdminPayoutsRepository', () {
    test('lists payouts with tutor, booking and student details', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = _connection(statements, (sql) {
        if (sql.contains('COUNT(*) AS n')) {
          return _result([
            {'n': '1'},
          ]);
        }
        if (sql.contains('AS PendingCount')) {
          return _result([
            {
              'PendingCount': '1',
              'PendingNet': '270.00',
              'ApprovedCount': '0',
              'ApprovedNet': '0',
              'PaidCount': '2',
              'PaidNet': '540.00',
            },
          ]);
        }
        return _result([
          {
            'PayoutID': '5',
            'Amount': '300.00',
            'CommissionAmount': '30.00',
            'NetAmount': '270.00',
            'Status': 'Pending',
            'BookingID': '12',
            'CreatedAt': '2026-11-10T09:00:00',
            'ApprovedAt': null,
            'PaidAt': null,
            'TutorID': '3',
            'TutorName': 'Tutor One',
            'TutorEmail': 'tutor@example.com',
            'StudentName': 'Student One',
            'subjectName': 'Mathematics',
            'SessionDate': '2026-11-09',
            'StartTime': '10:00',
            'EndTime': '11:00',
            'BookingStatus': 'Completed',
            'ApprovedBy': null,
          },
        ]);
      });

      final result = await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).list(const AdminPayoutQuery(status: 'Pending', pageSize: 10));

      final listQuery = statements.singleWhere(
        (s) => s.$1.contains('FROM payout p') && s.$1.contains('LIMIT'),
      );
      expect(listQuery.$1, contains('WHERE p.Status = :status'));
      expect(listQuery.$2, {'status': 'Pending', 'limit': 10, 'offset': 0});
      expect(result['total'], 1);
      final summary = result['summary']! as Map<String, Object?>;
      expect(summary['pendingNetAmount'], 270.0);
      expect(summary['paidCount'], 2);
      final payout =
          (result['payouts']! as List).single as Map<String, Object?>;
      expect(payout['status'], 'pending');
      expect(payout['amount'], 300.0);
      expect(payout['commissionAmount'], 30.0);
      expect(payout['netAmount'], 270.0);
      expect(payout['approvedAt'], isNull);
      expect((payout['tutor']! as Map)['name'], 'Tutor One');
      final booking = payout['booking']! as Map<String, Object?>;
      expect(booking['bookingId'], 12);
      expect(booking['studentName'], 'Student One');
    });

    test('approves a pending payout under a row lock, recording the admin '
        'and ApprovedAt', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = _connection(statements, (sql) {
        if (sql.contains('SELECT Status FROM payout')) {
          return _result([
            {'Status': 'Pending'},
          ]);
        }
        return _result([], affectedRows: BigInt.one);
      });

      await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).approve(5, _admin);

      expect(statements.first.$1, contains('FOR UPDATE'));
      expect(statements.first.$2, {'id': 5});
      final update = statements.singleWhere(
        (s) => s.$1.contains('UPDATE payout'),
      );
      expect(update.$1, contains("Status = 'Approved'"));
      expect(update.$1, contains('AdminID = :adminId'));
      expect(update.$1, contains('ApprovedAt = NOW()'));
      expect(update.$1, contains("AND Status = 'Pending'"));
      expect(update.$2, {'adminId': 7, 'id': 5});
    });

    test('marks an approved payout as paid, recording PaidAt', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = _connection(statements, (sql) {
        if (sql.contains('SELECT Status FROM payout')) {
          return _result([
            {'Status': 'Approved'},
          ]);
        }
        return _result([], affectedRows: BigInt.one);
      });

      await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).markPaid(5, _admin);

      expect(statements.first.$1, contains('FOR UPDATE'));
      final update = statements.singleWhere(
        (s) => s.$1.contains('UPDATE payout'),
      );
      expect(update.$1, contains("Status = 'Paid'"));
      expect(update.$1, contains('PaidAt = NOW()'));
      expect(update.$1, contains("AND Status = 'Approved'"));
      expect(update.$2, {'id': 5});
    });

    Future<void> expectConflict(
      Future<void> Function(MySqlAdminPayoutsRepository repository) action,
      String status,
      String message,
    ) async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = _connection(
        statements,
        (_) => _result([
          {'Status': status},
        ]),
      );
      await expectLater(
        action(
          MySqlAdminPayoutsRepository(
            connectionFactory: () async => connection,
          ),
        ),
        throwsA(
          isA<AdminPayoutConflict>().having(
            (e) => e.message,
            'message',
            message,
          ),
        ),
      );
      // Only the locking read ran: nothing was updated.
      expect(statements, hasLength(1));
    }

    test('will not approve an already approved or paid payout', () async {
      await expectConflict(
        (r) => r.approve(5, _admin),
        'Approved',
        'This payout is already approved.',
      );
      await expectConflict(
        (r) => r.approve(5, _admin),
        'Paid',
        'This payout has already been paid.',
      );
    });

    test('will not mark a pending payout as paid', () async {
      await expectConflict(
        (r) => r.markPaid(5, _admin),
        'Pending',
        'Approve this payout before marking it as paid.',
      );
    });

    test('will not mark a payout as paid twice', () async {
      await expectConflict(
        (r) => r.markPaid(5, _admin),
        'Paid',
        'This payout is already marked as paid.',
      );
    });

    test('reports a conflict when the guarded update changes no row', () async {
      final connection = _connection([], (sql) {
        if (sql.contains('SELECT Status FROM payout')) {
          return _result([
            {'Status': 'Approved'},
          ]);
        }
        return _result([]);
      });
      await expectLater(
        MySqlAdminPayoutsRepository(
          connectionFactory: () async => connection,
        ).markPaid(5, _admin),
        throwsA(isA<AdminPayoutConflict>()),
      );
    });

    test('throws not found for a missing payout', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = _connection(statements, (_) => _result([]));
      await expectLater(
        MySqlAdminPayoutsRepository(
          connectionFactory: () async => connection,
        ).approve(99, _admin),
        throwsA(isA<AdminPayoutNotFound>()),
      );
      expect(statements, hasLength(1));
    });

    test('passes database failures on to the route', () async {
      final connection = _connection([], (_) {
        throw const MySQLServerException('Lock wait timeout exceeded', 1205);
      });
      await expectLater(
        MySqlAdminPayoutsRepository(
          connectionFactory: () async => connection,
        ).approve(5, _admin),
        throwsA(isA<MySQLServerException>()),
      );
    });
  });
}
