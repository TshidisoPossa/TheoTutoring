import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/booking_receipt.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

// GET /StudentlandingPage/booking-purchases/<PurchaseID>/receipt
// The Download Receipt button after a successful payment. Only the
// student who made the purchase gets it, and only once it is paid. See
// lib/booking_receipt.dart for what it contains.
Future<Response> onRequest(RequestContext context, String purchaseId) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }
  final id = int.tryParse(purchaseId);
  if (id == null || id <= 0) {
    return jsonError(HttpStatus.badRequest, 'A valid purchase ID is required.');
  }
  try {
    final identity = await verifyFirebaseToken(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    final receipt = await loadBookingReceipt(
      await getConnection(),
      firebaseUid: identity.uid,
      purchaseId: id,
    );
    return Response.json(body: receipt);
  } on AuthTokenException catch (error) {
    return jsonError(HttpStatus.unauthorized, error.message);
  } on ReceiptException catch (error) {
    return jsonError(error.statusCode, error.message);
  } catch (error, stackTrace) {
    stderr.writeln('Loading receipt $id failed: $error\n$stackTrace');
    return jsonError(
      HttpStatus.internalServerError,
      'The receipt could not be loaded. Please try again.',
    );
  }
}
