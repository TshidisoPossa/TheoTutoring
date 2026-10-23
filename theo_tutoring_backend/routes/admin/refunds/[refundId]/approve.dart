import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context, String refundId) =>
    handleRefundAction(context, action: 'approve', refundId: refundId);

Future<Response> handleRefundAction(
  RequestContext context, {
  required String action,
  String? refundId,
  AdminResolver? adminResolver,
  AdminRefundRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: 405,
      body: {'error': 'Only POST requests are supported.'},
    );
  }

  final rawId = refundId ?? _refundIdFromPath(context.request.uri.pathSegments);
  final isReportResolution = action == 'resolve';
  final int id;
  try {
    id = isReportResolution ? parseReportId(rawId) : parseRefundId(rawId);
  } on AdminRefundValidation catch (error) {
    return Response.json(statusCode: 400, body: {'error': error.message});
  }

  final Object? body;
  try {
    body = await context.request.json();
  } on FormatException {
    return Response.json(
      statusCode: 400,
      body: {'error': 'The request body must contain valid JSON.'},
    );
  }
  if (body is! Map<String, dynamic>) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'The request body must be a JSON object.'},
    );
  }

  final String? reason;
  final double? percentage;
  try {
    switch (action) {
      case 'approve':
        reason = null;
        percentage = null;
      case 'deny':
        reason = body['reason'] is String
            ? (body['reason'] as String).trim()
            : null;
        validateReason(reason, fieldName: 'Reason');
        percentage = null;
      case 'override':
        reason = body['reason'] is String
            ? (body['reason'] as String).trim()
            : null;
        validateReason(reason, fieldName: 'Reason');
        percentage = parseRefundPercentage(body['refundPercentage']);
      case 'resolve':
        reason = body['note'] is String
            ? (body['note'] as String).trim()
            : null;
        validateReason(reason, fieldName: 'Note');
        percentage = null;
      default:
        return Response.json(
          statusCode: 404,
          body: {'error': 'Unknown action.'},
        );
    }
  } on AdminRefundValidation catch (error) {
    return Response.json(statusCode: 400, body: {'error': error.message});
  }

  final authorization =
      context.request.headers['authorization'] ??
      context.request.headers['Authorization'];
  try {
    final admin = await (adminResolver ?? resolveAdmin)(authorization);
    requireAdminPermission(
      admin,
      isReportResolution ? 'admin.reports.resolve' : 'admin.refunds.decide',
    );
    final repository = (repositoryFactory ?? MySqlAdminRefundsRepository.new)();
    if (isReportResolution) {
      await repository.resolveReport(id, admin, reason!);
      return Response.json(
        body: {'ok': true, 'message': 'Report marked as resolved.'},
      );
    }
    switch (action) {
      case 'approve':
        await repository.approve(id, admin);
      case 'deny':
        await repository.deny(id, admin, reason!);
      case 'override':
        await repository.overrideDecision(id, admin, percentage!, reason!);
    }
    return Response.json(
      body: {'ok': true, 'message': 'Refund decision recorded.'},
    );
  } on AuthTokenException catch (error) {
    return Response.json(statusCode: 401, body: {'error': error.message});
  } on AdminAccessDenied catch (error) {
    return Response.json(statusCode: 403, body: {'error': error.message});
  } on AdminRefundNotFound {
    return Response.json(statusCode: 404, body: {'error': 'Refund not found.'});
  } on AdminRefundConflict catch (error) {
    return Response.json(statusCode: 409, body: {'error': error.message});
  } catch (error) {
    stderr.writeln('Admin refund action failed (${error.runtimeType}).');
    return Response.json(
      statusCode: 500,
      body: {'error': 'The refund decision could not be recorded.'},
    );
  }
}

String? _refundIdFromPath(List<String> pathSegments) {
  final refundsIndex = pathSegments.lastIndexOf('refunds');
  if (refundsIndex < 0 || refundsIndex + 1 >= pathSegments.length) return null;
  return pathSegments[refundsIndex + 1];
}
