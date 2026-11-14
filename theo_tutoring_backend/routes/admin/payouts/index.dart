import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';
import 'package:theo_tutoring_backend/admin_payouts.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminPayouts(context);

/// GET /admin/payouts?status=all|pending|approved|paid&page=&pageSize=
/// The admin Payouts page (permission admin.finance.read).
///
/// { adminName, total, page, pageSize,
///   summary: { pendingCount, pendingNetAmount, approvedCount,
///              approvedNetAmount, paidCount, paidNetAmount },
///   payouts: [ { payoutId, status, amount, commissionAmount, netAmount,
///                createdAt, approvedAt, paidAt, approvedBy,
///                tutor: {tutorId, name, email},
///                booking: {bookingId, studentName, subject, date,
///                          startTime, endTime, status} } ] }
Future<Response> handleAdminPayouts(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminPayoutsRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.get) {
    return _error(
      HttpStatus.methodNotAllowed,
      'Only GET requests are supported.',
    );
  }

  final params = context.request.uri.queryParameters;
  final status = params['status'] ?? 'all';
  if (!adminPayoutStatuses.containsKey(status)) {
    return _error(
      HttpStatus.badRequest,
      'Status must be all, pending, approved, or paid.',
    );
  }
  final page = int.tryParse(params['page'] ?? '1');
  final pageSize = int.tryParse(params['pageSize'] ?? '20');
  if (page == null ||
      page < 1 ||
      pageSize == null ||
      pageSize < 1 ||
      pageSize > 100) {
    return _error(
      HttpStatus.badRequest,
      'page must be 1 or more and pageSize 1-100.',
    );
  }

  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.finance.read');
    final result =
        await (repositoryFactory ?? MySqlAdminPayoutsRepository.new)().list(
          AdminPayoutQuery(
            status: adminPayoutStatuses[status],
            page: page,
            pageSize: pageSize,
          ),
        );
    return Response.json(body: {...result, 'adminName': admin.name});
  } on AuthTokenException catch (e) {
    return _error(HttpStatus.unauthorized, e.message);
  } on AdminAccessDenied catch (e) {
    return _error(HttpStatus.forbidden, e.message);
  } catch (error) {
    if (error is MySQLServerException) {
      stderr.writeln('Admin payouts lookup failed (MySQL ${error.errorCode}).');
      // 1146: a table the query needs (payout) is missing on this server.
      if (error.errorCode == 1146) {
        return _error(
          HttpStatus.serviceUnavailable,
          'Payouts is not set up on this server yet: required database '
          'tables are missing.',
        );
      }
    } else {
      stderr.writeln('Admin payouts lookup failed (${error.runtimeType}).');
    }
    return _error(
      HttpStatus.internalServerError,
      'Payouts are temporarily unavailable.',
    );
  }
}

Response _error(int status, String message) =>
    Response.json(statusCode: status, body: {'error': message});
