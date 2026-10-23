import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_applications.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

Future<Response> onRequest(RequestContext context) =>
    handleApplicationReview(context);

Future<Response> handleApplicationReview(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminApplicationsRepositoryFactory? repositoryFactory,
}) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only POST requests are supported.'},
    );
  }

  try {
    final authorization =
        context.request.headers['authorization'] ??
        context.request.headers['Authorization'];
    final admin = await (adminResolver ?? resolveAdmin)(authorization);
    requireAdminPermission(admin, 'admin.applications.review');
    final body = await readJsonObject(context);
    final rawId = body['applicationId'];
    final applicationId = rawId is int
        ? rawId
        : rawId is String
        ? int.tryParse(rawId.trim())
        : null;
    if (applicationId == null || applicationId <= 0) {
      throw const FormatException('A valid applicationId is required.');
    }

    final rawDecision = body['decision'];
    if (rawDecision is! String) {
      throw const FormatException('Decision must be approve or reject.');
    }
    final decision = rawDecision.trim().toLowerCase();
    if (decision != 'approve' && decision != 'reject') {
      throw const FormatException('Decision must be approve or reject.');
    }
    final feedback = optionalString(body, 'feedback');
    if (decision == 'reject' && feedback == null) {
      throw const FormatException('Feedback is required when rejecting.');
    }

    await (repositoryFactory ?? MySqlAdminApplicationsRepository.new)()
        .reviewApplication(
          applicationId: applicationId,
          decision: decision,
          feedback: feedback,
          admin: admin,
        );

    return Response.json(
      body: {
        'message': decision == 'approve'
            ? 'Application approved successfully.'
            : 'Application rejected successfully.',
        'applicationId': applicationId,
        'status': decision == 'approve' ? 'Approved' : 'Rejected',
      },
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
  } on FormatException catch (error) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': error.message},
    );
  } on AdminApplicationValidation catch (error) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': error.message},
    );
  } on AdminApplicationNotFound {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'Tutor application not found.'},
    );
  } on AdminApplicationConflict catch (error) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': error.message},
    );
  } catch (error) {
    stderr.writeln('Admin application review failed (${error.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Tutor application could not be reviewed.'},
    );
  }
}
