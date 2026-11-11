import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/availability_overrides.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/session_rate.dart';

class BookingAvailabilityUnavailable implements Exception {
  const BookingAvailabilityUnavailable();
}

class AvailabilityRequest {
  const AvailabilityRequest({
    required this.studentId,
    required this.tutorId,
    required this.subjectId,
    required this.from,
    required this.through,
    required this.nowUtc,
  });

  final int studentId;
  final int tutorId;
  final int subjectId;
  final BookingDate from;
  final BookingDate through;
  final DateTime nowUtc;
}

class AvailabilitySnapshot {
  const AvailabilitySnapshot({
    required this.weeklyAvailability,
    required this.busyIntervals,
    required this.platformRate,
    this.availabilityOverrides = const [],
  });

  final List<WeeklyAvailability> weeklyAvailability;

  /// One-off date changes (day off / different hours) inside the range.
  final List<AvailabilityOverride> availabilityOverrides;
  final List<LessonInterval> busyIntervals;
  final String platformRate;
}

abstract interface class BookingAvailabilityRepository {
  Future<AvailabilitySnapshot?> load(AvailabilityRequest request);
}

class MySqlBookingAvailabilityRepository
    implements BookingAvailabilityRepository {
  MySqlBookingAvailabilityRepository(this.connection);

  final MySQLConnection connection;

  @override
  Future<AvailabilitySnapshot?> load(AvailabilityRequest request) async {
    final tutor = await connection.execute(
      '''
      SELECT tp.TutorID
      FROM TutorProfile tp
      INNER JOIN `User` u ON u.UserId = tp.UserID
      WHERE tp.TutorID = :tutorId
        AND u.Role = 'tutor'
        AND u.AccountStatus = 'Active'
        AND tp.VerificationStat = 'Approved'
        AND EXISTS (
          SELECT 1 FROM TutorApplication ta
          WHERE ta.TutorID = tp.TutorID AND ta.Status = 'Approved'
        )
        AND EXISTS (
          SELECT 1
          FROM TutorSubjects ts
          INNER JOIN Subjects s ON s.subjectId = ts.SubjectID
          WHERE ts.TutorID = tp.TutorID
            AND s.subjectId = :subjectId
        )
      LIMIT 1
      ''',
      {'tutorId': request.tutorId, 'subjectId': request.subjectId},
    );
    if (tutor.rows.isEmpty) return null;
    final resolvedTutorId = _databaseInt(
      tutor.rows.first.str('TutorID'),
    );
    if (resolvedTutorId != request.tutorId) {
      throw const BookingAvailabilityUnavailable();
    }

    final rate = await getCurrentSessionRate(connection);
    if (rate == null) {
      throw const BookingAvailabilityUnavailable(); // no rate set yet
    }

    final availabilityResult = await connection.execute(
      '''
      SELECT Day, StartTime, end_Time
      FROM TutAvailability
      WHERE TutorID = :tutorId
      ORDER BY Day, StartTime
      ''',
      {'tutorId': request.tutorId},
    );
    final weeklyAvailability = [
      for (final row in availabilityResult.rows)
        WeeklyAvailability(
          weekday: _weekdayNumber(
            _requiredDatabaseString(row.str('Day')),
          ),
          startMinutes: parseClockTime(
            _requiredDatabaseString(row.str('StartTime')),
          ),
          endMinutes: parseClockTime(
            _requiredDatabaseString(row.str('end_Time')),
          ),
        ),
    ];

    final parameters = {
      'tutorId': request.tutorId,
      'studentId': request.studentId,
      'fromDate': request.from.iso,
      'throughDate': request.through.iso,
    };
    final bookingResult = await connection.execute(
      '''
      SELECT Date, StartTime, EndTime
      FROM Booking
      WHERE Date BETWEEN :fromDate AND :throughDate
        AND Status = 'Confirmed'
        AND (TutorID = :tutorId OR StudentID = :studentId)
      ''',
      parameters,
    );
    final busyIntervals = <LessonInterval>[
      for (final row in bookingResult.rows)
        LessonInterval(
          date: BookingDate.parse(
            _requiredDatabaseString(row.date('Date')),
          ),
          startMinutes: parseClockTime(
            _requiredDatabaseString(row.str('StartTime')),
          ),
          endMinutes: parseClockTime(
            _requiredDatabaseString(row.str('EndTime')),
          ),
        ),
    ];

    final holdResult = await connection.execute(
      '''
      SELECT h.LessonDate, h.StartTime, h.EndTime
      FROM BookingSlotHold h
      INNER JOIN BookingPurchase p ON p.PurchaseID = h.PurchaseID
      WHERE h.LessonDate BETWEEN :fromDate AND :throughDate
        AND h.HoldStatus = 'Active'
        AND h.ExpiresAtUtc > UTC_TIMESTAMP(6)
        AND (h.TutorID = :tutorId OR p.StudentID = :studentId)
      ''',
      parameters,
    );
    busyIntervals.addAll([
      for (final row in holdResult.rows)
        LessonInterval(
          date: BookingDate.parse(
            _requiredDatabaseString(row.date('LessonDate')),
          ),
          startMinutes: parseClockTime(
            _requiredDatabaseString(row.str('StartTime')),
          ),
          endMinutes: parseClockTime(
            _requiredDatabaseString(row.str('EndTime')),
          ),
        ),
    ]);

    return AvailabilitySnapshot(
      weeklyAvailability: weeklyAvailability,
      busyIntervals: busyIntervals,
      platformRate: rate,
      availabilityOverrides: await loadAvailabilityOverrides(
        connection,
        request.tutorId,
        from: request.from,
        through: request.through,
      ),
    );
  }
}

String _requiredDatabaseString(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const BookingAvailabilityUnavailable();
  }
  return value;
}

int? _databaseInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

int _weekdayNumber(String day) {
  const weekdays = {
    'Monday': DateTime.monday,
    'Tuesday': DateTime.tuesday,
    'Wednesday': DateTime.wednesday,
    'Thursday': DateTime.thursday,
    'Friday': DateTime.friday,
    'Saturday': DateTime.saturday,
    'Sunday': DateTime.sunday,
  };
  final weekday = weekdays[day];
  if (weekday == null)
    throw const FormatException('Invalid availability weekday.');
  return weekday;
}
