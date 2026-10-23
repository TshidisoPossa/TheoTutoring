import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/mysql_client.dart';

import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';
import '../../../lib/tutor_account_status.dart';
import '../../../lib/tutor_application_status.dart';

// POST /auth/tutor/availability  (Tutor registration, Step 3 of 3)
//
//
//
// Submitting this step completes registration: the account moves from
// 'incomplete' to 'pending' and a TutorApplication is created for the
// administrator to review. The tutor stays hidden from students until
// the application is approved.

const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

const _maxSlots = 30;

final _timePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

typedef TutorAvailabilitySlot = ({
  String day,
  int startMinutes,
  int endMinutes,
});

Future<Response> onRequest(RequestContext context) =>
    handleTutorAvailability(context);

/// Optional seams let the focused integration test use only its isolated DB
/// and a verified test identity, while production keeps the normal defaults.
Future<Response> handleTutorAvailability(
  RequestContext context, {
  Future<FirebaseUser> Function(String?) tokenVerifier = verifyFirebaseToken,
  Future<MySQLConnection> Function() connectionFactory = getConnection,
}) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(405, 'Method not allowed');
  }

  try {
    // ── Verify the Firebase ID token ──
    final FirebaseUser firebaseUser;
    try {
      firebaseUser = await tokenVerifier(
        context.request.headers['Authorization'],
      );
    } on AuthTokenException catch (e) {
      return jsonError(401, e.message);
    }

    // ── Read and validate the availability slots ──
    final body = await readJsonObject(context);
    final slots = parseTutorAvailabilitySlots(body['availability']);

    final db = await connectionFactory();

    // ── Find the tutor and check that Step 2 is complete ──
    final tutorResult = await db.execute(
      '''
      SELECT tp.TutorID, u.UserId, u.AccountStatus, tp.Bio, tp.Certificate,
             (SELECT COUNT(*) FROM TutorSubjects ts
               WHERE ts.TutorID = tp.TutorID) AS SubjectCount,
             (SELECT COUNT(*) FROM Qualification q
               WHERE q.TutorID = tp.TutorID) AS QualificationCount
      FROM TutorProfile tp
      INNER JOIN User u ON tp.UserId = u.UserId
      WHERE u.FirebaseUid = :uid AND u.Role = 'tutor'
      ''',
      {'uid': firebaseUser.uid},
    );

    if (tutorResult.rows.isEmpty) {
      return jsonError(
        404,
        'Tutor account not found. Please complete Step 1 first.',
      );
    }

    final row = tutorResult.rows.first;
    final tutorId = int.parse(row.colByName('TutorID')!);
    final userId = int.parse(row.colByName('UserId')!);
    final accountStatus = row.colByName('AccountStatus');

    if (!canSubmitTutorAvailability(accountStatus)) {
      return jsonError(
        403,
        'This account cannot continue tutor registration.',
      );
    }

    final step2Complete =
        (row.colByName('Bio') ?? '').isNotEmpty &&
        (row.colByName('Certificate') ?? '').isNotEmpty &&
        int.parse(row.colByName('SubjectCount') ?? '0') > 0 &&
        int.parse(row.colByName('QualificationCount') ?? '0') > 0;

    if (!step2Complete) {
      return jsonError(
        400,
        'Please complete your teaching profile (Step 2) first.',
      );
    }

    // ── Save slots, submit the application, all in one transaction ──
    final submitted = await db.transactional((conn) async {
      await conn.execute(
        '''
        SELECT TutApplication
        FROM TutorApplication
        WHERE TutorID = :tutorId
        ORDER BY TutApplication ASC
        FOR UPDATE
        ''',
        {'tutorId': tutorId},
      );
      await conn.execute(
        'SELECT TutorID FROM TutorProfile WHERE TutorID = :tutorId FOR UPDATE',
        {'tutorId': tutorId},
      );
      final lockedUser = await conn.execute(
        'SELECT AccountStatus FROM `User` WHERE UserId = :userId FOR UPDATE',
        {'userId': userId},
      );
      if (lockedUser.rows.isEmpty) {
        throw const TutorApplicationSubmissionBlocked();
      }
      final latest = await conn.execute(
        '''
        SELECT Status
        FROM TutorApplication
        WHERE TutorID = :tutorId
        ORDER BY SubmittedAt DESC, TutApplication DESC
        LIMIT 1
        FOR UPDATE
        ''',
        {'tutorId': tutorId},
      );
      final pendingApplications = await conn.execute(
        '''
        SELECT TutApplication
        FROM TutorApplication
        WHERE TutorID = :tutorId AND Status = 'Pending'
        FOR UPDATE
        ''',
        {'tutorId': tutorId},
      );
      final plan = planTutorApplicationSubmission(
        accountStatus: lockedUser.rows.first.colByName('AccountStatus'),
        requestAccountStatus: accountStatus,
        latestApplicationStatus: latest.rows.isEmpty
            ? null
            : latest.rows.first.colByName('Status'),
        hasPendingApplication: pendingApplications.rows.isNotEmpty,
      );
      if (plan == TutorApplicationSubmissionPlan.blocked) {
        throw const TutorApplicationSubmissionBlocked();
      }
      if (plan == TutorApplicationSubmissionPlan.alreadyPending) return false;

      await conn.execute(
        'DELETE FROM TutAvailability WHERE TutorID = :tutorId',
        {'tutorId': tutorId},
      );

      for (final slot in slots) {
        await conn.execute(
          '''
          INSERT INTO TutAvailability (TutorID, Day, StartTime, end_Time)
          VALUES (:tutorId, :day, :startTime, :endTime)
          ''',
          {
            'tutorId': tutorId,
            'day': slot.day,
            'startTime': _formatTime(slot.startMinutes),
            'endTime': _formatTime(slot.endMinutes),
          },
        );
      }

      await conn.execute(
        '''
        UPDATE User SET AccountStatus = 'Pending'
        WHERE UserId = :userId
        ''',
        {'userId': userId},
      );
      await conn.execute(
        '''
        UPDATE TutorProfile
        SET VerificationStat = 'Pending'
        WHERE TutorID = :tutorId
        ''',
        {'tutorId': tutorId},
      );
      await conn.execute(
        '''
        INSERT INTO TutorApplication (TutorID, Status, SubmittedAt)
        VALUES (:tutorId, 'Pending', NOW())
        ''',
        {'tutorId': tutorId},
      );
      return true;
    });

    return Response.json(
      body: {
        'message': submitted
            ? 'Registration complete! Your application is under review.'
            : 'Your application is already under review.',
        'tutorId': tutorId,
        'status': 'Pending',
      },
    );
  } on TutorApplicationSubmissionBlocked {
    return jsonError(
      409,
      'This account cannot submit another tutor application in its current state.',
    );
  } on FormatException catch (e) {
    return jsonError(400, e.message);
  } catch (e) {
    print('❌ Error in tutor availability: $e');
    return jsonError(500, 'Something went wrong. Please try again.');
  }
}

/// Reads and validates the availability list.
/// Rules: at least one slot, Monday to Saturday only, 24-hour HH:mm times,
/// start before end, and no overlapping slots on the same day.
List<TutorAvailabilitySlot> parseTutorAvailabilitySlots(Object? value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException(
      'Please select at least one available time slot.',
    );
  }
  if (value.length > _maxSlots) {
    throw const FormatException('You can add up to $_maxSlots time slots.');
  }

  final slots = <TutorAvailabilitySlot>[];

  for (final item in value) {
    if (item is! Map<String, dynamic>) {
      throw const FormatException(
        'Each time slot needs a day, a start time and an end time.',
      );
    }

    final day = optionalString(item, 'day', maxLength: 20);
    if (day == null || !_days.contains(day)) {
      throw const FormatException('Day must be a day from Monday to Saturday.');
    }

    final start = _parseTime(optionalString(item, 'startTime', maxLength: 5));
    final end = _parseTime(optionalString(item, 'endTime', maxLength: 5));
    if (start == null || end == null) {
      throw const FormatException(
        'Times must use the 24-hour HH:mm format, e.g. 08:00.',
      );
    }
    if (start >= end) {
      throw FormatException(
        'On $day, the start time must be before the end time.',
      );
    }

    slots.add((day: day, startMinutes: start, endMinutes: end));
  }

  // ── Check for overlapping slots on the same day ──
  // Back-to-back slots (one ends at 12:00, the next starts at 12:00) are fine.
  for (final day in _days) {
    final daySlots = slots.where((s) => s.day == day).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    for (var i = 1; i < daySlots.length; i++) {
      if (daySlots[i].startMinutes < daySlots[i - 1].endMinutes) {
        throw FormatException('Some of your time slots on $day overlap.');
      }
    }
  }

  return slots;
}

/// Converts "HH:mm" to minutes after midnight, or null if invalid.
int? _parseTime(String? value) {
  if (value == null) return null;
  final match = _timePattern.firstMatch(value);
  if (match == null) return null;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

/// Converts minutes after midnight to MySQL TIME format "HH:mm:00".
String _formatTime(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m:00';
}
