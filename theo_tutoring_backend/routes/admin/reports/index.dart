import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_reports.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/tutor_reports.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminReports(context);

/// GET /admin/reports?status=all|open|under-review|resolved&category=&page=&pageSize=
/// The Report table for the admin Reports page, newest first: tutors'
/// Report a Problem (category Payments & Payouts, Student issues or Other)
/// and students' lesson/tutor reports (category null).
/// Needs permission admin.reports.read.
Future<Response> handleAdminReports(
  RequestContext context, {
  AdminResolver? adminResolver,
  AdminReportRepository? repository,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }
  final params = context.request.uri.queryParameters;
  final filter = params['status'] ?? 'all';
  final category = params['category']?.trim();
  final page = int.tryParse(params['page'] ?? '1');
  final pageSize = int.tryParse(params['pageSize'] ?? '20');
  if (!reportStatusFilters.containsKey(filter)) {
    return _bad('Unknown status filter.');
  }
  if (category != null &&
      category.isNotEmpty &&
      !tutorReportCategories.contains(category)) {
    return _bad('Unknown category.');
  }
  if (page == null ||
      page < 1 ||
      pageSize == null ||
      pageSize < 1 ||
      pageSize > 100) {
    return _bad('page must be 1 or more and pageSize 1-100.');
  }
  try {
    final admin = await (adminResolver ?? resolveAdmin)(
      context.request.headers['authorization'] ??
          context.request.headers['Authorization'],
    );
    requireAdminPermission(admin, 'admin.reports.read');
    final result = await (repository ?? MySqlAdminReportRepository()).list(
      status: reportStatusFilters[filter],
      category: category == null || category.isEmpty ? null : category,
      page: page,
      pageSize: pageSize,
    );
    return Response.json(body: {...result, 'adminName': admin.name});
  } on AuthTokenException catch (e) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': e.message},
    );
  } on AdminAccessDenied catch (e) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': e.message},
    );
  } catch (error) {
    stderr.writeln('Admin reports failed (${error.runtimeType}): $error');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'The reports could not be loaded.'},
    );
  }
}

Response _bad(String message) => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {'error': message},
);
