import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_subjects.dart';

Future<Response> onRequest(RequestContext context) =>
    handleAdminSubjects(context, null);
