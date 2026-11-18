import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/tutor_reports.dart';
// Relative import: must be the same TutorSession type the middleware provides.
import '../../../lib/tutorlanding_session.dart';

// POST /TutorLandingpage/reports  (Report a Problem on the tutor Profile)
//
// body: {"category": "Student issues", "description": "...",
//        "studentUserId": 15}
// studentUserId is only for Student issues. See lib/tutor_reports.dart.
Future<Response> onRequest(RequestContext context) async {
  final (response, body) = await readResponseJson(
    await handleFileTutorReport(
      context,
      tutorId: context.read<TutorSession>().tutorId,
    ),
  );
  // A new report: tell the admins (in the background)
  final reportId = body?['reportId'];
  if (response.statusCode == 200 && reportId is int) {
    announceToAdmins(() => notifyAdminsOfReport(reportId));
  }
  return response;
}
