import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';
import 'package:theo_tutoring_backend/admin_payouts.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/payout_finance.dart';

/// POST /admin/payouts/<id>/approve: Pending -> Approved.
Future<Response> onRequest(RequestContext context, String payoutId) =>
    handlePayoutAction(context, action: 'approve', payoutId: payoutId);

/// Shared by approve and mark-paid (permission admin.payouts.manage).
/// mark-paid takes an optional body {"reference": "<external payment
/// reference, up to 100 characters>"}. Marking a payout as paid records the
/// payment only; it moves no money. Both write an audit row.
Future<Response> handlePayoutAction(
  RequestContext context, {
  required String action,
  required String payoutId,
  AdminResolver? adminResolver,
  AdminPayoutsRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.post) {
    return _error(
      HttpStatus.methodNotAllowed,
      'Only POST requests are supported.',
    );
  }
  if (action != 'approve' && action != 'mark-paid') {
    return _error(HttpStatus.notFound, 'Unknown action.');
  }
  final id = parsePayoutId(payoutId);
  if (id == null) {
    return _error(
      HttpStatus.badRequest,
      'The payout ID must be a positive integer.',
    );
  }

  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.payouts.manage');
    final repository = (repositoryFactory ?? MySqlAdminPayoutsRepository.new)();
    if (action == 'approve') {
      await repository.approve(id, admin);
      return Response.json(body: {'ok': true, 'message': 'Payout approved.'});
    }
    final String? reference;
    try {
      reference = await _paymentReference(context.request);
    } on FormatException catch (e) {
      return _error(HttpStatus.badRequest, e.message);
    }
    await repository.markPaid(id, admin, reference: reference);
    return Response.json(
      body: {'ok': true, 'message': 'Payout marked as paid.'},
    );
  } on AuthTokenException catch (e) {
    return _error(HttpStatus.unauthorized, e.message);
  } on AdminAccessDenied catch (e) {
    return _error(HttpStatus.forbidden, e.message);
  } on AdminPayoutNotFound {
    return _error(HttpStatus.notFound, 'Payout not found.');
  } on AdminPayoutConflict catch (e) {
    return _error(HttpStatus.conflict, e.message);
  } catch (error) {
    final code = error is MySQLServerException
        ? ' MySQL ${error.errorCode}'
        : '';
    stderr.writeln('Admin payout $action failed (${error.runtimeType}$code).');
    return _error(
      HttpStatus.internalServerError,
      'The payout could not be updated.',
    );
  }
}

/// The optional reference from a mark-paid body; an empty body means none.
Future<String?> _paymentReference(Request request) async {
  final text = (await request.body()).trim();
  if (text.isEmpty) return null;
  final Object? body;
  try {
    body = jsonDecode(text);
  } on FormatException {
    throw const FormatException('The request body must be JSON.');
  }
  if (body is! Map) {
    throw const FormatException('The request body must be a JSON object.');
  }
  return normalisePaymentReference(body['reference']);
}

Response _error(int status, String message) =>
    Response.json(statusCode: status, body: {'error': message});
