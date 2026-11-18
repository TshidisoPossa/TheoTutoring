import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';
import 'package:theo_tutoring_backend/admin_payouts.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleGeneratePayouts(context);

/// POST /admin/payouts/generate (permission admin.payouts.manage).
///
/// Creates a Pending payout for every paid lesson that has finished, has no
/// refund (other than a rejected one) and has no payout yet
/// (lib/payout_finance.dart). Safe to repeat: existing payouts are never
/// changed or duplicated, and concurrent requests are serialised.
///
/// 200 { ok: true, generated: <count>, message }
/// 409 another generation is running, or payouts appeared concurrently.
Future<Response> handleGeneratePayouts(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminPayoutsRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.post) {
    return _error(
      HttpStatus.methodNotAllowed,
      'Only POST requests are supported.',
    );
  }
  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.payouts.manage');
    final generated = await (repositoryFactory ??
            MySqlAdminPayoutsRepository.new)()
        .generate(admin);
    return Response.json(
      body: {
        'ok': true,
        'generated': generated,
        'message': switch (generated) {
          0 => 'No new eligible lessons: no payouts were generated.',
          1 => '1 payout generated.',
          _ => '$generated payouts generated.',
        },
      },
    );
  } on AuthTokenException catch (e) {
    return _error(HttpStatus.unauthorized, e.message);
  } on AdminAccessDenied catch (e) {
    return _error(HttpStatus.forbidden, e.message);
  } on AdminPayoutConflict catch (e) {
    return _error(HttpStatus.conflict, e.message);
  } catch (error) {
    if (error is MySQLServerException) {
      stderr.writeln('Payout generation failed (MySQL ${error.errorCode}).');
      if (error.errorCode == 1146 || error.errorCode == 1054) {
        return _error(
          HttpStatus.serviceUnavailable,
          'Payout generation is not set up on this server yet: apply the '
          'latest database migrations.',
        );
      }
    } else {
      stderr.writeln('Payout generation failed (${error.runtimeType}).');
    }
    return _error(
      HttpStatus.internalServerError,
      'Payouts could not be generated. Nothing was changed.',
    );
  }
}

Response _error(int status, String message) =>
    Response.json(statusCode: status, body: {'error': message});
