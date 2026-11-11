import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';
import 'package:theo_tutoring_backend/booking_purchase.dart';
import 'package:theo_tutoring_backend/booking_purchase_repository.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

typedef PurchaseStudentIdResolver = Future<int> Function(String? authorization);
typedef BookingPurchaseRepositoryFactory =
    Future<BookingPurchaseRepository> Function();

Future<Response> onRequest(RequestContext context) =>
    handleCreateBookingPurchase(context);

Future<Response> handleCreateBookingPurchase(
  RequestContext context, {
  BookingPurchaseRepositoryFactory? repositoryFactory,
  PurchaseStudentIdResolver? studentIdResolver,
  DateTime Function()? clock,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only POST requests are supported.'},
    );
  }

  late final Object? body;
  try {
    body = await context.request.json();
  } on FormatException {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'The request body must contain valid JSON.'},
    );
  }

  late final CreateBookingPurchaseCommand command;
  try {
    command = CreateBookingPurchaseCommand.parse(
      body,
      nowUtc: (clock ?? DateTime.now)().toUtc(),
    );
  } on BookingPurchaseRequestException catch (error) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': error.message},
    );
  } on FormatException catch (error) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': error.message},
    );
  }

  final authorization =
      context.request.headers['authorization'] ??
      context.request.headers['Authorization'];
  try {
    final studentId = await (studentIdResolver ?? _resolveStudentId)(
      authorization,
    );
    final repository = await (repositoryFactory ?? _defaultRepositoryFactory)();
    final receipt = await repository.create(studentId, command);
    return Response.json(
      statusCode: receipt.replayed ? HttpStatus.ok : HttpStatus.created,
      body: receipt.toJson(),
    );
  } on AuthTokenException catch (error) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': error.message},
    );
  } on PurchaseStudentException catch (error) {
    return Response.json(
      statusCode: error.statusCode,
      body: {'error': error.message},
    );
  } on BookingPurchaseConflict catch (error) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': error.message, 'code': error.code},
    );
  } on BookingPurchaseUnavailable {
    final recurring = command.schedulingMode == 'weekly';
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {
        'error': recurring
            ? 'A proposed recurring slot is unavailable. Select '
                  'alternatives for the affected lessons and retry.'
            : 'One or more selected lesson slots are unavailable.',
        'code': recurring
            ? 'recurring_alternatives_required'
            : 'slot_unavailable',
        'alternativesRequired': recurring,
      },
    );
  } on BookingPurchaseNotFound {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'The approved tutor or tutor subject was not found.'},
    );
  } on BookingPurchaseServiceUnavailable {
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'error':
            'Booking is temporarily unavailable. Retry with the same idempotency key.',
      },
    );
  } on MySQLServerException {
    return _unexpectedDatabaseFailure();
  } on MySQLClientException {
    return _unexpectedDatabaseFailure();
  } catch (error) {
    stderr.writeln('Booking purchase request failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Booking could not be created.'},
    );
  }
}

Response _unexpectedDatabaseFailure() {
  stderr.writeln('Booking purchase database operation failed.');
  return Response.json(
    statusCode: HttpStatus.serviceUnavailable,
    body: {
      'error':
          'Booking is temporarily unavailable. Retry with the same idempotency key.',
    },
  );
}

Future<BookingPurchaseRepository> _defaultRepositoryFactory() async =>
    MySqlBookingPurchaseRepository();

class PurchaseStudentException implements Exception {
  const PurchaseStudentException(this.statusCode, this.message);

  final int statusCode;
  final String message;
}

Future<int> _resolveStudentId(String? authorization) async {
  final firebaseUser = await verifyFirebaseToken(authorization);
  final connection = await getConnection();
  final result = await connection.execute(
    '''
    SELECT sp.StudentID, u.AccountStatus
    FROM `user` u
    INNER JOIN studentprofile sp ON sp.UserID = u.UserId
    WHERE u.FirebaseUid = :uid AND u.Role = 'student'
    LIMIT 1
    ''',
    {'uid': firebaseUser.uid},
  );
  if (result.rows.isEmpty) {
    throw const PurchaseStudentException(
      HttpStatus.notFound,
      'Student account or profile not found.',
    );
  }
  if (result.rows.first.str('AccountStatus') != 'Active') {
    throw const PurchaseStudentException(
      HttpStatus.forbidden,
      'An active student account is required.',
    );
  }
  final id = int.tryParse(result.rows.first.str('StudentID') ?? '');
  if (id == null || id < 1) {
    throw const BookingPurchaseServiceUnavailable();
  }
  return id;
}
