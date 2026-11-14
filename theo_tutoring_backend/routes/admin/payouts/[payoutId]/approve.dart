import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_payouts.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

/// POST /admin/payouts/<id>/approve: Pending -> Approved.
Future<Response> onRequest(RequestContext context, String payoutId) =>
    handlePayoutAction(context, action: 'approve', payoutId: payoutId);

/// Shared by approve and mark-paid (permission admin.payouts.manage).
/// Marking a payout as paid records the status only; it moves no money.
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
    await repository.markPaid(id, admin);
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
    stderr.writeln('Admin payout $action failed (${error.runtimeType}).');
    return _error(
      HttpStatus.internalServerError,
      'The payout could not be updated.',
    );
  }
}

Response _error(int status, String message) =>
    Response.json(statusCode: status, body: {'error': message});
