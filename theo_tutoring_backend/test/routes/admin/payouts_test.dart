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
import '../../../routes/admin/payouts/generate.dart' as generate_route;
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
  String? reference;
  AdminIdentity? actingAdmin;
  int generated = 0;
  Exception? error;

  @override
  Future<int> generate(AdminIdentity admin) async {
    action = 'generate';
    actingAdmin = admin;
    if (error != null) throw error!;
    return generated;
  }

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
  Future<void> markPaid(
    int payoutId,
    AdminIdentity admin, {
    String? reference,
  }) async {
    action = 'mark-paid';
    this.payoutId = payoutId;
    this.reference = reference;
    actingAdmin = admin;
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
  when(() => connection.transactional<int>(any())).thenAnswer((
    invocation,
  ) async {
    final callback =
        invocation.positionalArguments.single
            as FutureOr<int> Function(MySQLConnection);
    return callback(connection);
  });
  when(
    () => connection.transactional<Map<String, Object?>>(any()),
  ).thenAnswer((invocation) async {
    final callback =
        invocation.positionalArguments.single
            as FutureOr<Map<String, Object?>> Function(MySQLConnection);
    return callback(connection);
  });
  return connection;
}

/// A connection answering approve / mark-paid's statements: the payout's
/// booking (12), its refund ([refundStatus], none when null), the payout's
/// [status]; updates change [updateRows] rows and the audit insert one row
/// (or throws [auditError]).
_MockConnection _transitionConnection(
  List<(String, Map<String, dynamic>?)> statements, {
  required String status,
  String? refundStatus,
  BigInt? updateRows,
  Exception? auditError,
}) => _connection(statements, (sql) {
  if (sql.contains('SELECT BookingID FROM payout')) {
    return _result([
      {'BookingID': '12'},
    ]);
  }
  if (sql.contains('FROM booking')) {
    return _result([
      {'Booking_id': '12'},
    ]);
  }
  if (sql.contains('FROM refund')) {
    return _result([
      if (refundStatus != null) {'RefundStatus': refundStatus},
    ]);
  }
  if (sql.contains('SELECT Status FROM payout')) {
    return _result([
      {'Status': status},
    ]);
  }
  if (sql.contains('INSERT INTO payoutadminaction')) {
    if (auditError != null) throw auditError;
    return _result([], affectedRows: BigInt.one);
  }
  return _result([], affectedRows: updateRows ?? BigInt.one);
});

/// A paid-lesson row as paidLessonsQuery returns it.
Map<String, String?> _lessonRow(
  int bookingId, {
  String status = 'Confirmed',
  bool ended = true,
  String price = '175.00',
  String? rate = '10.00',
  String? source = 'Purchase',
  String? refundStatus,
  String? refundAmount,
  String? payoutId,
  String? payoutTotal,
}) => {
  'Booking_id': '$bookingId',
  'TutorID': '3',
  'Status': status,
  'Ended': ended ? '1' : '0',
  'Price': price,
  'CommissionPercentage': rate,
  'CommissionSource': source,
  'RefundStatus': refundStatus,
  'RefundAmount': refundAmount,
  'PayoutID': payoutId,
  'PayoutTotal': payoutTotal ?? (payoutId == null ? null : price),
};

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
    when(() => request.body()).thenAnswer((_) async => '');
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
              'CommissionTotal': '90.00',
              'InconsistentCount': '0',
            },
          ]);
        }
        if (sql.contains('AS PurchaseReceived')) {
          return _result([
            {'PurchaseReceived': '900.00', 'LegacyReceived': '0'},
          ]);
        }
        if (sql.contains('AS Ended')) {
          return _result([
            for (final (booking, payout) in [(12, '5'), (13, '6'), (14, '7')])
              _lessonRow(booking, price: '300.00', payoutId: payout),
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
            'CommissionPercentage': '10.00',
            'CommissionSource': 'Backfilled',
            'ApprovedBy': null,
            'PaidBy': null,
            'PaymentReference': null,
            'RefundStatus': 'Approved',
            'RefundAmount': '150.00',
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
      // The rate it used, and a refund recorded after the payout, are shown.
      expect(payout['commissionRate'], '10.00');
      expect(payout['commissionRateBackfilled'], isTrue);
      expect(payout['flagged'], isTrue);
      expect(payout['refund'], {'status': 'approved', 'amount': 150.0});

      // GET only reads: no payout is generated as a side effect.
      expect(
        statements.where(
          (s) => RegExp(r'\b(INSERT|UPDATE|DELETE)\b').hasMatch(s.$1),
        ),
        isEmpty,
      );
      expect(statements.any((s) => s.$1.contains('GET_LOCK')), isFalse);
      // A legacy payment linked to a purchase settlement is counted once.
      expect(
        statements
            .singleWhere((s) => s.$1.contains('AS PurchaseReceived'))
            .$1,
        contains('WHERE lpp.PaymentID = lp.PaymentID'),
      );

      final finance = result['finance']! as Map<String, Object?>;
      expect(finance['moneyReceived'], '900.00');
      expect(finance['platformCommission'], '90.00');
      expect(finance['owedToTutors'], '270.00');
      expect(finance['paidToTutors'], '540.00');
      expect(finance['reconciled'], isTrue);
    });

    test('approves a pending payout, locking booking -> refund -> payout, '
        'recording the admin and ApprovedAt', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = _transitionConnection(statements, status: 'Pending');

      await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).approve(5, _admin);

      // The lock order every writer shares: booking, refund, then payout.
      expect(statements[0].$1, contains('SELECT BookingID FROM payout'));
      expect(statements[0].$1, isNot(contains('FOR ')));
      expect(statements[1].$1, contains('FROM booking'));
      expect(statements[1].$1, contains('FOR SHARE'));
      expect(statements[1].$2, {'booking': '12'});
      expect(statements[2].$1, contains('FROM refund'));
      expect(statements[2].$1, contains('FOR SHARE'));
      expect(statements[3].$1, contains('SELECT Status FROM payout'));
      expect(statements[3].$1, contains('FOR UPDATE'));
      expect(statements[3].$2, {'id': 5});
      final update = statements.singleWhere(
        (s) => s.$1.contains('UPDATE payout'),
      );
      expect(update.$1, contains("Status = 'Approved'"));
      expect(update.$1, contains('AdminID = :adminId'));
      expect(update.$1, contains('ApprovedAt = NOW()'));
      expect(update.$1, contains("AND Status = 'Pending'"));
      expect(update.$2, {'adminId': 7, 'id': 5});
      // The audit row is written after the update, in the same transaction.
      expect(statements.last.$1, contains('INSERT INTO payoutadminaction'));
      expect(statements.last.$2, {
        'adminId': 7,
        'action': 'Approved',
        'reference': null,
        'id': 5,
      });
    });

    test('marks an approved payout as paid, recording the paying admin, '
        'PaidAt, the reference and an audit row', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      // A rejected refund does not block payment.
      final connection = _transitionConnection(
        statements,
        status: 'Approved',
        refundStatus: 'Rejected',
      );

      await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).markPaid(5, _admin, reference: 'EFT-2026-001');

      expect(statements[3].$1, contains('FOR UPDATE'));
      final update = statements.singleWhere(
        (s) => s.$1.contains('UPDATE payout'),
      );
      expect(update.$1, contains("Status = 'Paid'"));
      expect(update.$1, contains('PaidAt = NOW()'));
      expect(update.$1, contains('PaidByAdminID = :adminId'));
      expect(update.$1, contains('PaymentReference = :reference'));
      expect(update.$1, contains("AND Status = 'Approved'"));
      expect(update.$2, {'adminId': 7, 'reference': 'EFT-2026-001', 'id': 5});
      expect(statements.last.$1, contains('INSERT INTO payoutadminaction'));
      expect(statements.last.$2, {
        'adminId': 7,
        'action': 'Paid',
        'reference': 'EFT-2026-001',
        'id': 5,
      });
    });

    test('a step already in the audit trail is a conflict, not a duplicate',
        () async {
      final connection = _transitionConnection(
        <(String, Map<String, dynamic>?)>[],
        status: 'Approved',
        auditError: const MySQLServerException(
          "Duplicate entry '5-Paid' for key 'uq_payout_action_once'",
          1062,
        ),
      );
      await expectLater(
        MySqlAdminPayoutsRepository(
          connectionFactory: () async => connection,
        ).markPaid(5, _admin),
        throwsA(
          isA<AdminPayoutConflict>().having(
            (e) => e.message,
            'message',
            'This payout is already marked as paid.',
          ),
        ),
      );
    });

    Future<void> expectConflict(
      Future<void> Function(MySqlAdminPayoutsRepository repository) action,
      String status,
      String message, {
      String? refundStatus,
    }) async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = _transitionConnection(
        statements,
        status: status,
        refundStatus: refundStatus,
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
      // Only the locking reads ran: nothing was updated or audited.
      expect(
        statements.where(
          (s) => s.$1.contains('UPDATE payout') || s.$1.contains('INSERT'),
        ),
        isEmpty,
      );
    }

    test('an unresolved refund blocks approval and payment; a rejected one '
        'does not', () async {
      for (final refund in ['Pending', 'Approved', 'Processed']) {
        final message = refund == 'Pending'
            ? 'A refund for this lesson is awaiting a decision. Decide it '
                  'before approving or paying this payout.'
            : 'A refund was ${refund.toLowerCase()} for this lesson after the '
                  'payout was generated. Resolve it before approving or paying '
                  'this payout.';
        await expectConflict(
          (r) => r.approve(5, _admin),
          'Pending',
          message,
          refundStatus: refund,
        );
        await expectConflict(
          (r) => r.markPaid(5, _admin, reference: 'EFT-1'),
          'Approved',
          message,
          refundStatus: refund,
        );
      }
      // A status conflict is reported before the refund (an already paid
      // payout is never touched, let alone reversed).
      await expectConflict(
        (r) => r.markPaid(5, _admin),
        'Paid',
        'This payout is already marked as paid.',
        refundStatus: 'Approved',
      );
      final statements = <(String, Map<String, dynamic>?)>[];
      await MySqlAdminPayoutsRepository(
        connectionFactory: () async => _transitionConnection(
          statements,
          status: 'Pending',
          refundStatus: 'Rejected',
        ),
      ).approve(5, _admin);
      expect(statements.any((s) => s.$1.contains('UPDATE payout')), isTrue);
    });

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
      final connection = _transitionConnection(
        <(String, Map<String, dynamic>?)>[],
        status: 'Approved',
        updateRows: BigInt.zero,
      );
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

  group('MySqlAdminPayoutsRepository.generate', () {
    /// A connection whose named lock answers [locked] and whose paid-lesson
    /// query returns [lessons]; payout inserts get IDs 100, 101, ...
    _MockConnection generationConnection(
      List<(String, Map<String, dynamic>?)> statements, {
      required List<Map<String, String?>> lessons,
      List<Map<String, String?>>? lockedLessons,
      String locked = '1',
      Exception? insertError,
    }) {
      var nextId = 100;
      final connection = _connection(statements, (sql) {
        if (sql.contains('GET_LOCK')) {
          return _result([
            {'Locked': locked},
          ]);
        }
        // The locking re-read sees the latest committed state, which may
        // differ from the snapshot the candidates came from.
        if (sql.contains('AS Ended') && sql.contains('FOR SHARE OF b, r')) {
          return _result(lockedLessons ?? lessons);
        }
        if (sql.contains('AS Ended')) return _result(lessons);
        if (sql.contains('INSERT INTO payout\n') ||
            sql.contains('INSERT INTO payout (')) {
          if (insertError != null) throw insertError;
          final result = _result([], affectedRows: BigInt.one);
          when(() => result.lastInsertID).thenReturn(BigInt.from(nextId++));
          return result;
        }
        return _result([], affectedRows: BigInt.one);
      });
      when(() => connection.connected).thenReturn(true);
      when(connection.close).thenAnswer((_) async {});
      return connection;
    }

    test('creates a Pending payout and an audit row per eligible lesson, '
        'using the captured rate', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = generationConnection(
        statements,
        lessons: [
          _lessonRow(1), // finished, 10%: eligible
          _lessonRow(2, price: '185.00', rate: '15.00'), // eligible at 15%
          _lessonRow(3, ended: false), // upcoming
          _lessonRow(4, status: 'Cancelled', refundStatus: 'Rejected'),
          _lessonRow(5, refundStatus: 'Approved', refundAmount: '175.00'),
          _lessonRow(6, refundStatus: 'Pending', refundAmount: '0.00'),
          _lessonRow(7, payoutId: '40'), // already has one
          _lessonRow(8, rate: null, source: null), // no rate recorded
        ],
      );

      final generated = await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).generate(_admin);

      expect(generated, 2);
      expect(statements.first.$1, contains('GET_LOCK'));
      expect(statements.first.$2, {
        'name': payoutGenerationLock,
        'timeout': payoutGenerationLockTimeoutSeconds,
      });
      final inserts = statements
          .where((s) => s.$1.contains('INSERT INTO payout\n'))
          .toList();
      expect(inserts.map((s) => s.$2), [
        {
          'tutorId': 3,
          'amount': '175.00',
          'commission': '17.50',
          'net': '157.50',
          'bookingId': 1,
        },
        {
          'tutorId': 3,
          'amount': '185.00',
          'commission': '27.75',
          'net': '157.25',
          'bookingId': 2,
        },
      ]);
      expect(inserts.first.$1, contains("'Pending'"));
      final audits = statements
          .where((s) => s.$1.contains('INSERT INTO payoutadminaction'))
          .map((s) => s.$2)
          .toList();
      expect(audits, [
        {'adminId': 7, 'action': 'Generated', 'reference': null, 'id': 100},
        {'adminId': 7, 'action': 'Generated', 'reference': null, 'id': 101},
      ]);
      // Existing payouts are never updated; the lock is released.
      expect(statements.any((s) => s.$1.contains('UPDATE payout')), isFalse);
      expect(statements.last.$1, contains('RELEASE_LOCK'));
    });

    test('locks booking then refund rows of the candidates, in order, and '
        're-reads them with a locking read before inserting', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = generationConnection(
        statements,
        lessons: [_lessonRow(9), _lessonRow(4), _lessonRow(5, ended: false)],
      );
      await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).generate(_admin);

      final sqls = statements.map((s) => s.$1).toList();
      final snapshot = sqls.indexWhere(
        (s) => s.contains('AS Ended') && !s.contains('FOR '),
      );
      final bookingLock = sqls.indexWhere(
        (s) => s.contains('SELECT Booking_id FROM booking'),
      );
      final lockedRead = sqls.indexWhere(
        (s) => s.contains('AS Ended') && s.contains('FOR SHARE OF b, r'),
      );
      final firstInsert = sqls.indexWhere(
        (s) => s.contains('INSERT INTO payout\n'),
      );
      expect(snapshot, greaterThan(0)); // after GET_LOCK
      expect(bookingLock, greaterThan(snapshot));
      expect(lockedRead, greaterThan(bookingLock));
      expect(firstInsert, greaterThan(lockedRead));
      // Only the eligible candidates (4 and 9) are locked, in ascending order.
      expect(sqls[bookingLock], contains('Booking_id IN (4, 9)'));
      expect(sqls[bookingLock], contains('ORDER BY Booking_id FOR SHARE'));
      expect(sqls[lockedRead], contains('AND b.Booking_id IN (4, 9)'));
    });

    test('a lesson cancelled or refunded while generation waited for its '
        'lock gets no payout', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = generationConnection(
        statements,
        // Eligible in the snapshot...
        lessons: [_lessonRow(1), _lessonRow(2), _lessonRow(3)],
        // ...but the in-flight cancellation / refund committed meanwhile.
        lockedLessons: [
          _lessonRow(1, status: 'Cancelled', refundStatus: 'Pending'),
          _lessonRow(2, refundStatus: 'Approved', refundAmount: '175.00'),
          _lessonRow(3),
        ],
      );
      final generated = await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).generate(_admin);
      expect(generated, 1);
      final inserts = statements
          .where((s) => s.$1.contains('INSERT INTO payout\n'))
          .map((s) => s.$2!['bookingId'])
          .toList();
      expect(inserts, [3]);
    });

    test('takes no row locks when nothing is eligible', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = generationConnection(
        statements,
        lessons: [_lessonRow(1, ended: false)],
      );
      expect(
        await MySqlAdminPayoutsRepository(
          connectionFactory: () async => connection,
        ).generate(_admin),
        0,
      );
      expect(statements.any((s) => s.$1.contains('FOR SHARE')), isFalse);
      expect(statements.last.$1, contains('RELEASE_LOCK'));
    });

    test('money received and paid lessons never count a legacy payment '
        'that a purchase settlement already links', () {
      final query = paidLessonsQuery();
      expect(
        query,
        contains(
          'NOT EXISTS (SELECT 1 FROM purchasepayment lpp '
          'WHERE lpp.PaymentID = lp.PaymentID)',
        ),
      );
      expect(query, contains('AS PastEnd'));
    });

    test('running again with nothing new creates nothing', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = generationConnection(
        statements,
        lessons: [
          _lessonRow(1, payoutId: '100'),
          _lessonRow(2, payoutId: '101'),
        ],
      );
      final generated = await MySqlAdminPayoutsRepository(
        connectionFactory: () async => connection,
      ).generate(_admin);
      expect(generated, 0);
      expect(statements.any((s) => s.$1.contains('INSERT')), isFalse);
    });

    test('a concurrent generation holding the lock is refused, without '
        'reading or writing anything', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = generationConnection(
        statements,
        lessons: [_lessonRow(1)],
        locked: '0',
      );
      await expectLater(
        MySqlAdminPayoutsRepository(
          connectionFactory: () async => connection,
        ).generate(_admin),
        throwsA(isA<AdminPayoutConflict>()),
      );
      expect(statements, hasLength(1)); // only GET_LOCK
      verifyNever(() => connection.transactional<int>(any()));
    });

    test('a duplicate payout rolls the whole generation back as a conflict '
        'and still releases the lock', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = generationConnection(
        statements,
        lessons: [_lessonRow(1)],
        insertError: const MySQLServerException(
          "Duplicate entry '1' for key 'payout.BookingID'",
          1062,
        ),
      );
      await expectLater(
        MySqlAdminPayoutsRepository(
          connectionFactory: () async => connection,
        ).generate(_admin),
        throwsA(isA<AdminPayoutConflict>()),
      );
      expect(statements.last.$1, contains('RELEASE_LOCK'));
    });

    test('other database failures pass through, releasing the lock', () async {
      final statements = <(String, Map<String, dynamic>?)>[];
      final connection = generationConnection(
        statements,
        lessons: [_lessonRow(1)],
        insertError: const MySQLServerException('Lock wait timeout', 1205),
      );
      await expectLater(
        MySqlAdminPayoutsRepository(
          connectionFactory: () async => connection,
        ).generate(_admin),
        throwsA(isA<MySQLServerException>()),
      );
      expect(statements.last.$1, contains('RELEASE_LOCK'));
    });
  });

  group('POST /admin/payouts/generate', () {
    Future<Response> generate({AdminResolver? resolver}) {
      when(() => request.method).thenReturn(HttpMethod.post);
      return generate_route.handleGeneratePayouts(
        context,
        adminResolver: resolver ?? adminResolver,
        repositoryFactory: () => repository,
      );
    }

    test('returns how many payouts were generated', () async {
      repository.generated = 3;
      final response = await generate();
      expect(response.statusCode, HttpStatus.ok);
      final body = await json(response);
      expect(body['generated'], 3);
      expect(body['message'], '3 payouts generated.');
      expect(repository.actingAdmin?.id, 7);
    });

    test('says so when there is nothing new to generate', () async {
      final body = await json(await generate());
      expect(body['generated'], 0);
      expect(body['message'], contains('No new eligible lessons'));
    });

    test('requires admin.payouts.manage', () async {
      final unauthenticated = await generate(
        resolver: (_) => throw const AuthTokenException('Sign in required.'),
      );
      final reviewer = await generate(
        resolver: (_) async => const AdminIdentity(
          id: 9,
          name: 'Reviewer',
          roleKey: 'application_reviewer',
        ),
      );
      final support = await generate(
        resolver: (_) async => const AdminIdentity(
          id: 9,
          name: 'Support',
          roleKey: 'support_admin',
        ),
      );
      expect(unauthenticated.statusCode, HttpStatus.unauthorized);
      expect(reviewer.statusCode, HttpStatus.forbidden);
      expect(support.statusCode, HttpStatus.forbidden);
      expect(repository.action, isNull);
    });

    test('only accepts POST', () async {
      when(() => request.method).thenReturn(HttpMethod.get);
      final response = await generate_route.handleGeneratePayouts(
        context,
        adminResolver: adminResolver,
        repositoryFactory: () => repository,
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(repository.action, isNull);
    });

    test('409 while another generation runs', () async {
      repository.error = const AdminPayoutConflict(
        'Payouts are already being generated. Refresh in a moment.',
      );
      final response = await generate();
      expect(response.statusCode, HttpStatus.conflict);
      expect((await json(response))['error'], contains('already being'));
    });

    test('503 before migration 013, 500 otherwise, without SQL details',
        () async {
      repository.error = const MySQLServerException(
        "Unknown column 'CommissionSource' in 'field list'",
        1054,
      );
      final missing = await generate();
      expect(missing.statusCode, HttpStatus.serviceUnavailable);
      expect((await json(missing))['error'], isNot(contains('Commission')));
      repository.error = const MySQLServerException('Deadlock found', 1213);
      final failed = await generate();
      expect(failed.statusCode, HttpStatus.internalServerError);
      expect(
        (await json(failed))['error'],
        'Payouts could not be generated. Nothing was changed.',
      );
    });
  });

  group('POST /admin/payouts/:id/mark-paid reference', () {
    Future<Response> markPaid(String body) {
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.body()).thenAnswer((_) async => body);
      return action_route.handlePayoutAction(
        context,
        action: 'mark-paid',
        payoutId: '5',
        adminResolver: adminResolver,
        repositoryFactory: () => repository,
      );
    }

    test('passes the trimmed external reference and the paying admin',
        () async {
      final response = await markPaid('{"reference": "  EFT-2026-001 "}');
      expect(response.statusCode, HttpStatus.ok);
      expect(repository.reference, 'EFT-2026-001');
      expect(repository.actingAdmin?.id, 7);
    });

    test('the reference is optional', () async {
      const bodies = ['', '{}', '{"reference": null}', '{"reference":""}'];
      for (final body in bodies) {
        repository.action = null;
        final response = await markPaid(body);
        expect(response.statusCode, HttpStatus.ok, reason: body);
        expect(repository.action, 'mark-paid');
        expect(repository.reference, isNull, reason: body);
      }
    });

    test('rejects an invalid reference or body without marking it paid',
        () async {
      for (final body in [
        '{"reference": "${'x' * 101}"}',
        '{"reference": 42}',
        r'{"reference": "two\nlines"}',
        'not json',
        '[]',
      ]) {
        final response = await markPaid(body);
        expect(response.statusCode, HttpStatus.badRequest, reason: body);
      }
      expect(repository.action, isNull);
    });

    test('a second payment of the same payout is a 409', () async {
      repository.error = const AdminPayoutConflict(
        'This payout is already marked as paid.',
      );
      final response = await markPaid('{"reference": "EFT-1"}');
      expect(response.statusCode, HttpStatus.conflict);
      expect(
        (await json(response))['error'],
        'This payout is already marked as paid.',
      );
    });
  });
}
