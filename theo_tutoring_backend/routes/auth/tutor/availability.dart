import 'package:dart_frog/dart_frog.dart';

import '../../../lib/database.dart';
import '../../../lib/firebase_auth.dart';
import '../../../lib/request_utils.dart';

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

typedef _Slot = ({String day, int startMinutes, int endMinutes});

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(405, 'Method not allowed');
  }

  try {
    // ── Verify the Firebase ID token ──
    final FirebaseUser firebaseUser;
    try {
      firebaseUser = await verifyFirebaseToken(
        context.request.headers['Authorization'],
      );
    } on AuthTokenException catch (e) {
      return jsonError(401, e.message);
    }

    // ── Read and validate the availability slots ──
    final body = await readJsonObject(context);
    final slots = _parseSlots(body['availability']);

    final db = await getConnection();

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
      WHERE u.UID = :uid AND u.Role = 'tutor'
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

    if (accountStatus == 'suspended' || accountStatus == 'rejected') {
      return jsonError(
        403,
        'This account cannot be updated. Please contact support.',
      );
    }

    // This endpoint is only for registration. Approved tutors change their
    // availability from the profile edit screen, which must protect slots
    // that already have upcoming bookings.
    if (accountStatus == 'active') {
      return jsonError(
        409,
        'Your registration is already approved. '
        'Update your availability from your profile instead.',
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
    await db.transactional((conn) async {
      await conn.execute(
        'DELETE FROM TutAvailability WHERE TutorID = :tutorId',
        {'tutorId': tutorId},
      );

      for (final slot in slots) {
        await conn.execute(
          '''
          INSERT INTO TutAvailability (TutorID, Day, StartTime, EndTime)
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

      // Registration is now complete: incomplete → pending.
      await conn.execute(
        '''
        UPDATE User SET AccountStatus = 'pending'
        WHERE UserId = :userId AND AccountStatus = 'incomplete'
        ''',
        {'userId': userId},
      );

      // Create the application for the admin queue, unless the tutor is
      // resubmitting Step 3 and already has one.
      final existingApplication = await conn.execute(
        'SELECT TutApplicationID FROM TutorApplication WHERE UserID = :userId',
        {'userId': userId},
      );

      if (existingApplication.rows.isEmpty) {
        await conn.execute(
          '''
          INSERT INTO TutorApplication (UserID, Status, Submitted_at)
          VALUES (:userId, 'pending', NOW())
          ''',
          {'userId': userId},
        );
      }
    });

    return Response.json(
      body: {
        'message':
            'Registration complete! Your application is under review. '
            'You will be notified once an admin approves your account.',
        'tutorId': tutorId,
        'status': 'pending',
      },
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
List<_Slot> _parseSlots(Object? value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException(
      'Please select at least one available time slot.',
    );
  }
  if (value.length > _maxSlots) {
    throw const FormatException('You can add up to $_maxSlots time slots.');
  }

  final slots = <_Slot>[];

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
