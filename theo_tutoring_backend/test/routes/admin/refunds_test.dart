import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/refunds/[refundId]/approve.dart' as action_route;
import '../../../routes/admin/refunds/index.dart' as cases_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

class _FakeRepository implements AdminRefundsRepository {
  String? action;
  int? refundId;
  String? reason;
  double? percentage;
  String? type;
  String? status;
  bool failOnClosed = false;

  @override
  Future<Map<String, Object?>> fetchCases({
    required String type,
    required String status,
    required String adminName,
  }) async {
    this.type = type;
    this.status = status;
    return {
      'adminName': adminName,
      'summary': {
        'openDisputes': 0,
        'pendingRefunds': 1,
        'pendingRefundAmount': 100.0,
        'resolvedLast7Days': 0,
        'needsAction': 1,
      },
      'cases': <Object?>[],
    };
  }

  @override
  Future<void> approve(int refundId, AdminIdentity admin) async {
    action = 'approve';
    this.refundId = refundId;
  }

  @override
  Future<void> deny(int refundId, AdminIdentity admin, String reason) async {
    action = 'deny';
    this.refundId = refundId;
    this.reason = reason;
  }

  @override
  Future<void> overrideDecision(
    int refundId,
    AdminIdentity admin,
    double percentage,
    String reason,
  ) async {
    action = 'override';
    this.refundId = refundId;
    this.reason = reason;
    this.percentage = percentage;
  }

  @override
  Future<void> resolveReport(
    int reportId,
    AdminIdentity admin,
    String note,
  ) async {
    action = 'resolve';
    refundId = reportId;
    reason = note;
  }
}

IResultSet _result(
  List<Map<String, String?>> rows, {
  BigInt? affectedRows,
}) {
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

class _ThrowingRepository extends _FakeRepository {
  _ThrowingRepository(this.error);
  final Exception error;

  @override
  Future<Map<String, Object?>> fetchCases({
    required String type,
    required String status,
    required String adminName,
  }) async => throw error;
}

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
    when(() => request.uri).thenReturn(Uri.parse('/admin/refunds'));
    when(() => request.headers).thenReturn({'Authorization': 'Bearer test'});
  });

  Future<AdminIdentity> adminResolver(String? authorization) async {
    expect(authorization, 'Bearer test');
    return const AdminIdentity(id: 7, name: 'Admin Tester');
  }

  group('GET /admin/refunds', () {
    test('returns cases for the verified administrator', () async {
      final response = await cases_route.handleRefundCases(
        context,
        adminResolver: adminResolver,
        repositoryFactory: () => repository,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      final summary = body['summary'] as Map<String, dynamic>;
      expect(body['adminName'], 'Admin Tester');
      expect(summary['pendingRefunds'], 1);
      expect(repository.type, 'all');
      expect(repository.status, 'all');
    });

    test(
      'report access uses report permissions, not review permissions',
      () async {
        when(() => request.uri).thenReturn(
          Uri.parse('/admin/refunds?type=report'),
        );
        final response = await cases_route.handleRefundCases(
          context,
          adminResolver: (_) async => const AdminIdentity(
            id: 8,
            name: 'Finance Admin',
            roleKey: 'finance_admin',
          ),
          repositoryFactory: () => repository,
        );
        expect(response.statusCode, HttpStatus.ok);
        expect(repository.type, 'report');
      },
    );

    test('rejects report access without report permissions', () async {
      when(() => request.uri).thenReturn(
        Uri.parse('/admin/refunds?type=report'),
      );
      final response = await cases_route.handleRefundCases(
        context,
        adminResolver: (_) async => const AdminIdentity(
          id: 9,
          name: 'Reviewer',
          roleKey: 'application_reviewer',
        ),
        repositoryFactory: () => repository,
      );
      expect(response.statusCode, HttpStatus.forbidden);
      expect(repository.type, isNull);
    });

    test('rejects unsupported filters before looking up data', () async {
      when(() => request.uri).thenReturn(
        Uri.parse('/admin/refunds?status=everything'),
      );
      final response = await cases_route.handleRefundCases(context);
      expect(response.statusCode, HttpStatus.badRequest);
    });

    test(
      'returns 403 for a valid Firebase user without an admin row',
      () async {
        final response = await cases_route.handleRefundCases(
          context,
          adminResolver: (_) => throw const AdminAccessDenied(
            'Administrator access is required.',
          ),
          repositoryFactory: () => repository,
        );
        expect(response.statusCode, HttpStatus.forbidden);
        expect(repository.type, isNull);
      },
    );

    test('returns 401 when Firebase token verification fails', () async {
      final response = await cases_route.handleRefundCases(
        context,
        adminResolver: (_) => throw const AuthTokenException('Invalid token.'),
        repositoryFactory: () => repository,
      );
      expect(response.statusCode, HttpStatus.unauthorized);
      expect(repository.type, isNull);
    });

    test('returns an accurate 503 when refund tables are missing', () async {
      final response = await cases_route.handleRefundCases(
        context,
        adminResolver: adminResolver,
        repositoryFactory: () => _ThrowingRepository(
          const MySQLServerException(
            "Table 'theotutoring_test.refundadminaction' doesn't exist",
            1146,
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], contains('required database tables are missing'));
      // The raw MySQL message (schema and table names) is not exposed.
      expect(body['error'], isNot(contains('refundadminaction')));
    });

    test('keeps the generic 500 for other lookup failures', () async {
      final response = await cases_route.handleRefundCases(
        context,
        adminResolver: adminResolver,
        repositoryFactory: () =>
            _ThrowingRepository(const MySQLServerException('Deadlock', 1213)),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], 'Refund cases are temporarily unavailable.');
    });
  });

  group('POST /admin/refunds/:id/:action', () {
    // Refund decisions the student was told about: (refundId, reason)
    final notified = <(int, String?)>[];
    setUp(notified.clear);

    Future<Response> sendAction(
      String action,
      Object? body, {
      String? id = '42',
      AdminResolver? resolveAdmin,
    }) {
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.json()).thenAnswer((_) async => body);
      return action_route.handleRefundAction(
        context,
        action: action,
        refundId: id,
        adminResolver: resolveAdmin ?? adminResolver,
        repositoryFactory: () => repository,
        notifyStudent: (refundId, {reason}) async =>
            notified.add((refundId, reason)),
      );
    }

    test('tells the student when a refund is approved or denied', () async {
      await sendAction('approve', const <String, dynamic>{});
      await sendAction('deny', {'reason': 'Cancelled after the lesson'});
      expect(notified, [(42, null), (42, 'Cancelled after the lesson')]);
    });

    test('an override does not notify: the refund is still pending', () async {
      final response = await sendAction('override', {
        'refundPercentage': 50,
        'reason': 'Approved as exception',
      });
      expect(response.statusCode, HttpStatus.ok);
      expect(notified, isEmpty);
    });

    test('records an approval for the parsed refund ID', () async {
      final response = await sendAction(
        'approve',
        const <String, dynamic>{},
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(repository.action, 'approve');
      expect(repository.refundId, 42);
    });

    test('rejects malformed IDs and short decision reasons', () async {
      final badId = await sendAction(
        'approve',
        const <String, dynamic>{},
        id: '0',
      );
      final badReason = await sendAction('deny', {'reason': 'no'});
      expect(badId.statusCode, HttpStatus.badRequest);
      expect(badReason.statusCode, HttpStatus.badRequest);
      expect(repository.action, isNull);
    });

    test('validates override percentage and reason', () async {
      final response = await sendAction('override', {
        'refundPercentage': 101,
        'reason': 'Approved as exception',
      });
      expect(response.statusCode, HttpStatus.badRequest);
      expect(repository.action, isNull);
    });

    test(
      'requires admin authorization before resolving reports',
      () async {
        final response = await sendAction(
          'resolve',
          {'note': 'Reviewed this report'},
          id: 'report-14',
          resolveAdmin: (_) =>
              throw const AuthTokenException('Sign in required.'),
        );
        expect(response.statusCode, HttpStatus.unauthorized);
      },
    );

    test('resolves a report using a namespaced case ID', () async {
      final response = await sendAction(
        'resolve',
        {'note': 'Reviewed this report'},
        id: 'report-14',
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(repository.action, 'resolve');
      expect(repository.refundId, 14);
      expect(repository.reason, 'Reviewed this report');
    });
  });

  group('MySqlAdminRefundsRepository decisions', () {
    test(
      'denial rejects the refund and records a Denied audit action',
      () async {
        final connection = _MockConnection();
        when(() => connection.connected).thenReturn(false);
        final statements = <(String, Map<String, dynamic>?)>[];
        when(() => connection.execute(any(), any())).thenAnswer((
          invocation,
        ) async {
          final sql = invocation.positionalArguments.first as String;
          final params =
              invocation.positionalArguments[1] as Map<String, dynamic>?;
          statements.add((sql, params));
          if (sql.contains('FROM refund r')) {
            return _result([
              {
                'RefundStatus': 'Pending',
                'RefundPercentage': '0',
                'OverriddenByAdmin': '0',
                'CancellationTime': '2026-11-10 10:00:00',
                'SessionStart': '2026-11-12 10:00:00',
                'AmountPaid': '100.00',
              },
            ]);
          }
          return _result([]);
        });
        when(
          () => connection.transactional<void>(any()),
        ).thenAnswer((invocation) async {
          final callback =
              invocation.positionalArguments.single
                  as FutureOr<void> Function(MySQLConnection);
          await callback(connection);
        });

        await MySqlAdminRefundsRepository(
          connectionFactory: () async => connection,
        ).deny(42, const AdminIdentity(id: 7, name: 'Admin'), 'Not eligible');

        final refundUpdate = statements.singleWhere(
          (statement) => statement.$1.contains('UPDATE refund'),
        );
        final auditInsert = statements.singleWhere(
          (statement) => statement.$1.contains('INSERT INTO refundadminaction'),
        );
        expect(refundUpdate.$2?['status'], 'Rejected');
        expect(auditInsert.$2?['action'], 'Denied');
      },
    );
  });

  group('MySqlAdminRefundsRepository reports', () {
    test('fetches report cases from Report', () async {
      final connection = _MockConnection();
      when(() => connection.connected).thenReturn(false);
      final statements = <String>[];
      when(() => connection.execute(any(), any())).thenAnswer((
        invocation,
      ) async {
        final sql = invocation.positionalArguments.first as String;
        statements.add(sql);
        if (sql.contains('FROM refund r')) return _result([]);
        if (sql.contains('FROM report report')) {
          return _result([
            {
              'ReportID': '14',
              'ReportStatus': 'Under review',
              'Category': '',
              'Reason': 'Lesson report: The tutor did not attend.',
              'CreatedAtUtc': '2026-10-28 12:00:00',
              'ReporterRole': 'student',
              'StudentName': 'Student',
              'TutorName': 'Tutor',
            },
          ]);
        }
        fail('Unexpected query: $sql');
      });

      final cases = await MySqlAdminRefundsRepository(
        connectionFactory: () async => connection,
      ).fetchCases(type: 'report', status: 'all', adminName: 'Admin');

      final reportQuery = statements.singleWhere(
        (sql) => sql.contains('FROM report'),
      );
      expect(reportQuery, contains('FROM report report'));
      expect(reportQuery, isNot(contains('UserReport')));
      expect(reportQuery, contains('LEFT JOIN `user` reported'));
      expect(
        reportQuery,
        contains('TIMESTAMPDIFF(SECOND, NOW(), UTC_TIMESTAMP())'),
      );
      final item = (cases['cases']! as List).single as Map<String, Object?>;
      expect(item['id'], 'report-14');
      expect(item['status'], 'under_review');
      expect(item['reason'], 'Lesson report: The tutor did not attend.');
      expect(item['createdAt'], '2026-10-28T14:00:00+02:00');
    });

    test(
      'resolves a Report with administrator attribution and details',
      () async {
        final connection = _MockConnection();
        when(() => connection.connected).thenReturn(false);
        final statements = <(String, Map<String, dynamic>?)>[];
        when(() => connection.execute(any(), any())).thenAnswer((
          invocation,
        ) async {
          final sql = invocation.positionalArguments.first as String;
          final params =
              invocation.positionalArguments[1] as Map<String, dynamic>?;
          statements.add((sql, params));
          if (sql.contains('SELECT Status FROM report')) {
            return _result([
              {'Status': 'Open'},
            ]);
          }
          if (sql.contains('UPDATE report')) {
            return _result([], affectedRows: BigInt.one);
          }
          fail('Unexpected query: $sql');
        });
        when(
          () => connection.transactional<void>(any()),
        ).thenAnswer((invocation) async {
          final callback =
              invocation.positionalArguments.single
                  as FutureOr<void> Function(MySQLConnection);
          await callback(connection);
        });

        await MySqlAdminRefundsRepository(
          connectionFactory: () async => connection,
        ).resolveReport(
          14,
          const AdminIdentity(id: 7, name: 'Admin'),
          'Reviewed this report',
        );

        final update = statements.singleWhere(
          (call) => call.$1.contains('UPDATE report'),
        );
        expect(update.$1, contains('AdminID = :adminId'));
        expect(update.$1, contains('ResolutionNote = :note'));
        expect(update.$1, contains('ResolvedAtUtc = UTC_TIMESTAMP(6)'));
        expect(update.$1, isNot(contains('UserReport')));
        expect(update.$2, {
          'note': 'Reviewed this report',
          'adminId': 7,
          'id': 14,
        });
      },
    );

    test('does not resolve an already-resolved Report again', () async {
      final connection = _MockConnection();
      when(() => connection.connected).thenReturn(false);
      final statements = <String>[];
      when(() => connection.execute(any(), any())).thenAnswer((
        invocation,
      ) async {
        final sql = invocation.positionalArguments.first as String;
        statements.add(sql);
        if (sql.contains('SELECT Status FROM report')) {
          return _result([
            {'Status': 'Resolved'},
          ]);
        }
        fail('Unexpected query: $sql');
      });
      when(
        () => connection.transactional<void>(any()),
      ).thenAnswer((invocation) async {
        final callback =
            invocation.positionalArguments.single
                as FutureOr<void> Function(MySQLConnection);
        await callback(connection);
      });

      await expectLater(
        MySqlAdminRefundsRepository(
          connectionFactory: () async => connection,
        ).resolveReport(
          14,
          const AdminIdentity(id: 7, name: 'Admin'),
          'Reviewed this report',
        ),
        throwsA(isA<AdminRefundConflict>()),
      );
      expect(statements, hasLength(1));
      expect(statements.single, contains('FROM report'));
    });
  });
}
