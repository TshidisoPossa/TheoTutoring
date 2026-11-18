import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Notifications for administrators: the same Firestore store students and
// tutors use (notifications/{firebaseUid}/items), written to every active
// admin when something needs their attention:
//
//   * a tutor submits an application        (ApplicationSubmitted)
//   * a student or tutor files a report     (ReportSubmitted)
//   * a cancelled paid lesson has a refund  (RefundRequested)
//
// Each event is announced once (fixed document ids). Telling the admins can
// never fail or slow the action that caused it: [announceToAdmins] runs in
// the background and only logs problems. Routes call these from their
// onRequest entry points, which tests do not use, so tests never write to
// the real Firestore.

NotificationStore? _store; // shared, so the Google access token is reused

/// Firebase UIDs of every active administrator.
Future<List<String>> activeAdminUids(MySQLConnection connection) async {
  final result = await connection.execute(
    '''
    SELECT u.FirebaseUid
    FROM `user` u
    INNER JOIN admin a ON a.UserId = u.UserId
    WHERE u.Role = 'admin' AND u.AccountStatus = 'Active'
    ''',
  );
  return [
    for (final row in result.rows)
      if (row.str('FirebaseUid') case final uid? when uid.isNotEmpty) uid,
  ];
}

/// Saves [notice] for every active admin. Returns how many were told.
Future<int> notifyAdmins(
  Notice notice, {
  MySQLConnection? connection,
  NotificationStore? store,
}) async {
  final uids = await activeAdminUids(connection ?? await getConnection());
  final target = store ?? (_store ??= NotificationStore.fromFirebaseAdmin());
  var told = 0;
  for (final uid in uids) {
    try {
      if (await notice.sendTo(uid, target)) told++;
    } catch (e) {
      stderr.writeln('Could not notify admin $uid (${notice.id}): $e');
    }
  }
  return told;
}

/// The JSON object in [response]'s body (null if it is not one), and an
/// identical response to send on: a body can only be read once.
Future<(Response, Map<String, dynamic>?)> readResponseJson(
  Response response,
) async {
  final text = await response.body();
  Map<String, dynamic>? json;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) json = decoded;
  } on FormatException {
    json = null;
  }
  return (
    Response(
      statusCode: response.statusCode,
      body: text,
      headers: response.headers,
    ),
    json,
  );
}

/// Runs [announce] in the background; any problem is only logged.
void announceToAdmins(Future<void> Function() announce) {
  unawaited(
    announce().catchError((Object e) {
      stderr.writeln('Could not notify the administrators: $e');
    }),
  );
}

/// "Lerato Mokoena submitted a tutor application."
Future<void> notifyAdminsOfApplication(int tutorId) async {
  final connection = await getConnection();
  final result = await connection.execute(
    '''
    SELECT u.Name,
      (SELECT MAX(ta.TutApplication) FROM tutorapplication ta
       WHERE ta.TutorID = tp.TutorID) AS ApplicationId,
      (SELECT COUNT(*) FROM tutorapplication ta
       WHERE ta.TutorID = tp.TutorID) AS Applications
    FROM tutorprofile tp
    INNER JOIN `user` u ON u.UserId = tp.UserID
    WHERE tp.TutorID = :tutorId
    ''',
    {'tutorId': tutorId},
  );
  if (result.rows.isEmpty) return;
  final row = result.rows.first;
  final name = row.str('Name') ?? 'A tutor';
  final resubmitted = (int.tryParse(row.str('Applications') ?? '') ?? 1) > 1;
  await notifyAdmins(
    Notice(
      id: 'admin-application-${row.str('ApplicationId') ?? tutorId}',
      type: NotificationType.applicationSubmitted,
      title: resubmitted
          ? 'Tutor application resubmitted'
          : 'New tutor application',
      body: '$name ${resubmitted ? 'resubmitted' : 'submitted'} a tutor '
          'application. Review it on the Applications page.',
    ),
    connection: connection,
  );
}

/// "A student reported Thabo Nkosi." [reportId] is report.ReportID.
Future<void> notifyAdminsOfReport(int reportId) async {
  final connection = await getConnection();
  final result = await connection.execute(
    '''
    SELECT reporter.Name AS ReporterName, reporter.Role AS ReporterRole,
      reported.Name AS ReportedName
    FROM report r
    INNER JOIN `user` reporter ON reporter.UserId = r.ReporterID
    LEFT JOIN `user` reported ON reported.UserId = r.ReportedUserID
    WHERE r.ReportID = :reportId
    ''',
    {'reportId': reportId},
  );
  final row = result.rows.isEmpty ? null : result.rows.first;
  final reporter = row?.str('ReporterName') ?? 'A user';
  final role = row?.str('ReporterRole');
  final reported = row?.str('ReportedName');
  await notifyAdmins(
    Notice(
      id: 'admin-report-$reportId',
      type: NotificationType.reportSubmitted,
      title: 'New report',
      body: '$reporter${role == null ? '' : ' ($role)'} filed a report'
          '${reported == null ? '' : ' about $reported'}. Review it on the '
          'Reports page.',
    ),
    connection: connection,
  );
}

/// "Refund of R185.00 to review" for booking [bookingId], cancelled by
/// [cancelledBy] ('student' or 'tutor').
Future<void> notifyAdminsOfRefund(
  int bookingId, {
  required String cancelledBy,
  String? amount,
}) async {
  await notifyAdmins(
    Notice(
      id: 'admin-refund-$bookingId',
      type: NotificationType.refundRequested,
      title: 'Refund to review',
      body: 'A $cancelledBy cancelled a paid lesson (booking #$bookingId)'
          '${amount == null ? '' : '. Refund: R$amount'}. Review it on the '
          'Refunds page.',
      bookingId: bookingId,
    ),
  );
}

/// After a tutor cancels or reschedules (lib/tutor_cancel_booking.dart): a
/// cancelled paid lesson leaves a refund for the admins to review.
void announceTutorCancelRefund(Response response, Map<String, dynamic>? body) {
  final bookingId = body?['bookingId'];
  final refund = body?['refundAmount'];
  if (response.statusCode == 200 && bookingId is int && refund != null) {
    announceToAdmins(
      () => notifyAdminsOfRefund(
        bookingId,
        cancelledBy: 'tutor',
        amount: '$refund',
      ),
    );
  }
}

/// The signed-in administrator on /admin/notifications routes: their
/// Firebase UID is where their notifications are stored.
class AdminNotificationUser {
  /// Creates the session.
  const AdminNotificationUser(this.uid);

  /// The admin's Firebase UID.
  final String uid;
}
