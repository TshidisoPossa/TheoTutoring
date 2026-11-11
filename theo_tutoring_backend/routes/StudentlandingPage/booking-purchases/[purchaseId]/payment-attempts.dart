import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';
import 'package:theo_tutoring_backend/booking_purchase.dart';
import 'package:theo_tutoring_backend/booking_purchase_repository.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/demo_payment_config.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/student_notifications.dart';
import 'package:theo_tutoring_backend/tutor_notifications.dart';

typedef PaymentStudentIdResolver = Future<int> Function(String? authorization);
typedef PaymentRepositoryFactory = Future<BookingPurchaseRepository> Function();

/// Announces a purchase that was just paid.
typedef PaidPurchaseNotifier = Future<void> Function(int purchaseId);

// The student gets "Payment successful", the tutor "New lesson booked".
// Neither can fail the payment: both only log their problems.
Future<void> _notifyPaid(int purchaseId) => Future.wait([
  notifyStudentOfPaidPurchase(purchaseId),
  notifyTutorOfPaidPurchase(purchaseId),
]);

Future<Response> onRequest(RequestContext context, String purchaseId) =>
    handleCreatePaymentAttempt(context, routePurchaseId: purchaseId);

Future<Response> handleCreatePaymentAttempt(
  RequestContext context, {
  String? routePurchaseId,
  PaymentRepositoryFactory? repositoryFactory,
  PaymentStudentIdResolver? studentIdResolver,
  DemoPaymentConfig? paymentConfig,
  PaidPurchaseNotifier? notifyPaid,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only POST requests are supported.'},
    );
  }
  if (!(paymentConfig ?? DemoPaymentConfig.current()).isEnabled) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': 'Demo payments are disabled in this environment.'},
    );
  }
  final purchaseId = routePurchaseId != null
      ? _positiveInt(routePurchaseId)
      : _purchaseId(context.request.uri.pathSegments);
  if (purchaseId == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'A valid purchase ID is required.'},
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
  late final CreatePaymentAttemptCommand command;
  try {
    command = CreatePaymentAttemptCommand.parse(body);
  } on BookingPurchaseRequestException catch (error) {
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
    final receipt = await repository.createPaymentAttempt(
      studentId,
      purchaseId,
      command,
    );
    // The lessons are now Confirmed. A replay was already announced.
    if (receipt.settled && !receipt.replayed) {
      await (notifyPaid ?? _notifyPaid)(purchaseId);
    }
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
  } on BookingPurchaseNotFound {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'Purchase not found.'},
    );
  } on BookingPurchaseServiceUnavailable {
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {'error': 'Payment attempt is temporarily unavailable.'},
    );
  } on MySQLServerException {
    return _databaseFailure();
  } on MySQLClientException {
    return _databaseFailure();
  } catch (error) {
    stderr.writeln('Payment attempt request failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Payment attempt could not be completed.'},
    );
  }
}

int? _purchaseId(List<String> segments) {
  final index = segments.lastIndexOf('booking-purchases');
  if (index < 0 ||
      index + 2 != segments.length - 1 ||
      segments.last != 'payment-attempts') {
    return null;
  }
  return _positiveInt(segments[index + 1]);
}

int? _positiveInt(String raw) {
  final value = int.tryParse(raw);
  return value != null && value > 0 ? value : null;
}

Response _databaseFailure() {
  stderr.writeln('Payment attempt database operation failed.');
  return Response.json(
    statusCode: HttpStatus.serviceUnavailable,
    body: {'error': 'Payment attempt is temporarily unavailable.'},
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
    FROM \`User\` u
    INNER JOIN StudentProfile sp ON sp.UserID = u.UserId
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
