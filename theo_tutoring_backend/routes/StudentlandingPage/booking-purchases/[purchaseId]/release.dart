import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/exception.dart';
import 'package:theo_tutoring_backend/booking_purchase.dart';
import 'package:theo_tutoring_backend/booking_purchase_repository.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

typedef ReleaseStudentIdResolver = Future<int> Function(String? authorization);
typedef ReleaseRepositoryFactory =
    Future<BookingPurchaseReleaseRepository> Function();

// POST /StudentlandingPage/booking-purchases/{purchaseId}/release
//
// The student went back from payment to change their lessons: their own
// unpaid reservation is cancelled and its times are free again. Safe to
// retry; a paid (or being paid) purchase is refused with 409.
Future<Response> onRequest(RequestContext context, String purchaseId) =>
    handleReleasePurchase(context, routePurchaseId: purchaseId);

Future<Response> handleReleasePurchase(
  RequestContext context, {
  required String routePurchaseId,
  ReleaseRepositoryFactory? repositoryFactory,
  ReleaseStudentIdResolver? studentIdResolver,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only POST requests are supported.'},
    );
  }
  final purchaseId = int.tryParse(routePurchaseId);
  if (purchaseId == null || purchaseId < 1 || purchaseId > 2147483647) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'A valid purchase ID is required.'},
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
    final status = await repository.release(studentId, purchaseId);
    return Response.json(
      body: {'purchaseId': purchaseId, 'purchaseStatus': status},
    );
  } on AuthTokenException catch (error) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': error.message},
    );
  } on ReleaseStudentException catch (error) {
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
    return _unavailable();
  } on MySQLServerException {
    return _unavailable();
  } on MySQLClientException {
    return _unavailable();
  } catch (error) {
    stderr.writeln('Booking release request failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The reservation could not be released.'},
    );
  }
}

Response _unavailable() => Response.json(
  statusCode: HttpStatus.serviceUnavailable,
  body: {'error': 'Releasing is temporarily unavailable. Please retry.'},
);

Future<BookingPurchaseReleaseRepository> _defaultRepositoryFactory() async =>
    MySqlBookingPurchaseRepository();

class ReleaseStudentException implements Exception {
  const ReleaseStudentException(this.statusCode, this.message);

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
    throw const ReleaseStudentException(
      HttpStatus.notFound,
      'Student account or profile not found.',
    );
  }
  if (result.rows.first.str('AccountStatus') != 'Active') {
    throw const ReleaseStudentException(
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
