import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/tutor_reports.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// GET /TutorLandingpage/reports/students  -> the students who have booked
// this tutor, for the Student issues dropdown. See lib/tutor_reports.dart.
Future<Response> onRequest(RequestContext context) =>
    handleReportableStudents(
      context,
      tutorId: context.read<TutorSession>().tutorId,
    );
