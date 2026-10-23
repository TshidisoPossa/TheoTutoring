import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_session_rate.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminSessionRate(context);

Future<Response> handleAdminSessionRate(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminSessionRateRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.get &&
      context.request.method != HttpMethod.put) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET and PUT requests are supported.'},
    );
  }

  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(
      admin,
      context.request.method == HttpMethod.get
          ? 'admin.settings.rate.read'
          : 'admin.settings.rate.write',
    );
    final repository =
        (repositoryFactory ?? MySqlAdminSessionRateRepository.new)();
    if (context.request.method == HttpMethod.get) {
      return Response.json(body: await repository.fetch(admin.name));
    }

    final decoded = jsonDecode(await context.request.body());
    if (decoded is! Map<String, dynamic>) {
      throw const AdminSessionRateValidation(
        'Request body must be a JSON object.',
      );
    }
    final body = decoded;
    final amount = _validatedAmount(body['amount']);
    return Response.json(
      body: await repository.update(amount, admin),
    );
  } on AuthTokenException catch (error) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': error.message},
    );
  } on AdminAccessDenied catch (error) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': error.message},
    );
  } on AdminSessionRateValidation catch (error) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': error.message},
    );
  } on AdminSessionRateNotConfigured {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {
        'error':
            'Platform settings are not configured; contact the '
            'database administrator.',
      },
    );
  } on FormatException {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Request body must be valid JSON.'},
    );
  } catch (error) {
    stderr.writeln('Admin session rate failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Session rate settings are temporarily unavailable.'},
    );
  }
}

String _validatedAmount(Object? value) {
  final text = value is num ? value.toString() : value?.toString();
  if (text == null || !RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(text)) {
    throw const AdminSessionRateValidation(
      'Amount must be a positive value with up to two decimal places.',
    );
  }
  final parts = text.split('.');
  final cents =
      BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(2, '0'));
  if (cents == BigInt.zero) {
    throw const AdminSessionRateValidation('Amount must be greater than zero.');
  }
  return text;
}
